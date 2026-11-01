import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:battery_plus/battery_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import 'backend.dart';

/// 위치 공유가 시작되지 못한 이유 (홈 화면 경고에 표시)
enum SharingProblem { none, serviceOff, permissionDenied, permissionDeniedForever }

/// 내 위치를 수집해 서버에 올린다.
///
/// - users/{uid}.lastLocation : 최신 위치 (전원이 꺼져도 마지막 위치가 남는다)
/// - users/{uid}/locations    : 시간대별 이동경로
///
/// Android 에서는 네이티브 포그라운드 서비스(LocationTrackingService)가 앱 화면과 별도로
/// 수집해, 앱을 밀어서 닫거나 재부팅해도 계속 올린다. iOS 는 geolocator 백그라운드 위치를 쓴다.
class LocationService {
  LocationService._();
  static final instance = LocationService._();

  /// 이 거리 이상 움직이면 이동경로에 점을 추가한다.
  static const _historyMinDistanceM = 30.0;

  /// 이보다 오차가 큰 위치는 이동경로에 남기지 않는다.
  static const _historyMaxAccuracyM = 80.0;

  /// 이보다 오차가 큰 위치는, 최근에 올린 더 정확한 위치가 있으면 올리지 않는다.
  static const _goodAccuracyM = 100.0;

  /// 움직이지 않아도 이 간격마다 최신 위치/배터리를 갱신한다 (온라인 상태 유지용).
  static const _heartbeat = Duration(minutes: 5);

  final _battery = Battery();
  StreamSubscription<Position>? _positionSub;
  StreamSubscription<BatteryState>? _batterySub;
  Timer? _heartbeatTimer;
  Position? _lastHistoryPoint;
  Position? _lastUploaded;
  DateTime? _lastUpload;
  DateTime? _lastCheckin;

  /// 서버 알림 계산용 위치(checkins)는 이 간격으로만 올린다 (비용 절약)
  static const _checkinInterval = Duration(minutes: 1);

  final running = ValueNotifier<bool>(false);

  /// 공유를 켰는데 시작하지 못한 이유
  final problem = ValueNotifier<SharingProblem>(SharingProblem.none);

  /// 권한 상태. disclosure 화면에서 사용.
  static Future<LocationPermission> permission() => Geolocator.checkPermission();

  static const _tracking = MethodChannel('familylocator/tracking');

  Future<bool> start() async {
    // Android 는 서비스가 정리됐을 수 있어 매번 다시 시작을 요청한다 (이미 돌고 있으면 그대로 유지).
    if (running.value && !Platform.isAndroid) return true;
    if (!await Geolocator.isLocationServiceEnabled()) {
      problem.value = SharingProblem.serviceOff;
      return false;
    }
    final perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      problem.value = SharingProblem.permissionDenied;
      return false;
    }
    if (perm == LocationPermission.deniedForever) {
      problem.value = SharingProblem.permissionDeniedForever;
      return false;
    }
    problem.value = SharingProblem.none;

    if (Platform.isAndroid) {
      try {
        await _tracking.invokeMethod<bool>('start');
        running.value = true;
        return true;
      } catch (e) {
        debugPrint('tracking service failed: $e');
        return false;
      }
    }

    _positionSub = Geolocator.getPositionStream(locationSettings: _settings())
        .listen(_onPosition, onError: (Object e) => debugPrint('location error: $e'));

    _heartbeatTimer = Timer.periodic(_heartbeat, (_) async {
      if (_lastUpload != null && DateTime.now().difference(_lastUpload!) < _heartbeat) return;
      try {
        // 한 자리에 머무는 동안에도 이동경로에 점을 남겨 "머문 곳"을 알 수 있게 한다.
        await _onPosition(await _currentPosition(), force: true);
      } catch (e) {
        debugPrint('heartbeat failed: $e');
      }
    });

    // 배터리가 거의 다 떨어지면 꺼지기 전에 한 번 더 위치를 올린다.
    _batterySub = _battery.onBatteryStateChanged.listen((_) async {
      final level = await _battery.batteryLevel;
      if (level <= 5) {
        try {
          await _onPosition(await _currentPosition(), force: true);
        } catch (_) {}
      }
    });

