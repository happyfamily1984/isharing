import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';

/// 이 시간 이상 위치 갱신이 없으면 오프라인(전원 꺼짐/네트워크 끊김 등)으로 보고 마지막 위치를 표시한다.
const offlineThreshold = Duration(minutes: 20);

class Member {
  Member({
    required this.uid,
    required this.displayName,
    this.avatar,
    required this.sharing,
    this.position,
    this.accuracy,
    this.updatedAt,
    this.battery,
    this.charging = false,
  });

  final String uid;
  final String displayName;

  /// 프로필에서 고른 이모지. 없으면 이름 첫 글자를 쓴다.
  final String? avatar;
  final bool sharing;
  final LatLng? position;
  final double? accuracy;
  final DateTime? updatedAt;
  final int? battery;
  final bool charging;

  factory Member.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    final loc = d['lastLocation'] as Map<String, dynamic>?;
    return Member(
      uid: doc.id,
      displayName: (d['displayName'] as String?) ?? '이름 없음',
      avatar: d['avatar'] as String?,
      sharing: (d['sharing'] as bool?) ?? true,
      position: loc == null
          ? null
          : LatLng((loc['lat'] as num).toDouble(), (loc['lng'] as num).toDouble()),
      accuracy: (loc?['accuracy'] as num?)?.toDouble(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
      battery: (d['battery'] as num?)?.toInt(),
      charging: (d['charging'] as bool?) ?? false,
    );
  }

  /// 화면에 표시할 아이콘 (이모지 또는 이름 첫 글자)
  String get badge =>
      avatar ?? (displayName.isEmpty ? '?' : displayName.characters.first);

  bool get isOnline =>
      updatedAt != null && DateTime.now().difference(updatedAt!) < offlineThreshold;

  String get statusText {
    if (!sharing) return '위치 공유 일시중지';
    if (position == null || updatedAt == null) return '위치 정보 없음';
    final ago = _formatAgo(DateTime.now().difference(updatedAt!));
    if (isOnline) return '실시간 · $ago';
    final lowBattery = battery != null && battery! <= 5;
    return lowBattery
        ? '배터리 방전 추정 · 마지막 위치 $ago'
        : '전원 꺼짐/연결 끊김 · 마지막 위치 $ago';
  }

  static String _formatAgo(Duration d) {
    if (d.inMinutes < 1) return '방금 전';
    if (d.inHours < 1) return '${d.inMinutes}분 전';
    if (d.inDays < 1) return '${d.inHours}시간 전';
    return '${d.inDays}일 전';
  }
}

class LocationPoint {
  LocationPoint(this.position, this.time, this.accuracy);

  final LatLng position;
  final DateTime time;
  final double? accuracy;

  factory LocationPoint.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return LocationPoint(
      LatLng((d['lat'] as num).toDouble(), (d['lng'] as num).toDouble()),
      (d['ts'] as Timestamp).toDate(),
      (d['accuracy'] as num?)?.toDouble(),
    );
  }
}

class Group {
  Group({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.members,
    required this.planName,
    this.inviteCode,
    this.inviteExpiresAt,
  });

  final String id;
  final String name;
  final String ownerId;
  final List<String> members;
  final String planName;
  final String? inviteCode;
  final DateTime? inviteExpiresAt;

  factory Group.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Group(
      id: doc.id,
      name: (d['name'] as String?) ?? '',
      ownerId: (d['ownerId'] as String?) ?? '',
      members: List<String>.from(d['members'] as List? ?? const []),
      planName: (d['plan'] as String?) ?? 'free',
      inviteCode: d['inviteCode'] as String?,
      inviteExpiresAt: (d['inviteExpiresAt'] as Timestamp?)?.toDate(),
    );
  }

  bool get inviteValid =>
      inviteCode != null && inviteExpiresAt != null && inviteExpiresAt!.isAfter(DateTime.now());
}
