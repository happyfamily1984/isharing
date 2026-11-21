import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'backend.dart';

/// 알림 탭에 보여줄 기록 (장소 도착 · 거리 · 벨). 서버가 users/{uid}/alerts 에 남긴다.
class AppAlert {
  AppAlert({required this.id, required this.title, required this.body, required this.type, this.createdAt});

  final String id;
  final String title;
  final String body;

  /// place / distance / ring
  final String type;
  final DateTime? createdAt;

  factory AppAlert.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return AppAlert(
      id: doc.id,
      title: (d['title'] as String?) ?? '',
      body: (d['body'] as String?) ?? '',
      type: (d['type'] as String?) ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

class AlertService {
  AlertService._();

  /// 최근 알림 (새것부터). 읽기 비용을 줄이려고 개수를 제한한다.
  static Stream<List<AppAlert>> recent({int limit = 50}) => Backend.userDoc(Backend.uid)
      .collection('alerts')
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((q) => q.docs.map(AppAlert.fromDoc).toList());

  /// 알림 목록을 봤다고 기록한다 (안 읽은 알림 수 표시를 지운다).
  static void markSeen() {
    unawaited(Backend.userDoc(Backend.uid)
        .set({'alertsSeenAt': FieldValue.serverTimestamp()}, SetOptions(merge: true))
        .then((_) {}, onError: (Object _) {}));
  }
}
