/// 요금제별 제한. functions/src/index.ts 의 PLAN_LIMITS 와 값을 맞춘다.
enum Plan {
  free(maxMembers: 6, historyDays: 2),
  premium(maxMembers: 20, historyDays: 30);

  const Plan({required this.maxMembers, required this.historyDays});

  final int maxMembers;
  final int historyDays;

  static Plan parse(Object? value) => value == 'premium' ? Plan.premium : Plan.free;
}
