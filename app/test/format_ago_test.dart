import 'package:flutter_test/flutter_test.dart';
import 'package:isharing/models/member.dart';

void main() {
  final now = DateTime(2026, 10, 17, 14, 30);
  String ago(Duration d) => formatAgo(now.subtract(d), now: now);

  test('relative labels', () {
    expect(ago(const Duration(seconds: 30)), '지금');
    expect(ago(const Duration(minutes: 3)), '3분 전');
    expect(ago(const Duration(hours: 2)), '2시간 전');
    expect(ago(const Duration(hours: 7)), '오늘 07:30');
    expect(formatAgo(DateTime(2026, 10, 16, 18, 5), now: now), '어제 18:05');
    expect(formatAgo(DateTime(2026, 10, 14, 9, 0), now: now), '10/14 09:00');
  });
}
