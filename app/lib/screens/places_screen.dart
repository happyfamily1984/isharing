import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../models/member.dart';
import '../services/place_service.dart';
import 'place_edit_screen.dart';

/// 그룹의 장소 목록. 가족이 여기 등록된 장소에 도착하면 서로에게 알림이 간다.
class PlacesScreen extends StatelessWidget {
  const PlacesScreen({super.key, required this.group, required this.myPosition});

  final Group group;

  /// 새 장소를 등록할 때 지도를 처음 보여줄 위치 (내 현재 위치)
  final LatLng? myPosition;

  void _edit(BuildContext context, [Place? place]) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlaceEditScreen(
        groupId: group.id,
        place: place,
        initialCenter: myPosition ?? const LatLng(37.5665, 126.9780),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${group.name} · 장소')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context),
        icon: const Icon(Icons.add_location_alt),
        label: const Text('장소 등록'),
      ),
      body: StreamBuilder<List<Place>>(
        stream: PlaceService.places(group.id),
        builder: (context, snap) {
          final places = snap.data ?? const <Place>[];
          if (snap.connectionState == ConnectionState.waiting && places.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (places.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  '집, 회사, 학교 같은 장소를 등록하면\n가족이 도착했을 때 서로에게 알림이 와요.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              for (final p in places)
                ListTile(
                  leading: CircleAvatar(child: Text(p.emoji, style: const TextStyle(fontSize: 22))),
                  title: Text(p.name),
                  subtitle: Text('도착 반경 ${p.radius.round()}m'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _edit(context, p),
                ),
            ],
          );
        },
      ),
    );
  }
}
