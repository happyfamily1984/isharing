import 'package:latlong2/latlong.dart';

import '../models/member.dart';
import 'backend.dart';

/// 함께 있었던 한 번의 시간과 장소
class TogetherSession {
  TogetherSession(this.start, this.end, this.position);

  final DateTime start;
  final DateTime end;
  final LatLng position;

  Duration get duration => end.difference(start);
}

/// 나와 가족 한 명이 함께한 기록 (서버가 together/{두 사람} 에 누적)
class TogetherRecord {
  TogetherRecord({required this.otherUid, required this.daySeconds, required this.sessions});

  final String otherUid;

  /// "2026-10-17" → 함께한 초
  final Map<String, int> daySeconds;
  final List<TogetherSession> sessions;

  static String dayKey(DateTime day) =>
      '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

  Duration on(DateTime day) => Duration(seconds: daySeconds[dayKey(day)] ?? 0);

  /// 오늘을 포함한 최근 [days]일 합계
  Duration lastDays(int days, {DateTime? now}) {
    now ??= DateTime.now();
    var total = Duration.zero;
    for (var i = 0; i < days; i++) {
      total += on(DateTime(now.year, now.month, now.day - i));
    }
    return total;
  }

  /// 그 날 시작한 기록 (시간순)
  List<TogetherSession> sessionsOn(DateTime day) => sessions
      .where((s) => s.start.year == day.year && s.start.month == day.month && s.start.day == day.day)
      .toList();
}

class TogetherService {
  TogetherService._();

  /// 나와 각 가족의 함께한 기록. 키는 상대방 uid.
  static Stream<Map<String, TogetherRecord>> mine() {
    final me = Backend.uid;
    return Backend.db
        .collection('together')
        .where('members', arrayContains: me)
        .snapshots()
        .map((snap) => {
              for (final doc in snap.docs) _parse(me, doc.data()).otherUid: _parse(me, doc.data()),
            });
  }

  static TogetherRecord _parse(String me, Map<String, dynamic> d) {
    final members = List<String>.from(d['members'] as List? ?? const []);
    final days = (d['days'] as Map?) ?? const {};
    final sessions = (d['sessions'] as List?) ?? const [];
    return TogetherRecord(
      otherUid: members.firstWhere((m) => m != me, orElse: () => ''),
      daySeconds: {for (final e in days.entries) e.key as String: (e.value as num).toInt()},
      sessions: [
        for (final s in sessions.cast<Map>())
          TogetherSession(
            DateTime.fromMillisecondsSinceEpoch((s['start'] as num).toInt()),
            DateTime.fromMillisecondsSinceEpoch((s['end'] as num).toInt()),
            LatLng((s['lat'] as num).toDouble(), (s['lng'] as num).toDouble()),
          ),
      ]..sort((a, b) => a.start.compareTo(b.start)),
    );
  }

  /// 함께 있던 곳이 등록한 장소 안이면 그 장소
  static Place? placeAt(LatLng position, List<Place> places) {
    const distance = Distance();
    Place? best;
    var bestD = double.infinity;
    for (final p in places) {
      final d = distance(position, p.position);
      if (d <= p.radius + 50 && d < bestD) {
        best = p;
        bestD = d;
      }
    }
    return best;
  }
}

/// "2시간 30분" / "45분" / "0분"
String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h == 0) return '$m분';
  return m == 0 ? '$h시간' : '$h시간 $m분';
}
