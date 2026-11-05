import 'package:flutter_test/flutter_test.dart';
import 'package:isharing/models/member.dart';
import 'package:isharing/services/trips.dart';
import 'package:latlong2/latlong.dart';

// 위도 0.001도 ≈ 111m
LocationPoint pt(double latOffset, int minute) =>
    LocationPoint(LatLng(37.5 + latOffset, 127.0), DateTime(2026, 10, 17, 8).add(Duration(minutes: minute)), 10);

void main() {
  test('home -> move -> office becomes stay, move, stay', () {
    final points = [
      pt(0, 0), // 집 도착(기록 시작)
      pt(0.0005, 5), // 집 근처 (55m)
      // 60분 동안 기록 없음 = 집에 머묾
      pt(0.005, 65), // 출발 (555m)
      pt(0.010, 66),
      pt(0.015, 67),
      pt(0.020, 68),
      pt(0.025, 69),
      pt(0.030, 70), // 회사 도착 (3.3km)
      pt(0.0305, 75), // 회사에서 5분마다 기록
      pt(0.0302, 80),
      // 3시간 머묾
      pt(0.040, 250), // 다시 이동
      pt(0.050, 251),
      pt(0.060, 252),
    ];
    final segs = buildSegments(points);
    expect(segs.map((s) => s.isStay).toList(), [true, false, true, false]);
    expect(segs[0].start, points[0].time);
    expect(segs[0].end, points[2].time); // 떠난 첫 점까지 머묾
    expect(segs[1].distanceMeters, greaterThan(2500));
    expect(segs[2].start, points[7].time);
    expect(segs[2].end, points[10].time);
  });

  test('GPS jitter around one place is a single stay, not moves', () {
    final points = [pt(0, 0), pt(0.001, 5), pt(0, 10), pt(0.001, 15), pt(0, 20)];
    final segs = buildSegments(points);
    expect(segs.length, 1);
    expect(segs.single.isStay, isTrue);
  });

  test('empty input', () => expect(buildSegments(const []), isEmpty));

  test('a day at home is drawn as one point, not a zigzag', () {
    // 집에서 GPS 가 30~80m 씩 흔들리며 5분마다 기록됨
    final points = [
      for (var i = 0; i < 60; i++) pt(i.isEven ? 0.0004 : -0.0004, i * 5),
    ];
    final segs = buildSegments(points);
    expect(segs.length, 1);
    final line = routeLine(segs, points);
    expect(line.length, 1);
    expect(line.first.latitude, closeTo(37.5, 0.0001));
  });

  test('route line joins stays and moves without jitter spurs', () {
    final points = [
      pt(0, 0),
      pt(0.0006, 30), // 집에서 흔들림
      pt(0.0002, 60),
      pt(0.010, 61), // 이동
      pt(0.020, 62),
      pt(0.030, 63), // 도착
      pt(0.0303, 100),
    ];
    final segs = buildSegments(points);
    expect(segs.map((s) => s.isStay).toList(), [true, false, true]);
    final line = routeLine(segs, points);
    expect(line.first, segs.first.center);
    expect(line.last, segs.last.center);
    // 집에서 흔들린 점(0.0006)은 선에 들어가지 않는다
    expect(line.any((p) => (p.latitude - 37.5006).abs() < 1e-9), isFalse);
  });

  test('day distance counts only moves, not jitter at home', () {
    final points = [
      pt(0, 0),
      pt(0.0006, 30), // 집에서 흔들림 (67m)
      pt(0.0002, 60),
      pt(0.010, 61), // 이동 시작
      pt(0.020, 62),
      pt(0.030, 63), // 도착 (집에서 약 3.3km)
      pt(0.0303, 100),
    ];
    final km = dayDistanceMeters(buildSegments(points)) / 1000;
    expect(km, closeTo(3.3, 0.2));
    expect(dayDistanceMeters(const []), 0);
  });
}
