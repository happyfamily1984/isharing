import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../config.dart';

/// 지도 위에 표시할 핀.
class MapPin {
  const MapPin({
    required this.id,
    required this.position,
    required this.label,
    required this.color,
    this.subLabel,
    this.emoji,
    this.onTap,
  });

  final String id;
  final LatLng position;
  final String label;
  final String? subLabel;
  final Color color;

  /// 지정하면 기본 핀 대신 이모지 말풍선으로 표시한다.
  final String? emoji;
  final VoidCallback? onTap;
}

/// 지도에 그릴 선 (이동경로).
class MapLine {
  const MapLine({required this.id, required this.points, required this.color, this.width = 6});

  final String id;
  final List<LatLng> points;
  final Color color;
  final double width;
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
    this.lines = const [],
    this.initialCenter = const LatLng(37.5665, 126.9780), // 서울시청
    this.initialZoom = 11,
    this.onReady,
  });

  final FamilyMapController controller;
  final List<MapPin> pins;
  final List<MapLine> lines;
  final LatLng initialCenter;
  final double initialZoom;
  final VoidCallback? onReady;

  @override
  State<FamilyMap> createState() => _FamilyMapState();
}

class _FamilyMapState extends State<FamilyMap> {
  NaverMapController? _map;
  final _iconCache = <String, NOverlayImage>{};
  int _syncGeneration = 0;

  Future<NOverlayImage> _emojiIcon(String emoji, Color color) async {
    final key = '$emoji|${color.toARGB32()}';
    final cached = _iconCache[key];
    if (cached != null) return cached;
    final icon = await NOverlayImage.fromWidget(
      widget: _EmojiPin(emoji: emoji, color: color),
      size: _EmojiPin.size,
      context: context,
    );
    return _iconCache[key] = icon;
  }

  @override
  void didUpdateWidget(FamilyMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncOverlays();
  }

  Future<void> _syncOverlays() async {
    final map = _map;
    if (map == null) return;
    final generation = ++_syncGeneration;
    final overlays = <NAddableOverlay>{};
    for (final line in widget.lines) {
      if (line.points.length < 2) continue;
      overlays.add(NPathOverlay(
        id: line.id,
        coords: line.points.map(_n),
        width: line.width,
        color: line.color,
        outlineWidth: 1,
        outlineColor: Colors.white,
      ));
    }
    for (final pin in widget.pins) {
      final emoji = pin.emoji;
      final marker = NMarker(
        id: pin.id,
        position: _n(pin.position),
        icon: emoji == null ? null : await _emojiIcon(emoji, pin.color),
        iconTintColor: emoji == null ? pin.color : Colors.transparent,
        caption: NOverlayCaption(text: pin.label, textSize: 13),
        subCaption: pin.subLabel == null
            ? null
            : NOverlayCaption(text: pin.subLabel!, textSize: 11, color: Colors.black54),
      );
      if (pin.onTap != null) marker.setOnTapListener((_) => pin.onTap!());
      overlays.add(marker);
    }
    // 아이콘을 만드는 동안 더 새로운 갱신이 들어왔으면 이번 결과는 버린다.
    if (!mounted || generation != _syncGeneration) return;
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

/// 이모지 말풍선 핀. 아래 꼬리 끝이 실제 위치를 가리킨다.
class _EmojiPin extends StatelessWidget {
  const _EmojiPin({required this.emoji, required this.color});

  static const size = Size(52, 60);

  final String emoji;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.fromSize(
      size: size,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            bottom: 0,
            child: CustomPaint(size: const Size(14, 10), painter: _TailPainter(color)),
          ),
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: color, width: 3.5),
            ),
            alignment: Alignment.center,
            child: Text(emoji, style: const TextStyle(fontSize: 28, height: 1.1)),
          ),
        ],
      ),
    );
  }
}

class _TailPainter extends CustomPainter {
  _TailPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TailPainter old) => old.color != color;
}