    running.value = true;
    return true;
  }

  Future<void> stop() async {
    if (Platform.isAndroid) {
      try {
        await _tracking.invokeMethod<void>('stop');
      } catch (e) {
        debugPrint('tracking service stop failed: $e');
      }
    }
    await _positionSub?.cancel();
    await _batterySub?.cancel();
    _heartbeatTimer?.cancel();
    _positionSub = null;
    _batterySub = null;
    _heartbeatTimer = null;
    running.value = false;
    problem.value = SharingProblem.none;
  }

  /// 한 번 정확하게 측정한다 (GPS 를 켜서 최대 20초까지 기다림).
  static Future<Position> _currentPosition() => Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 20),
        ),
      );

  static const _power = MethodChannel('familylocator/power');

  /// 이 앱이 배터리 최적화(절전) 대상인지 (Android). 그렇다면 화면이 꺼진 뒤
  /// 폰이 앱을 멈춰 위치 공유가 끊길 수 있다.
  static Future<bool> isBatteryOptimized() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _power.invokeMethod<bool>('isBatteryOptimized') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Android 12+/iOS 14+ 에서 사용자가 "대략적인 위치"만 허용했는지.
  /// 이 경우 오차가 1~3km 까지 커진다.
  static Future<bool> isApproximateOnly() async {
    try {
      return await Geolocator.getLocationAccuracy() == LocationAccuracyStatus.reduced;
    } catch (_) {
      return false;
    }
  }

  LocationSettings _settings() {
    if (Platform.isIOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 10,
        activityType: ActivityType.other,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
      );
    }
    return const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 10);
  }

  Future<void> _onPosition(Position p, {bool force = false}) async {
    if (Backend.auth.currentUser == null) return;
    // 방금 올린 정확한 위치를 오차 큰 위치(실내 와이파이·기지국 추정 등)로 덮어쓰지 않는다.
    final prev = _lastUploaded;
    if (!force &&
        prev != null &&
        p.accuracy > _goodAccuracyM &&
        p.accuracy > prev.accuracy * 2 &&
        DateTime.now().difference(_lastUpload ?? DateTime(0)) < const Duration(minutes: 2)) {
      return;
    }
    final uid = Backend.uid;
    int? level;
    var charging = false;
    try {
      level = await _battery.batteryLevel;
      final state = await _battery.batteryState;
      charging = state == BatteryState.charging || state == BatteryState.full;
    } catch (_) {}

    _lastUpload = DateTime.now();
    _lastUploaded = p;
    // 서버 응답을 기다리지 않는다: 신호가 약해도 기기에 쌓였다가 연결되면 올라간다.
    unawaited(Backend.userDoc(uid).set({
      'lastLocation': {'lat': p.latitude, 'lng': p.longitude, 'accuracy': p.accuracy},
      'updatedAt': FieldValue.serverTimestamp(),
      'battery': ?level,
      'charging': charging,
    }, SetOptions(merge: true)).then((_) {}, onError: (Object e) => debugPrint('위치 저장 실패: $e')));

    // 서버는 checkins/{uid} 가 바뀔 때만 장소 도착·거리·함께한 시간을 계산한다
    final now = DateTime.now();
    if (force || _lastCheckin == null || now.difference(_lastCheckin!) >= _checkinInterval) {
      _lastCheckin = now;
      unawaited(Backend.db.collection('checkins').doc(uid).set({
        'lat': p.latitude,
        'lng': p.longitude,
        'accuracy': p.accuracy,
        'at': FieldValue.serverTimestamp(),
      }).then((_) {}, onError: (Object e) => debugPrint('checkin 저장 실패: $e')));
    }

    final last = _lastHistoryPoint;
    // 두 위치의 오차를 합친 것보다 덜 움직였으면 GPS 흔들림일 수 있어 이동으로 보지 않는다
    final moved = last == null ||
        Geolocator.distanceBetween(last.latitude, last.longitude, p.latitude, p.longitude) >=
            math.max(_historyMinDistanceM, last.accuracy + p.accuracy);
    if ((moved || force) && p.accuracy <= _historyMaxAccuracyM) {
      _lastHistoryPoint = p;
      unawaited(Backend.userDoc(uid).collection('locations').add({
        'lat': p.latitude,
        'lng': p.longitude,
        'accuracy': p.accuracy,
        'ts': Timestamp.fromDate(p.timestamp),
      }).then((_) {}, onError: (Object e) => debugPrint('이동경로 저장 실패: $e')));
    }
  }
}
