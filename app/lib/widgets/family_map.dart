import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:latlong2/latlong.dart';

import '../config.dart';

/// 지도 위에 표시할 핀.
class MapPin {
  const MapPin({
    required this.id,
    required this.position,
    required this.label,
    required this.color,
    this.subLabel,
    this.onTap,
  });

  final String id;
  final LatLng position;
  final String label;
  final String? subLabel;
  final Color color;
  final VoidCallback? onTap;
}

/// 화면에서 지도 카메라를 움직일 때 쓰는 컨트롤러.
class FamilyMapController {
  NaverMapController? _map;

  Future<void> moveTo(LatLng target, {double zoom = 15}) async {
    await _map?.updateCamera(NCameraUpdate.scrollAndZoomTo(target: _n(target), zoom: zoom));
  }

  /// 모든 점이 화면에 들어오게 맞춘다.
  Future<void> fit(List<LatLng> points) async {
    if (points.isEmpty) return;
    if (points.length == 1) return moveTo(points.first, zoom: 16);
    await _map?.updateCamera(NCameraUpdate.fitBounds(
      NLatLngBounds.from(points.map(_n)),
      padding: const EdgeInsets.all(56),
    ));
  }
}

NLatLng _n(LatLng p) => NLatLng(p.latitude, p.longitude);

/// 네이버 지도. 핀과 경로를 선언적으로 받아 지도에 그린다.
class FamilyMap extends StatefulWidget {
  const FamilyMap({
    super.key,
    required this.controller,
    this.pins = const [],
    this.path = const [],
    this.pathColor,
    this.initialCenter = const LatLng(37.5665, 126.9780), // 서울시청
    this.initialZoom = 11,
    this.onReady,
  });

  final FamilyMapController controller;
  final List<MapPin> pins;
  final List<LatLng> path;
  final Color? pathColor;
  final LatLng initialCenter;
  final double initialZoom;
  final VoidCallback? onReady;

  @override
  State<FamilyMap> createState() => _FamilyMapState();
}

class _FamilyMapState extends State<FamilyMap> {
  NaverMapController? _map;

  @override
  void didUpdateWidget(FamilyMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncOverlays();
  }

  Future<void> _syncOverlays() async {
    final map = _map;
    if (map == null) return;
    final overlays = <NAddableOverlay>{};
    if (widget.path.length > 1) {
      overlays.add(NPathOverlay(
        id: 'path',
        coords: widget.path.map(_n),
        width: 6,
        color: widget.pathColor ?? Theme.of(context).colorScheme.primary,
        outlineWidth: 1,
        outlineColor: Colors.white,
      ));
    }
    for (final pin in widget.pins) {
      final marker = NMarker(
        id: pin.id,
        position: _n(pin.position),
        iconTintColor: pin.color,
        caption: NOverlayCaption(text: pin.label, textSize: 13),
        subCaption: pin.subLabel == null
            ? null
            : NOverlayCaption(text: pin.subLabel!, textSize: 11, color: Colors.black54),
        isHideCollidedCaptions: false,
      );
      if (pin.onTap != null) marker.setOnTapListener((_) => pin.onTap!());
      overlays.add(marker);
    }
    // 멤버 수가 적어 매번 다시 그려도 충분히 가볍다.
    await map.clearOverlays();
    if (overlays.isNotEmpty) await map.addOverlayAll(overlays);
  }

  @override
  Widget build(BuildContext context) {
    if (AppConfig.naverMapClientId.isEmpty) {
      return const ColoredBox(
        color: Color(0xFFE8EEF0),
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              '네이버 지도 Client ID가 설정되지 않았어요.\n(README의 "네이버 지도 설정" 참고)',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return NaverMap(
      options: NaverMapViewOptions(
        initialCameraPosition:
            NCameraPosition(target: _n(widget.initialCenter), zoom: widget.initialZoom),
        locale: const NLocale('ko', 'KR'),
        scaleBarEnable: false,
        indoorEnable: false,
        consumeSymbolTapEvents: false,
      ),
      onMapReady: (controller) {
        _map = controller;
        widget.controller._map = controller;
        _syncOverlays();
        widget.onReady?.call();
      },
    );
  }
}
