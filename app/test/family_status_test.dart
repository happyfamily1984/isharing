import 'package:flutter_test/flutter_test.dart';
import 'package:isharing/models/member.dart';
import 'package:isharing/services/family_status.dart';
import 'package:latlong2/latlong.dart';

Member m(String uid, double lat, {Duration ago = Duration.zero, DateTime? now}) => Member(
      uid: uid,
      displayName: uid,
      sharing: true,
      position: LatLng(lat, 127.0),
      updatedAt: (now ?? DateTime(2026, 11, 21, 15)).subtract(ago),
    );

void main() {
  final now = DateTime(2026, 11, 21, 15);

  test('everyone close together', () {
    final s = FamilyStatus.of([m('a', 37.5), m('b', 37.5005), m('c', 37.4997)], now: now)!;
    expect(s.headline, '우리 가족이 모두 함께 있어요!');
    expect(s.subtitle, '실시간 위치가 업데이트 되었어요.');
  });

  test('spread out and one offline', () {
    final s = FamilyStatus.of([m('a', 37.5), m('b', 37.6, ago: const Duration(hours: 1))], now: now)!;
    expect(s.headline, '가족 2명 중 1명이 온라인이에요');
  });

  test('no locations', () => expect(FamilyStatus.of(const [], now: now), isNull));

  test('near a registered place', () {
    final home = Place(id: 'h', groupId: 'g', name: '집', emoji: '🏠', position: const LatLng(37.5, 127.0), radius: 150);
    expect(nearPlaceLabel(const LatLng(37.5005, 127.0), [home]), '집에 있어요');
    expect(nearPlaceLabel(const LatLng(37.503, 127.0), [home]), '집 근처');
    expect(nearPlaceLabel(const LatLng(37.52, 127.0), [home]), isNull);
  });
}
