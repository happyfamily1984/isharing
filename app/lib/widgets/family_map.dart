import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:latlong2/latlong.dart' show Distance, LatLng;

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

/// 지도에 그릴 원 (등록한 장소의 도착 반경).
class MapCircle {
  const MapCircle({required this.id, required this.center, required this.radius, required this.color});

  final String id;
  final LatLng center;
  final double radius;
  final Color color;
}

/// 화면에서 지도 카메라를 움직일 때 쓰는 컨트롤러.
class FamilyMapController {
  NaverMapController? _map;
  void Function(String what, Object error)? _onError;

  Future<void> _update(NCameraUpdate update) async {
    final map = _map;
    if (map == null) return;
    update.setAnimation(duration: const Duration(milliseconds: 600));
    try {
      await map.updateCamera(update);
    } catch (e) {
      _onError?.call('카메라 이동', e);
    }
  }

  Future<void> moveTo(LatLng target, {double zoom = 15}) =>
      _update(NCameraUpdate.scrollAndZoomTo(target: _n(target), zoom: zoom));

  /// 지금 지도 화면 가운데 좌표
  Future<LatLng?> center() async {
    final map = _map;
    if (map == null) return null;
    final target = (await map.getCameraPosition()).target;
    return LatLng(target.latitude, target.longitude);
  }

  /// 모든 점이 화면 가운데에 다 보이도록 위치와 확대 수준을 맞춘다.
  /// 한 자리에 모여 있는 점(머문 곳)은 너무 확대되지 않게 적당한 수준으로 보여준다.
  Future<void> fit(List<LatLng> points) async {
    if (points.isEmpty) return;
    final bounds = NLatLngBounds.from(points.map(_n));
    const distance = Distance();
    final spanMeters = distance(
      LatLng(bounds.southWest.latitude, bounds.southWest.longitude),
      LatLng(bounds.northEast.latitude, bounds.northEast.longitude),
    );
    if (spanMeters < 150) {
      final c = bounds.center;
      return moveTo(LatLng(c.latitude, c.longitude), zoom: 16);
    }
    // 위아래는 핀 이름표가 잘리지 않게 여백을 더 둔다.
    await _update(NCameraUpdate.fitBounds(
      bounds,
      padding: const EdgeInsets.fromLTRB(48, 72, 48, 72),
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
    this.circles = const [],
    this.onCameraIdle,
    this.initialCenter = const LatLng(37.5665, 126.9780), // 서울시청
    this.initialZoom = 11,
    this.onReady,
  });

  final FamilyMapController controller;
  final List<MapPin> pins;
  final List<MapLine> lines;
  final List<MapCircle> circles;

  /// 사용자가 지도를 움직이다 멈췄을 때
  final VoidCallback? onCameraIdle;
  final LatLng initialCenter;
  final double initialZoom;
  final VoidCallback? onReady;

  @override
  State<FamilyMap> createState() => _FamilyMapState();
}

class _FamilyMapState extends State<FamilyMap> {
  NaverMapController? _map;
  final _iconCache = <String, NOverlayImage>{};

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

  /// 갱신 요청이 겹치면 지우기·그리기가 뒤섞이므로 하나씩 순서대로 처리한다.
  Future<void> _syncChain = Future.value();
  bool _syncPending = false;

  void _syncOverlays() {
    if (_syncPending) return; // 이미 대기 중인 갱신이 최신 위젯 상태로 그린다.
    _syncPending = true;
    _syncChain = _syncChain.then((_) async {
      _syncPending = false;
      try {
        await _drawOverlays();
      } catch (e) {
        _reportError('지도 그리기', e);
      }
    });
  }

  Future<void> _drawOverlays() async {
    final map = _map;
    if (map == null || !mounted) return;
    final overlays = <NAddableOverlay>[];
    for (final c in widget.circles) {
      overlays.add(NCircleOverlay(
        id: c.id,
        center: _n(c.center),
        radius: c.radius,
        color: c.color.withValues(alpha: 0.15),
        outlineColor: c.color.withValues(alpha: 0.6),
        outlineWidth: 1.5,
      ));
    }
    for (final line in widget.lines) {
      final coords = _dedupe(line.points);
      if (coords.length < 2) continue;
      overlays.add(NPathOverlay(
        id: line.id,
        coords: coords,
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
    if (!mounted) return;
    // 멤버 수가 적어 매번 다시 그려도 충분히 가볍다.
    await map.clearOverlays();
    // 하나가 실패해도 나머지는 보이도록 따로따로 추가한다.
    for (final overlay in overlays) {
      try {
        await map.addOverlay(overlay);
      } catch (e) {
        _reportError('${overlay.info.type.name} ${overlay.info.id}', e);
      }
    }
  }

  /// 연속으로 같은 좌표가 찍힌 점은 하나로 줄인다 (선 그리기 오류 방지).
  static List<NLatLng> _dedupe(List<LatLng> points) {
    final out = <NLatLng>[];
    for (final p in points) {
      final n = _n(p);
      if (out.isEmpty || out.last.latitude != n.latitude || out.last.longitude != n.longitude) {
        out.add(n);
      }
    }
    return out;
  }

  /// 테스트 중 원인 파악을 위해 지도 오류를 화면에 보여준다.
  void _reportError(String what, Object e) {
    debugPrint('지도 오류 ($what): $e');
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text('지도 표시 오류 ($what): $e'),
      duration: const Duration(seconds: 8),
    ));
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
      onCameraIdle: widget.onCameraIdle,
      onMapReady: (controller) {
        _map = controller;
        widget.controller._map = controller;
        widget.controller._onError = _reportError;
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
