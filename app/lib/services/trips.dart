import 'package:latlong2/latlong.dart';

import '../models/member.dart';

/// 하루 이동기록을 "머문 곳"과 "이동" 구간으로 묶은 것.
class RouteSegment {
  RouteSegment.stay(this.points, this.start, this.end) : isStay = true;
  RouteSegment.move(this.points, this.start, this.end) : isStay = false;

  final bool isStay;
  final List<LocationPoint> points;
  final DateTime start;
  final DateTime end;

  Duration get duration => end.difference(start);

  LatLng get center => points.first.position;

  double get distanceMeters {
    const d = Distance();
    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      total += d(points[i - 1].position, points[i].position);
    }
    return total;
  }
}

/// 이 반경 안에 있으면 같은 장소에 머문 것으로 본다.
const _stayRadiusMeters = 150.0;

/// 이 시간 이상 같은 장소에서 기록이 이어지면 "머문 곳"으로 본다.
const _minStay = Duration(minutes: 10);

/// 점 하나 뒤에 이만큼 기록이 끊기면 그 자리에 머문 것으로 본다.
/// (이동 중에는 30초~1분마다 기록되므로 이 정도 공백은 정지 상태)
const _minStayGap = Duration(minutes: 20);

/// 이보다 짧은 이동은 GPS 오차로 보고 목록에서 뺀다.
const _minMoveMeters = 300.0;

/// 시간순 위치 기록을 머문 곳/이동 구간으로 나눈다.
///
/// 앱은 50m 이상 움직일 때만 기록을 남기므로 한 장소에 머무는 동안에는 점이 거의 없다.
/// 그래서 머문 시간은 "그 장소에 도착한 점 ~ 다음 장소로 떠난 첫 점" 사이로 계산한다.
List<RouteSegment> buildSegments(List<LocationPoint> points) {
  if (points.isEmpty) return const [];
  const distance = Distance();

  // 1) 가까운 점끼리 묶어 장소 후보(cluster)를 만든다.
  final clusters = <List<LocationPoint>>[];
  for (final p in points) {
    if (clusters.isNotEmpty &&
        distance(clusters.last.first.position, p.position) <= _stayRadiusMeters) {
      clusters.last.add(p);
    } else {
      clusters.add([p]);
    }
  }

  // 2) 오래 머문 장소만 "머문 곳"으로 남기고 나머지 점은 이동으로 이어 붙인다.
  final segments = <RouteSegment>[];
  var moving = <LocationPoint>[];

  void flushMove() {
    if (moving.length >= 2) {
      final seg = RouteSegment.move(moving, moving.first.time, moving.last.time);
      if (seg.distanceMeters >= _minMoveMeters) segments.add(seg);
    }
  }

  for (var i = 0; i < clusters.length; i++) {
    final c = clusters[i];
    final leftAt = i + 1 < clusters.length ? clusters[i + 1].first.time : c.last.time;
    final isStay = c.last.time.difference(c.first.time) >= _minStay ||
        leftAt.difference(c.last.time) >= _minStayGap;
    if (isStay) {
      moving.add(c.first); // 이동의 끝 = 도착 지점
      flushMove();
      segments.add(RouteSegment.stay(c, c.first.time, leftAt));
      moving = [c.last]; // 다음 이동의 시작 = 출발 지점
    } else {
      moving.addAll(c);
    }
  }
  flushMove();
  return segments;
}
