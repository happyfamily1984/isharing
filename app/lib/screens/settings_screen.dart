import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../services/auth_service.dart';
import '../services/backend.dart';
import '../services/location_service.dart';
import 'home_screen.dart';
import 'profile_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _setSharing(BuildContext context, bool on) async {
    final messenger = ScaffoldMessenger.of(context);
    if (on) {
      if (!await ensureSharing(context)) {
        messenger.showSnackBar(const SnackBar(content: Text('위치 권한이 필요해요.')));
        return;
      }
      await Backend.userDoc(Backend.uid).set({'sharing': true}, SetOptions(merge: true));
    } else {
      await LocationService.instance.stop();
      // 일시중지하면 마지막 위치도 숨긴다.
      await Backend.userDoc(Backend.uid).set(
          {'sharing': false, 'lastLocation': FieldValue.delete()}, SetOptions(merge: true));
    }
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final usesPassword = AuthService.usesPassword;
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('회원 탈퇴'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('모든 그룹에서 나가고 위치·이동경로 기록이 즉시 삭제됩니다. 되돌릴 수 없어요.'),
            if (usesPassword)
              TextField(
                controller: controller,
                obscureText: true,
                decoration: const InputDecoration(labelText: '비밀번호 확인'),
              )
            else
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('본인 확인을 위해 구글 로그인 창이 한 번 더 열립니다.'),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('탈퇴'),
          ),
        ],
      ),
    );
    final password = controller.text;
    controller.dispose();
    if (confirmed != true || (usesPassword && password.isEmpty) || !context.mounted) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await AuthService.deleteAccount(password: password);
      navigator.popUntil((r) => r.isFirst);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(Backend.errorMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: Backend.userDoc(Backend.uid).snapshots(),
        builder: (context, snap) {
          final data = snap.data?.data() ?? const {};
          final sharing = (data['sharing'] as bool?) ?? true;
          final name = (data['displayName'] as String?) ?? '';
          return ListView(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.share_location),
                title: const Text('내 위치 공유'),
                subtitle: Text(sharing ? '그룹 멤버에게 내 위치를 공유하고 있어요' : '일시중지됨 · 멤버에게 내 위치가 보이지 않아요'),
                value: sharing,
                onChanged: (v) => _setSharing(context, v),
              ),
              ListTile(
                leading: CircleAvatar(
                  child: Text((data['avatar'] as String?) ?? '🙂',
                      style: const TextStyle(fontSize: 22)),
                ),
                title: const Text('프로필 (이름 · 캐릭터)'),
                subtitle: Text(name),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => ProfileScreen.show(
                  context,
                  name: name,
                  avatar: data['avatar'] as String?,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.email),
                title: const Text('계정'),
                subtitle: Text(Backend.auth.currentUser?.email ?? ''),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.privacy_tip),
                title: const Text('개인정보처리방침'),
                onTap: () => launchUrl(Uri.parse(AppConfig.privacyPolicyUrl)),
              ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('로그아웃'),
                onTap: () async {
                  final navigator = Navigator.of(context);
                  await AuthService.signOut();
                  navigator.popUntil((r) => r.isFirst);
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_forever, color: Theme.of(context).colorScheme.error),
                title: Text('회원 탈퇴',
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
                onTap: () => _deleteAccount(context),
              ),
            ],
          );
        },
      ),
    );
  }
}
