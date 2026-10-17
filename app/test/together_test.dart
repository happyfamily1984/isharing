import 'package:flutter_test/flutter_test.dart';
import 'package:isharing/models/member.dart';
import 'package:isharing/services/together_service.dart';
import 'package:latlong2/latlong.dart';

void main() {
  final record = TogetherRecord(
    otherUid: 'mom',
    daySeconds: {'2026-10-17': 9000, '2026-10-16': 3600, '2026-10-01': 99999},
    sessions: [
      TogetherSession(DateTime(2026, 10, 16, 20), DateTime(2026, 10, 16, 21), const LatLng(37.43, 127.0)),
      TogetherSession(DateTime(2026, 10, 17, 7), DateTime(2026, 10, 17, 8), const LatLng(37.43, 127.0)),
      TogetherSession(DateTime(2026, 10, 17, 12), DateTime(2026, 10, 17, 13, 30), const LatLng(37.44, 127.01)),
    ],
  );

  test('daily and 7-day totals', () {
    final now = DateTime(2026, 10, 17, 22);
    expect(record.on(now), const Duration(hours: 2, minutes: 30));
    expect(record.lastDays(7, now: now), const Duration(hours: 3, minutes: 30));
    expect(formatDuration(record.on(now)), '2시간 30분');
    expect(formatDuration(const Duration(minutes: 45)), '45분');
  });

  test('sessions of a day and matching registered places', () {
    final today = record.sessionsOn(DateTime(2026, 10, 17));
    expect(today.length, 2);
    final home = Place(
      id: 'h', groupId: 'g', name: '집', emoji: '🏠', position: const LatLng(37.4301, 127.0), radius: 100);
    expect(TogetherService.placeAt(today.first.position, [home])?.name, '집');
    expect(TogetherService.placeAt(today.last.position, [home]), isNull);
  });
}
