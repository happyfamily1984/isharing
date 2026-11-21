import 'package:latlong2/latlong.dart';

import '../models/member.dart';

/// 홈 화면 위쪽 상태 카드에 보여줄 문구.
class FamilyStatus {
  const FamilyStatus({required this.headline, required this.subtitle, required this.latest, required this.anyOnline});

  final String headline;
  final String subtitle;

  /// 가장 최근에 위치가 올라온 시각
  final DateTime latest;
  final bool anyOnline;

  /// 이 거리 안에 모두 모여 있으면 "함께 있어요"
  static const togetherRadiusM = 150.0;

  /// 위치가 있는 가족이 없으면 null.
  static FamilyStatus? of(List<Member> members, {DateTime? now}) {
    now ??= DateTime.now();
    final located = members.where((m) => m.sharing && m.position != null && m.updatedAt != null).toList();
    if (located.isEmpty) return null;
    final online = located.where((m) => now!.difference(m.updatedAt!) < offlineThreshold).toList();
    final latest = located.map((m) => m.updatedAt!).reduce((a, b) => a.isAfter(b) ? a : b);

    String headline;
    if (located.length >= 2 && online.length == located.length && _together(located)) {
      headline = '우리 가족이 모두 함께 있어요!';
    } else if (located.length >= 2 && online.length == located.length) {
      headline = '가족 모두 위치를 공유하고 있어요';
    } else if (located.length >= 2) {
      headline = '가족 ${located.length}명 중 ${online.length}명이 온라인이에요';
    } else {
      headline = online.isEmpty ? '위치가 오프라인이에요' : '내 위치를 공유하고 있어요';
    }
    final fresh = now.difference(latest) < const Duration(minutes: 2);
    final subtitle = fresh ? '실시간 위치가 업데이트 되었어요.' : '마지막 업데이트 ${formatAgo(latest, now: now)}';
    return FamilyStatus(headline: headline, subtitle: subtitle, latest: latest, anyOnline: online.isNotEmpty);
  }

  static bool _together(List<Member> located) {
    var lat = 0.0, lng = 0.0;
    for (final m in located) {
      lat += m.position!.latitude;
      lng += m.position!.longitude;
    }
    final center = LatLng(lat / located.length, lng / located.length);
    const distance = Distance();
    return located.every((m) => distance(center, m.position!) <= togetherRadiusM);
  }
}

/// 등록된 장소 근처면 "집에 있어요" / "학교 근처" 를 돌려준다.
String? nearPlaceLabel(LatLng? position, List<Place> places) {
  if (position == null || places.isEmpty) return null;
  const distance = Distance();
  Place? best;
  var bestD = double.infinity;
  for (final p in places) {
    final d = distance(position, p.position);
    if (d < bestD) {
      bestD = d;
      best = p;
    }
  }
  if (best == null) return null;
  if (bestD <= best.radius) return '${best.name}에 있어요';
  if (bestD <= best.radius + 300) return '${best.name} 근처';
  return null;
}
