import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../models/member.dart';
import '../widgets/map_tiles.dart';
import '../services/group_service.dart';

/// 날짜·시간대별 이동경로.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    required this.uid,
    required this.name,
    required this.historyDays,
  });

  final String uid;
  final String name;

  /// 요금제에 따라 조회 가능한 기간(일)
  final int historyDays;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _map = MapController();
  late DateTime _day = _today();
  RangeValues _hours = const RangeValues(0, 24);
  List<LocationPoint> _points = const [];
  bool _loading = true;
  String? _error;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final points =
          await HistoryService.load(widget.uid, _day, _day.add(const Duration(days: 1)));
      if (!mounted) return;
      setState(() => _points = points);
      _fit();
    } catch (e) {
      if (mounted) setState(() => _error = '이동경로를 불러오지 못했습니다.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
      firstDate: _today().subtract(Duration(days: widget.historyDays - 1)),
      lastDate: _today(),
      helpText: '최근 ${widget.historyDays}일까지 조회할 수 있어요',
    );
    if (picked != null) {
      _day = picked;
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final line = visible.map((p) => p.position).toList();
    final scheme = Theme.of(context).colorScheme;
    final time = DateFormat('HH:mm');

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.name}님의 이동경로'),
        actions: [
          TextButton.icon(
            onPressed: _pickDay,
            icon: const Icon(Icons.calendar_today),
            label: Text(DateFormat('M월 d일 (E)', 'ko').format(_day)),
          ),
        ],
      ),
      body: Column(
        children: [
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
                    ? const Center(child: Text('이 시간대에는 기록된 이동경로가 없어요'))
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
