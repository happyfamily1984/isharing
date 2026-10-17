import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../models/member.dart';
import '../services/backend.dart';
import '../services/group_service.dart';
import '../widgets/map_tiles.dart';

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
  final _map = MapController();
  late String _uid = widget.initialUid;
  late DateTime _day = _today();
  RangeValues _hours = const RangeValues(0, 24);
  List<LocationPoint> _points = const [];
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
      setState(() => _points = points);
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

  List<LocationPoint> get _visible => _points.where((p) {
        final h = p.time.hour + p.time.minute / 60;
        return h >= _hours.start && h <= _hours.end;
      }).toList();

  void _fit() {
    final pts = _visible.map((p) => p.position).toList();
    if (pts.isEmpty) return;
    if (pts.length == 1) {
      _map.move(pts.first, 16);
      return;
    }
    _map.fitCamera(CameraFit.coordinates(coordinates: pts, padding: const EdgeInsets.all(48)));
  }

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
    final line = visible.map((p) => p.position).toList();
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
                            child: Text(m.displayName.isEmpty ? '?' : m.displayName.characters.first),
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
                FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: line.isNotEmpty ? line.first : const LatLng(37.5665, 126.9780),
                    initialZoom: 13,
                  ),
                  children: [
                    const AppTileLayer(),
                    PolylineLayer(polylines: [
                      if (line.length > 1)
                        Polyline(points: line, strokeWidth: 5, color: scheme.primary),
                    ]),
                    MarkerLayer(markers: [
                      if (line.isNotEmpty)
                        Marker(
                          point: line.first,
                          child: Icon(Icons.trip_origin, color: scheme.tertiary),
                        ),
                      if (line.length > 1)
                        Marker(
                          point: line.last,
                          width: 40,
                          height: 40,
                          alignment: Alignment.topCenter,
                          child: Icon(Icons.location_on, size: 40, color: scheme.error),
                        ),
                    ]),
                    const AppMapAttribution(),
                  ],
                ),
                if (_loading) const LinearProgressIndicator(),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Text('${_hours.start.round()}시'),
                Expanded(
                  child: RangeSlider(
                    values: _hours,
                    min: 0,
                    max: 24,
                    divisions: 24,
                    labels: RangeLabels('${_hours.start.round()}시', '${_hours.end.round()}시'),
                    onChanged: (v) => setState(() => _hours = v),
                    onChangeEnd: (_) => _fit(),
                  ),
                ),
                Text('${_hours.end.round()}시'),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: _error != null
                ? Center(child: Text(_error!))
                : visible.isEmpty
                    ? Center(
                        child: Text(_loading ? '불러오는 중…' : '이 시간대에는 기록된 이동경로가 없어요'),
                      )
                    : ListView.builder(
                        itemCount: visible.length,
                        itemBuilder: (context, i) {
                          final p = visible[visible.length - 1 - i];
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.place_outlined),
                            title: Text(time.format(p.time)),
                            subtitle: Text(
                                '${p.position.latitude.toStringAsFixed(5)}, ${p.position.longitude.toStringAsFixed(5)}'),
                            onTap: () => _map.move(p.position, 17),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
