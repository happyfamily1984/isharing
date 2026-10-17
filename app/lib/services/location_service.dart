import 'dart:async';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'backend.dart';

/// 내 위치를 수집해 서버에 올린다.
///
/// - users/{uid}.lastLocation : 최신 위치 (전원이 꺼져도 마지막 위치가 남는다)
/// - users/{uid}/locations    : 시간대별 이동경로
///
/// Android 에서는 상시 알림이 있는 포그라운드 서비스로 동작해 앱을 닫아도 계속 수집한다.
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

  final running = ValueNotifier<bool>(false);

  /// 권한 상태. disclosure 화면에서 사용.
  static Future<LocationPermission> permission() => Geolocator.checkPermission();

  Future<bool> start() async {
    if (running.value) return true;
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    final perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      return false;
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
    await _positionSub?.cancel();
    await _batterySub?.cancel();
    _heartbeatTimer?.cancel();
    _positionSub = null;
    _batterySub = null;
    _heartbeatTimer = null;
    running.value = false;
  }

  /// 한 번 정확하게 측정한다 (GPS 를 켜서 최대 20초까지 기다림).
  static Future<Position> _currentPosition() => Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 20),
        ),
      );

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
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 10,
        intervalDuration: const Duration(seconds: 15),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: '패밀리 위치 공유 중',
          notificationText: '그룹 멤버에게 내 위치를 공유하고 있어요. 앱에서 언제든 중지할 수 있어요.',
          notificationChannelName: '위치 공유',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }
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

    final last = _lastHistoryPoint;
    final moved = last == null ||
        Geolocator.distanceBetween(last.latitude, last.longitude, p.latitude, p.longitude) >=
            _historyMinDistanceM;
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
