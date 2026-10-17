import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../config.dart';

/// 앱 공통 지도 배경. 다크 모드에서는 어두운 지도를 쓴다.
class AppTileLayer extends StatelessWidget {
  const AppTileLayer({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return TileLayer(
      urlTemplate: dark ? AppConfig.tileUrlDark : AppConfig.tileUrlLight,
      userAgentPackageName: AppConfig.tileUserAgent,
      retinaMode: RetinaMode.isHighDensity(context),
    );
  }
}

/// 지도 출처 표기 (사용 조건상 필수)
class AppMapAttribution extends StatelessWidget {
  const AppMapAttribution({super.key});

  @override
  Widget build(BuildContext context) =>
      const SimpleAttributionWidget(source: Text('© OpenStreetMap contributors © CARTO'));
}
