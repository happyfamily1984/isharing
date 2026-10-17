import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../models/member.dart';
import '../services/place_service.dart';
import '../services/together_service.dart';
import '../widgets/family_map.dart';

/// 가족 한 명과 하루 중 언제, 어디서 함께 있었는지.
class TogetherScreen extends StatefulWidget {
  const TogetherScreen({super.key, required this.member, required this.places});

  final Member member;
  final PlacesController places;

  @override
  State<TogetherScreen> createState() => _TogetherScreenState();
}

class _TogetherScreenState extends State<TogetherScreen> {
  final _map = FamilyMapController();
  late final _stream = TogetherService.mine();
  late DateTime _day = _today();
  String? _fittedFor;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  String _dayLabel(DateTime d) {
    final diff = _today().difference(d).inDays;
    if (diff == 0) return '오늘';
    if (diff == 1) return '어제';
    return DateFormat('M/d (E)', 'ko').format(d);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final time = DateFormat('HH:mm');
    final days = [for (var i = 0; i < 7; i++) _today().subtract(Duration(days: i))];

    return Scaffold(
      appBar: AppBar(title: Text('${widget.member.displayName}님과 함께한 시간')),
      body: StreamBuilder<Map<String, TogetherRecord>>(
        stream: _stream,
        builder: (context, snap) {
          final record = snap.data?[widget.member.uid];
          final sessions = record?.sessionsOn(_day) ?? const <TogetherSession>[];
          final total = record?.on(_day) ?? Duration.zero;
          final week = record?.lastDays(7) ?? Duration.zero;

          // 날짜가 바뀌거나 기록이 처음 들어오면 그 날 만난 곳들이 다 보이게 맞춘다
          final fitKey = '${_day.toIso8601String()}-${sessions.length}';
          if (_fittedFor != fitKey && sessions.isNotEmpty) {
            _fittedFor = fitKey;
            WidgetsBinding.instance.addPostFrameCallback(
                (_) => _map.fit(sessions.map((s) => s.position).toList()));
          }

          return ListenableBuilder(
            listenable: widget.places,
            builder: (context, _) {
              final places = widget.places.all;
              return Column(
                children: [
                  SizedBox(
                    height: 52,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      children: [
                        for (final d in days)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text(_dayLabel(d)),
                              selected: d == _day,
                              showCheckmark: false,
                              onSelected: (_) => setState(() => _day = d),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Row(
                      children: [
                        Text(widget.member.badge, style: const TextStyle(fontSize: 32)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${_dayLabel(_day)} 함께한 시간', style: theme.textTheme.bodySmall),
                              Text(formatDuration(total), style: theme.textTheme.headlineSmall),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('최근 7일', style: theme.textTheme.bodySmall),
                            Text(formatDuration(week), style: theme.textTheme.titleMedium),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: FamilyMap(
                      controller: _map,
                      initialCenter: widget.member.position ?? const LatLng(37.5665, 126.9780),
                      initialZoom: 13,
                      onReady: () => _map.fit(sessions.map((s) => s.position).toList()),
                      pins: [
                        for (final (i, s) in sessions.indexed)
                          MapPin(
                            id: 'together$i',
                            position: s.position,
                            label: '${time.format(s.start)}~${time.format(s.end)}',
                            emoji: TogetherService.placeAt(s.position, places)?.emoji ?? '🤝',
                            color: theme.colorScheme.primary,
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: sessions.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                snap.connectionState == ConnectionState.waiting
                                    ? '불러오는 중…'
                                    : '${_dayLabel(_day)}은(는) 함께 있었던 기록이 없어요.\n'
                                        '두 사람이 100m 안에 있으면 함께한 시간으로 기록돼요.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : ListView(
                            children: [
                              for (final s in sessions)
                                Builder(builder: (context) {
                                  final place = TogetherService.placeAt(s.position, places);
                                  return ListTile(
                                    leading: CircleAvatar(
                                      child: Text(place?.emoji ?? '🤝',
                                          style: const TextStyle(fontSize: 20)),
                                    ),
                                    title: Text(place?.name ?? '함께 있던 곳'),
                                    subtitle: Text(
                                        '${time.format(s.start)} ~ ${time.format(s.end)} · ${formatDuration(s.duration)}'),
                                    onTap: () => _map.moveTo(s.position, zoom: 16),
                                  );
                                }),
                            ],
                          ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
