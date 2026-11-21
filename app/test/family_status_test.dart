import 'package:flutter_test/flutter_test.dart';
import 'package:isharing/models/member.dart';
import 'package:isharing/services/family_status.dart';
import 'package:latlong2/latlong.dart';

void main() {
  test('near a registered place', () {
    final home = Place(id: 'h', groupId: 'g', name: '집', emoji: '🏠', position: const LatLng(37.5, 127.0), radius: 150);
    expect(nearPlaceLabel(const LatLng(37.5005, 127.0), [home]), '집에 있어요');
    expect(nearPlaceLabel(const LatLng(37.503, 127.0), [home]), '집 근처');
    expect(nearPlaceLabel(const LatLng(37.52, 127.0), [home]), isNull);
  });
}
