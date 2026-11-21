import 'package:latlong2/latlong.dart';

import '../models/member.dart';

/// 등록된 장소 근처면 "집에 있어요" / "학교 근처" 를 돌려준다.
String? nearPlaceLabel(LatLng? position, List<Place> places) {
  if (position == null || places.isEmpty) return null;
  const distance = Distance();
  Place? best;
  var bestD = double.infinity;
  for (final p in places) {
    final d = distance(position, p.position);
    if (d < bestD) {
      bestD = d;
      best = p;
    }
  }
  if (best == null) return null;
  if (bestD <= best.radius) return '${best.name}에 있어요';
  if (bestD <= best.radius + 300) return '${best.name} 근처';
  return null;
}
