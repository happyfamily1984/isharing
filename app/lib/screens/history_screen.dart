import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/member.dart';
import '../services/backend.dart';
import '../services/group_service.dart';
import '../services/trips.dart';
import '../widgets/family_map.dart';

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
    final scheme = Theme.of(context).colorScheme;
    final time = DateFormat('HH:mm');
    final days = [for (var i = 0; i < _days; i++) _today().subtract(Duration(days: i))];

    return Scaffold(
      appBar: AppBar(
        title: const Text('이동경로'),
        actions: [
          IconButton(
            tooltip: '날짜 선택',
            icon: const Icon(Icons.calendar_month),
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
                height: 52,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  children: [
                    for (final m in all)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          avatar: CircleAvatar(
                            child: Text(m.badge),
                          ),
                          label: Text(m.uid == Backend.uid ? '나' : m.displayName),
                          selected: m.uid == _uid,
                          onSelected: (_) => _selectMember(m.uid),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          // 날짜 선택
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final d in days)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(_dayLabel(d)),
                      selected: d == _day,
                      showCheckmark: false,
                      onSelected: (_) => _selectDay(d),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Stack(
              children: [
                FamilyMap(
                  controller: _map,
                  initialZoom: 13,
                  onReady: _fit,
                  lines: [
                    // 구간을 골랐으면 하루 전체 경로는 흐리게, 고른 구간은 진하게
                    MapLine(
                      id: 'day',
                      points: dayLine,
                      color: selected == null ? scheme.primary : scheme.outlineVariant,
                      width: selected == null ? 6 : 4,
                    ),
                    if (selected != null && !selected.isStay)
                      MapLine(id: 'selected', points: line, color: scheme.primary, width: 7),
                  ],
                  pins: [
                    if (selected == null)
                      for (final (i, seg) in _segments.where((s) => s.isStay).indexed)
                        MapPin(
                          id: 'stay$i',
                          position: seg.center,
                          label: '${time.format(seg.start)}~${time.format(seg.end)}',
                          color: scheme.secondary,
                        ),
                    if (selected != null && selected.isStay)
                      MapPin(
                        id: 'stay',
                        position: selected.center,
                        label: '${time.format(selected.start)}~${time.format(selected.end)} 머묾',
                        color: scheme.secondary,
                      )
                    else ...[
                      if (line.isNotEmpty && !startsAtStay)
                        MapPin(
                          id: 'start',
                          position: line.first,
                          label: '출발 ${time.format(visible.first.time)}',
                          color: scheme.tertiary,
                        ),
                      if (line.length > 1 && !endsAtStay)
                        MapPin(
                          id: 'end',
                          position: line.last,
                          label: '${selected == null ? '마지막' : '도착'} ${time.format(visible.last.time)}',
                          color: scheme.error,
                        ),
                    ],
                  ],
                ),
                if (_loading) const LinearProgressIndicator(),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: _error != null
                ? Center(child: Text(_error!))
                : _points.isEmpty
                    ? Center(child: Text(_loading ? '불러오는 중…' : '이 날은 기록된 이동경로가 없어요'))
                    : ListView(
                        padding: const EdgeInsets.only(bottom: 16),
                        children: [
                          ListTile(
                            selected: selected == null,
                            leading: const Icon(Icons.route),
                            title: Text('하루 전체 · ${_km(dayDistanceMeters(_segments))} 이동'),
                            subtitle: Text(
                                '${time.format(_points.first.time)} ~ ${time.format(_points.last.time)}'
                                ' · 이동 ${_segments.where((s) => !s.isStay).length}번'),
                            onTap: () => _select(null),
                          ),
                          const Divider(height: 1),
                          for (final seg in _segments)
                            ListTile(
                              selected: identical(seg, selected),
                              leading: Icon(seg.isStay ? Icons.place : Icons.directions_walk),
                              title: Text('${time.format(seg.start)} ~ ${time.format(seg.end)}'),
                              subtitle: Text(seg.isStay
                                  ? '머묾 · ${_duration(seg.duration)}'
                                  : '이동 · ${_km(seg.distanceMeters)} · ${_duration(seg.duration)}'),
                              onTap: () => _select(seg),
                            ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}
