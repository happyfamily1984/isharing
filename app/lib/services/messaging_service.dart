import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';

import 'backend.dart';

/// 푸시 토큰 등록과 '벨 울리기' 처리.
///
/// Android 에서는 네이티브 RingReceiver/RingService 가 앱 상태와 무관하게 벨을 울린다.
/// iOS 에서는 APNs Critical Alert 로 울린다 (Apple 승인 필요, README 참고).
// FCM 등록 토큰 API는 FID 기반 register()/onRegistered 로 대체 예정(deprecated)이지만,
// 서버(firebase-admin)의 send({token}) 와 호환되는 현재 방식을 유지한다.
// ignore_for_file: deprecated_member_use

class MessagingService {
  MessagingService._();

  static const _ringChannel = MethodChannel('familylocator/ring');
  static final _incomingRings = StreamController<String>.broadcast();
  static final _incomingAlerts = StreamController<String>.broadcast();
  static StreamSubscription<String>? _tokenSub;
  static StreamSubscription<RemoteMessage>? _messageSub;

  /// 앱이 열려 있을 때 벨 요청이 오면 보낸 사람 이름을 내보낸다.
  static Stream<String> get incomingRings => _incomingRings.stream;

  /// 앱이 열려 있을 때 받은 장소 도착·거리 알림 문구.
  /// (앱이 열려 있으면 시스템 알림이 뜨지 않아 화면 안에서 보여준다)
  static Stream<String> get incomingAlerts => _incomingAlerts.stream;

  static Future<void> init() async {
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, sound: true, badge: true, criticalAlert: true);

    final token = await messaging.getToken();
    if (token != null) await _saveToken(token);
    await _tokenSub?.cancel();
    _tokenSub = messaging.onTokenRefresh.listen(_saveToken);

    await _messageSub?.cancel();
    _messageSub = FirebaseMessaging.onMessage.listen((message) {
      final type = message.data['type'];
      if (type == 'ring') {
        _incomingRings.add((message.data['fromName'] as String?) ?? '');
      } else if (message.notification?.body != null) {
        _incomingAlerts.add(message.notification!.body!);
      } else if (message.data['body'] is String) {
        // 잠깐만 보이는 알림(거리 알림)은 data 로만 온다
        _incomingAlerts.add(message.data['body'] as String);
      }
    });
  }

  static Future<void> _saveToken(String token) => Backend.userDoc(Backend.uid).set({
        'fcmToken': token,
        'platform': Platform.operatingSystem,
      }, SetOptions(merge: true));

  /// 로그아웃 시 이 기기로 벨/알림이 가지 않도록 토큰을 지운다.
  static Future<void> clearToken() async {
    await _tokenSub?.cancel();
    await _messageSub?.cancel();
    if (Backend.auth.currentUser == null) return;
    await Backend.userDoc(Backend.uid).update({'fcmToken': FieldValue.delete()});
    await FirebaseMessaging.instance.deleteToken();
  }

  static Future<void> ring(String targetUid) =>
      Backend.call('ringDevice', {'targetUid': targetUid});

  /// 벨이 울릴 때 화면 전체 안내 창을 띄울 수 있는지 ("다른 앱 위에 표시" 권한)
  static Future<bool> canShowRingOverlay() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _ringChannel.invokeMethod<bool>('canShowOverlay') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// "다른 앱 위에 표시" 권한 설정 화면을 연다.
  static Future<void> openRingOverlaySettings() =>
      _ringChannel.invokeMethod<void>('openOverlaySettings');

  static Future<void> stopRinging() async {
    if (!Platform.isAndroid) return;
    await _ringChannel.invokeMethod<void>('stop');
  }
}
