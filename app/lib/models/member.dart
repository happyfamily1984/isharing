import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';

/// 이 시간 이상 위치 갱신이 없으면 오프라인(전원 꺼짐/네트워크 끊김 등)으로 본다.
/// 앱은 멈춰 있어도 5분마다 위치를 올리므로, 두 번 연속 소식이 없으면 오프라인이다.
const offlineThreshold = Duration(minutes: 11);

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

  /// 온라인 / 오프라인 / 공유 중지
  String get onlineLabel {
    if (!sharing) return '공유 중지';
    return isOnline ? '온라인' : '오프라인';
  }

  /// 위치가 언제 것인지: 지금 / 3분 전 / 2시간 전 / 어제 18:20 / 10/14 09:30
  String get updatedLabel {
    final t = updatedAt;
    if (t == null) return '위치 없음';
    return formatAgo(t);
  }

  /// 목록에 보여줄 한 줄 상태
  String get statusText {
    if (!sharing) return '위치 공유를 잠시 멈췄어요';
    if (position == null || updatedAt == null) {
      return '위치 공유가 아직 시작되지 않았어요 (그 폰에서 위치 권한·GPS 확인)';
    }
    final acc = accuracy == null ? '' : ' · 오차 ${accuracy!.round()}m';
    if (isOnline) return '위치 $updatedLabel$acc';
    final lowBattery = battery != null && battery! <= 5 && !charging;
    final reason = lowBattery ? '배터리 방전 추정' : '전원 꺼짐 또는 연결 끊김';
    return '$reason · 마지막 위치 $updatedLabel';
  }
}

/// 지난 시각을 "지금 / N분 전 / N시간 전 / 어제 HH:mm / M/d HH:mm" 로 보여준다.
String formatAgo(DateTime t, {DateTime? now}) {
  now ??= DateTime.now();
  final d = now.difference(t);
  if (d.inSeconds < 90) return '지금';
  if (d.inMinutes < 60) return '${d.inMinutes}분 전';
  if (d.inHours < 6) return '${d.inHours}시간 전';
  String hm(DateTime x) =>
      '${x.hour.toString().padLeft(2, '0')}:${x.minute.toString().padLeft(2, '0')}';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final days = today.difference(day).inDays;
  if (days == 0) return '오늘 ${hm(t)}';
  if (days == 1) return '어제 ${hm(t)}';
  return '${t.month}/${t.day} ${hm(t)}';
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

/// 그룹에 등록한 장소 (집, 회사, 학교 등). 도착하면 다른 가족에게 알림이 간다.
class Place {
  Place({
    required this.id,
    required this.groupId,
    required this.name,
    required this.emoji,
    required this.position,
    required this.radius,
  });

  final String id;
  final String groupId;
  final String name;
  final String emoji;
  final LatLng position;

  /// 도착으로 볼 반경(m)
  final double radius;

  factory Place.fromDoc(String groupId, DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Place(
      id: doc.id,
      groupId: groupId,
      name: (d['name'] as String?) ?? '',
      emoji: (d['emoji'] as String?) ?? '📍',
      position: LatLng((d['lat'] as num).toDouble(), (d['lng'] as num).toDouble()),
      radius: ((d['radius'] as num?) ?? 150).toDouble(),
    );
  }
}
