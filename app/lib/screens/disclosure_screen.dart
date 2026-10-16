import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../config.dart';

/// Google Play 정책의 "명시적 고지(Prominent Disclosure)" 화면.
/// 위치 권한을 요청하기 전에 반드시 이 화면을 보여주고 동의를 받아야 한다.
/// 동의하고 권한을 얻으면 true 를 돌려준다.
class DisclosureScreen extends StatefulWidget {
  const DisclosureScreen({super.key});

  static Future<bool> show(BuildContext context) async =>
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(fullscreenDialog: true, builder: (_) => const DisclosureScreen()),
      ) ??
      false;

  @override
  State<DisclosureScreen> createState() => _DisclosureScreenState();
}

class _DisclosureScreenState extends State<DisclosureScreen> {
  bool _busy = false;

  Future<void> _accept() async {
    setState(() => _busy = true);
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (!mounted) return;

    if (perm == LocationPermission.deniedForever) {
      await _info('위치 권한이 꺼져 있어요',
          '설정 > 앱 > ${AppConfig.appName} > 권한에서 위치를 허용해주세요.');
      await Geolocator.openAppSettings();
      if (mounted) Navigator.of(context).pop(false);
      return;
    }
    if (perm == LocationPermission.denied) {
      Navigator.of(context).pop(false);
      return;
    }

    // Android 10+ 는 '항상 허용'을 설정 화면에서만 고를 수 있다.
    if (Platform.isAndroid && perm == LocationPermission.whileInUse) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('"항상 허용"을 권장해요'),
          content: const Text(
              '휴대폰을 재시작하거나 앱이 종료된 뒤에도 위치 공유가 이어지려면 '
              '다음 화면의 위치 권한에서 "항상 허용"을 선택해주세요.\n\n'
              '"앱 사용 중에만 허용"이어도 상단 알림이 떠 있는 동안에는 공유됩니다.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('나중에')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('설정 열기')),
          ],
        ),
      );
      if (go == true) await Geolocator.openAppSettings();
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _info(String title, String body) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('확인'))],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget item(IconData icon, String title, String body) => ListTile(
          leading: Icon(icon, color: theme.colorScheme.primary),
          title: Text(title),
          subtitle: Text(body),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('위치 정보 사용 안내')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 16),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      '${AppConfig.appName}은(는) 앱이 닫혀 있거나 사용 중이 아닐 때에도 '
                      '위치 정보를 수집하여, 내가 가입을 승인받은 그룹의 멤버에게 공유합니다.',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: 16),
                  item(Icons.groups, '누구에게 공유되나요?',
                      '내가 직접 참여한 그룹의 멤버에게만 보입니다. 광고나 제3자에게 제공하지 않습니다.'),
                  item(Icons.route, '무엇이 저장되나요?',
                      '현재 위치, 시간대별 이동경로, 배터리 잔량. 이동경로는 최대 30일 후 자동 삭제됩니다.'),
                  item(Icons.power_settings_new, '전원이 꺼지면?',
                      '꺼지기 전 마지막으로 확인된 위치가 그룹 멤버에게 표시됩니다.'),
                  item(Icons.notifications_active, '상단 알림',
                      '위치를 공유하는 동안에는 항상 알림이 표시됩니다.'),
                  item(Icons.pause_circle, '언제든 중지',
                      '설정에서 위치 공유를 일시중지하거나 그룹을 나가거나 탈퇴할 수 있습니다.'),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => Navigator.of(context).pop(false),
                      child: const Text('거부'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy ? null : _accept,
                      child: const Text('동의하고 계속'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
