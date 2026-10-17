import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../models/member.dart';
import '../services/place_service.dart';
import '../widgets/family_map.dart';

/// 장소 등록·수정. 지도를 움직여 가운데 핀을 장소에 맞춘다.
class PlaceEditScreen extends StatefulWidget {
  const PlaceEditScreen({
    super.key,
    required this.groupId,
    required this.initialCenter,
    this.place,
  });

  final String groupId;
  final LatLng initialCenter;

  /// 수정할 장소. null 이면 새로 등록.
  final Place? place;

  @override
  State<PlaceEditScreen> createState() => _PlaceEditScreenState();
}

class _PlaceEditScreenState extends State<PlaceEditScreen> {
  final _map = FamilyMapController();
  late final _name = TextEditingController(text: widget.place?.name ?? '');
  late LatLng _center = widget.place?.position ?? widget.initialCenter;
  late String _emoji = widget.place?.emoji ?? placeEmojis.first;
  late int _radius = widget.place?.radius.round() ?? 200;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _onCameraIdle() async {
    final c = await _map.center();
    if (c != null && mounted) setState(() => _center = c);
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    PlaceService.save(
      groupId: widget.groupId,
      placeId: widget.place?.id,
      name: name,
      emoji: _emoji,
      position: _center,
      radius: _radius,
    );
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final place = widget.place!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('장소 삭제'),
        content: Text("'${place.name}'을(를) 삭제할까요? 도착 알림도 더 이상 오지 않아요."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('삭제')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    PlaceService.delete(widget.groupId, place.id);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.place == null ? '장소 등록' : '장소 수정'),
        actions: [
          if (widget.place != null)
            IconButton(tooltip: '삭제', icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                FamilyMap(
                  controller: _map,
                  initialCenter: _center,
                  initialZoom: 16,
                  onCameraIdle: _onCameraIdle,
                  circles: [
                    MapCircle(id: 'radius', center: _center, radius: _radius.toDouble(), color: scheme.primary),
                  ],
                ),
                // 지도 가운데 고정 핀: 지도를 움직여 위치를 맞춘다
                IgnorePointer(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 44),
                    child: Text(_emoji, style: const TextStyle(fontSize: 40)),
                  ),
                ),
                Positioned(
                  top: 12,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Text('지도를 움직여 장소에 맞춰주세요', style: theme.textTheme.bodySmall),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _name,
                    maxLength: 20,
                    decoration: const InputDecoration(
                      labelText: '장소 이름 (예: 집, 회사, 학교)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  SizedBox(
                    height: 48,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final e in placeEmojis)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text(e, style: const TextStyle(fontSize: 20)),
                              selected: e == _emoji,
                              showCheckmark: false,
                              onSelected: (_) => setState(() => _emoji = e),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text('도착 반경', style: theme.textTheme.titleSmall),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SegmentedButton<int>(
                          segments: [
                            for (final r in placeRadii) ButtonSegment(value: r, label: Text('${r}m')),
                          ],
                          selected: {_radius},
                          onSelectionChanged: (v) => setState(() => _radius = v.first),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _name,
                    builder: (context, value, _) => FilledButton(
                      onPressed: value.text.trim().isEmpty ? null : _save,
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      child: const Text('저장'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
