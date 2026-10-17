import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../models/member.dart';
import 'backend.dart';

/// 장소 아이콘 후보
const placeEmojis = ['🏠', '🏢', '🏫', '🏥', '🛒', '🏋️', '⛪', '🍽️', '☕', '🌳', '👵', '📍'];

/// 도착 반경 후보(m)
const placeRadii = [100, 200, 500];

class PlaceService {
  PlaceService._();

  static CollectionReference<Map<String, dynamic>> _col(String groupId) =>
      Backend.db.collection('groups').doc(groupId).collection('places');

  static Stream<List<Place>> places(String groupId) => _col(groupId)
      .orderBy('name')
      .snapshots()
      .map((s) => s.docs.map((d) => Place.fromDoc(groupId, d)).toList());

  /// 서버 응답을 기다리지 않는다 (신호가 약해도 바로 반영되고 연결되면 올라감).
  static void save({
    required String groupId,
    String? placeId,
    required String name,
    required String emoji,
    required LatLng position,
    required int radius,
  }) {
    final data = {
      'name': name,
      'emoji': emoji,
      'lat': position.latitude,
      'lng': position.longitude,
      'radius': radius,
      'createdBy': Backend.uid,
      'createdAt': FieldValue.serverTimestamp(),
    };
    final ref = placeId == null ? _col(groupId).doc() : _col(groupId).doc(placeId);
    unawaited(ref.set(data).then((_) {}, onError: (Object e) => debugPrint('장소 저장 실패: $e')));
  }

  static void delete(String groupId, String placeId) => unawaited(_col(groupId)
      .doc(placeId)
      .delete()
      .then((_) {}, onError: (Object e) => debugPrint('장소 삭제 실패: $e')));
}

/// 내가 속한 모든 그룹의 장소를 실시간으로 모은다 (홈 지도 표시용).
class PlacesController extends ChangeNotifier {
  final Map<String, StreamSubscription<List<Place>>> _subs = {};
  final Map<String, List<Place>> _byGroup = {};

  List<Place> get all => _byGroup.values.expand((p) => p).toList();

  void setGroups(Iterable<String> groupIds) {
    final ids = groupIds.toSet();
    for (final id in _subs.keys.toList()) {
      if (!ids.contains(id)) {
        _subs.remove(id)?.cancel();
        _byGroup.remove(id);
      }
    }
    for (final id in ids) {
      _subs.putIfAbsent(
        id,
        () => PlaceService.places(id).listen(
          (places) {
            _byGroup[id] = places;
            notifyListeners();
          },
          onError: (Object _) {}, // 그룹에서 나간 직후 권한 오류는 무시
        ),
      );
    }
    notifyListeners();
  }

  @override
  void dispose() {
    for (final s in _subs.values) {
      s.cancel();
    }
    super.dispose();
  }
}
