import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/member.dart';
import '../services/backend.dart';
import '../services/group_service.dart';
import '../services/trips.dart';
import '../widgets/family_map.dart';
import '../widgets/ui.dart';

/// 멤버별 · 날짜별 · 시간대별 이동경로.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    required this.members,
    required this.initialUid,
    required this.historyDaysFor,
  });

  final MembersController members;
  final String initialUid;

  /// 멤버별 조회 가능 기간(일). 함께 속한 그룹의 요금제에 따라 다르다.
  final int Function(String uid) historyDaysFor;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _map = FamilyMapController();
  late String _uid = widget.initialUid;
  late DateTime _day = _today();
  List<LocationPoint> _points = const [];
  List<RouteSegment> _segments = const [];

  /// 목록에서 고른 구간. null 이면 하루 전체.
  RouteSegment? _selected;
  bool _loading = true;
  bool _satellite = false;
  String? _error;
  int _request = 0;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  int get _days => widget.historyDaysFor(_uid);
  DateTime get _firstDay => _today().subtract(Duration(days: _days - 1));

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final points = await HistoryService.load(_uid, _day, _day.add(const Duration(days: 1)));
      // 멤버/날짜를 빠르게 바꿨을 때 이전 요청 결과가 덮어쓰지 않게 한다.
      if (!mounted || request != _request) return;
      setState(() {
        _points = points;
        _segments = buildSegments(points);
        _selected = null;
      });
      _fit();
    } catch (e) {
      if (mounted && request == _request) setState(() => _error = '이동경로를 불러오지 못했습니다.');
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  void _selectMember(String uid) {
    if (uid == _uid) return;
    _uid = uid;
    if (_day.isBefore(_firstDay)) _day = _today();
    _load();
  }

  void _selectDay(DateTime day) {
    if (day == _day) return;
    _day = day;
    _load();
  }

  List<LocationPoint> get _visible => _selected?.points ?? _points;

  void _fit() => _map.fit(_selected == null
      ? routeLine(_segments, _points)
      : _visible.map((p) => p.position).toList());

  void _select(RouteSegment? segment) {
    setState(() => _selected = segment);
    _fit();
  }

  static String _duration(Duration d) {
    if (d.inMinutes < 60) return '${d.inMinutes}분';
    final m = d.inMinutes % 60;
    return m == 0 ? '${d.inHours}시간' : '${d.inHours}시간 $m분';
  }

  static String _km(double meters) =>
      meters < 1000 ? '${meters.round()}m' : '${(meters / 1000).toStringAsFixed(1)}km';

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: _firstDay,
      lastDate: _today(),
      helpText: '최근 $_days일까지 조회할 수 있어요',
    );
    if (picked != null) _selectDay(picked);
  }

  String _dayLabel(DateTime d) {
    final diff = _today().difference(d).inDays;
    if (diff == 0) return '오늘';
    if (diff == 1) return '어제';
    return DateFormat('M/d (E)', 'ko').format(d);
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final selected = _selected;
    final dayLine = routeLine(_segments, _points);
    final line = selected == null ? dayLine : visible.map((p) => p.position).toList();
    // 하루 전체를 볼 때 처음·끝이 머문 곳이면 그 곳 표시(시간 포함)가 출발·마지막을 대신한다
    final startsAtStay = selected == null && _segments.isNotEmpty && _segments.first.isStay;
    final endsAtStay = selected == null && _segments.isNotEmpty && _segments.last.isStay;
    final time = DateFormat('HH:mm');
    final days = [for (var i = 0; i < _days; i++) _today().subtract(Duration(days: i))];

    return Scaffold(
      appBar: PillAppBar(
        title: '이동경로',
        actions: [
          IconButton(
            tooltip: '날짜 선택',
            icon: const Icon(Icons.calendar_month, size: 23),
            onPressed: _pickDay,
          ),
        ],
      ),
      body: Column(
        children: [
          // 멤버 선택
          ListenableBuilder(
            listenable: widget.members,
            builder: (context, _) {
              final me = widget.members.me;
              final all = [?me, ...widget.members.others];
              return SizedBox(
                height: 50,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  children: [
                    for (final m in all)
                      _PillChoice(
                        selected: m.uid == _uid,
                        onTap: () => _selectMember(m.uid),
                        leading: EmojiBubble(m.badge, size: 28),
                        label: m.uid == Backend.uid ? '나' : m.displayName,
                      ),
                  ],
                ),
              );
            },
          ),
          // 날짜 선택
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              children: [
                for (final d in days)
                  _PillChoice(
                    selected: d == _day,
                    onTap: () => _selectDay(d),
                    label: _dayLabel(d),
                    minWidth: 64,
                  ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                // 아래 요약 카드가 지도 아래쪽을 덮으므로 맞추기는 보이는 부분 기준으로 한다.
                final sheet = box.maxHeight * 0.36;
                _map
                  ..bottomCover = sheet - 28
                  ..viewHeight = box.maxHeight;
                return Stack(
                  children: [
                    Positioned.fill(
                      child: FamilyMap(
                        controller: _map,
                        initialZoom: 13,
                        satellite: _satellite,
                        onReady: _fit,
                        lines: [
                          // 구간을 골랐으면 하루 전체 경로는 흐리게, 고른 구간은 진하게
                          MapLine(
                            id: 'day',
                            points: dayLine,
                            color: selected == null ? AppColors.primaryDark : const Color(0xFF9FB8B3),
                            width: selected == null ? 7 : 5,
                          ),
                          if (selected != null && !selected.isStay)
                            MapLine(id: 'selected', points: line, color: AppColors.primaryDark, width: 8),
                        ],
                        pins: [
                          if (selected == null)
                            for (final (i, seg) in _segments.where((s) => s.isStay).indexed)
                              MapPin(
                                id: 'stay$i',
                                position: seg.center,
                                label: '${time.format(seg.start)}~${time.format(seg.end)}',
                                color: AppColors.primary,
                              ),
                          if (selected != null && selected.isStay)
                            MapPin(
                              id: 'stay',
                              position: selected.center,
                              label: '${time.format(selected.start)}~${time.format(selected.end)} 머묾',
                              color: AppColors.primary,
                            )
                          else ...[
                            if (line.isNotEmpty && !startsAtStay)
                              MapPin(
                                id: 'start',
                                position: line.first,
                                label: '출발 ${time.format(visible.first.time)}',
                                color: AppColors.primary,
                              ),
                            if (line.length > 1 && !endsAtStay)
                              MapPin(
                                id: 'end',
                                position: line.last,
                                label: '${selected == null ? '마지막' : '도착'} ${time.format(visible.last.time)}',
                                color: AppColors.me,
                              ),
                          ],
                        ],
                      ),
                    ),
                    if (_loading) const LinearProgressIndicator(),
                    // 지도 오른쪽 버튼: 경로 전체 보기 · 위성 지도
                    Positioned(
                      right: 12,
                      bottom: sheet + 4,
                      child: Column(
                        children: [
                          _MapRoundButton(icon: Icons.my_location, tooltip: '경로 전체 보기', onTap: _fit),
                          const SizedBox(height: 8),
                          _MapRoundButton(
                            icon: Icons.layers_outlined,
                            tooltip: _satellite ? '기본 지도' : '위성 지도',
                            onTap: () => setState(() => _satellite = !_satellite),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: sheet,
                      child: _summarySheet(selected, time),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _summarySheet(RouteSegment? selected, DateFormat time) {
    Widget body;
    if (_error != null) {
      body = Center(child: Text(_error!));
    } else if (_points.isEmpty) {
      body = Center(
        child: Text(_loading ? '불러오는 중…' : '이 날은 기록된 이동경로가 없어요',
            style: const TextStyle(color: AppColors.sub, fontSize: 16)),
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _select(null),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
              child: Row(
                children: [
                  IconBubble(Icons.route, size: 42,
                      background: selected == null ? AppColors.mint : AppColors.mintSoft),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('하루 전체 · ${_km(dayDistanceMeters(_segments))} 이동',
                            style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, color: AppColors.ink)),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.schedule, size: 13, color: AppColors.sub),
                            const SizedBox(width: 4),
                            Text(
                              '${time.format(_points.first.time)} ~ ${time.format(_points.last.time)}'
                              ' · 이동 ${_segments.where((s) => !s.isStay).length}번',
                              style: const TextStyle(fontSize: 12.5, color: AppColors.sub),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          for (final seg in _segments)
            SoftCard(
              margin: const EdgeInsets.only(bottom: 8),
              padding: EdgeInsets.zero,
              radius: 18,
              border: identical(seg, selected) ? Border.all(color: AppColors.primary, width: 2) : null,
              onTap: () => _select(seg),
              child: FeatureRow(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                leading: IconBubble(seg.isStay ? Icons.location_on : Icons.directions_walk,
                    size: 38, color: AppColors.primaryDark, background: AppColors.mint),
                title: '${time.format(seg.start)} ~ ${time.format(seg.end)}',
                subtitle: seg.isStay
                    ? '머묾 · ${_duration(seg.duration)}'
                    : '이동 · ${_km(seg.distanceMeters)} · ${_duration(seg.duration)}',
                trailing: const Icon(Icons.chevron_right, size: 22, color: AppColors.sub),
              ),
            ),
        ],
      );
    }
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [BoxShadow(color: Color(0x1A000000), blurRadius: 20, offset: Offset(0, -4))],
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 8),
            width: 40,
            height: 5,
            decoration: BoxDecoration(color: const Color(0xFFD2DBD9), borderRadius: BorderRadius.circular(3)),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

/// 사람·날짜 고르기 버튼 (둥근 알약 모양, 고르면 민트색).
class _PillChoice extends StatelessWidget {
  const _PillChoice({
    required this.selected,
    required this.onTap,
    required this.label,
    this.leading,
    this.minWidth = 0,
  });

  final bool selected;
  final VoidCallback onTap;
  final String label;
  final Widget? leading;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? AppColors.mint : Colors.white,
        shape: StadiumBorder(
          side: BorderSide(color: selected ? AppColors.primary : AppColors.line, width: selected ? 2 : 1),
        ),
        elevation: selected ? 0 : 1.5,
        shadowColor: const Color(0x33000000),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: minWidth),
            child: Padding(
              padding: EdgeInsets.fromLTRB(leading == null ? 14 : 5, 0, 14, 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (leading != null) ...[leading!, const SizedBox(width: 6)],
                  Text(label,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                          color: AppColors.ink)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 지도 위 동그란 흰 버튼.
class _MapRoundButton extends StatelessWidget {
  const _MapRoundButton({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 3,
        shadowColor: const Color(0x44000000),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 42, height: 42, child: Icon(icon, size: 21, color: AppColors.ink)),
        ),
      ),
    );
  }
}
