import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/member.dart';
import '../services/backend.dart';
import '../services/group_service.dart';
import '../services/plan.dart';
import 'places_screen.dart';

/// 그룹 만들기 / 초대코드로 가입 요청 / 가입 승인 / 멤버 관리.
class GroupsScreen extends StatelessWidget {
  const GroupsScreen({super.key, required this.members});
  final MembersController members;

  Future<void> _run(BuildContext context, Future<String?> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final msg = await action();
      if (msg != null) messenger.showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(Backend.errorMessage(e))));
    }
  }

  Future<String?> _prompt(BuildContext context, String title, String label,
      {TextCapitalization caps = TextCapitalization.none}) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: caps,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('확인')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('그룹')),
      body: StreamBuilder<List<Group>>(
        stream: GroupService.myGroups(),
        builder: (context, snap) {
          final groups = snap.data ?? const <Group>[];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('그룹 만들기'),
                      onPressed: () async {
                        final name = await _prompt(context, '새 그룹', '그룹 이름 (예: 우리 가족)');
                        if (name == null || name.isEmpty || !context.mounted) return;
                        await _run(context, () async {
                          final code = await GroupService.create(name);
                          return '그룹을 만들었어요. 초대코드: $code';
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.vpn_key),
                      label: const Text('초대코드 입력'),
                      onPressed: () async {
                        final code = await _prompt(context, '그룹 참여', '초대코드 6자리',
                            caps: TextCapitalization.characters);
                        if (code == null || code.isEmpty || !context.mounted) return;
                        await _run(context, () async {
                          final name = await GroupService.requestJoin(code);
                          return "'$name' 그룹에 가입을 요청했어요. 방장이 승인하면 위치가 공유됩니다.";
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (snap.connectionState == ConnectionState.waiting)
                const Center(child: CircularProgressIndicator())
              else if (groups.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    '그룹을 만들어 초대코드를 가족에게 보내거나,\n받은 초대코드를 입력하세요.',
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final g in groups) _GroupCard(group: g, members: members, run: _run),
            ],
          );
        },
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group, required this.members, required this.run});

  final Group group;
  final MembersController members;
  final Future<void> Function(BuildContext, Future<String?> Function()) run;

  bool get _isOwner => group.ownerId == Backend.uid;

  Future<bool> _confirm(BuildContext context, String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('확인')),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = Plan.parse(group.planName);
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(group.name, style: theme.textTheme.titleLarge)),
                Chip(label: Text(plan == Plan.premium ? '프리미엄' : '무료')),
              ],
            ),
            Text('멤버 ${group.members.length}/${plan.maxMembers}명 · 이동경로 ${plan.historyDays}일',
                style: theme.textTheme.bodySmall),
            const Divider(height: 24),
            if (_isOwner) ...[
              _InviteRow(group: group, run: run),
              StreamBuilder<List<JoinRequest>>(
                stream: GroupService.requests(group.id),
                builder: (context, snap) {
                  final reqs = snap.data ?? const <JoinRequest>[];
                  if (reqs.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      Text('가입 요청', style: theme.textTheme.titleSmall),
                      for (final r in reqs)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.person_add),
                          title: Text(r.displayName),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: '거절',
                                icon: const Icon(Icons.close),
                                onPressed: () => run(context, () async {
                                  await GroupService.respond(group.id, r.uid, approve: false);
                                  return '거절했어요.';
                                }),
                              ),
                              IconButton.filled(
                                tooltip: '승인',
                                icon: const Icon(Icons.check),
                                onPressed: () => run(context, () async {
                                  await GroupService.respond(group.id, r.uid, approve: true);
                                  return '${r.displayName}님이 그룹에 참여했어요.';
                                }),
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
              const Divider(height: 24),
            ],
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.place),
              title: const Text('장소 (집 · 회사 · 학교)'),
              subtitle: const Text('가족이 도착하면 서로에게 알림이 와요'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PlacesScreen(group: group, myPosition: members.me?.position),
              )),
            ),
            const Divider(height: 24),
            Text('멤버', style: theme.textTheme.titleSmall),
            ListenableBuilder(
              listenable: members,
              builder: (context, _) => Column(
                children: [
                  for (final uid in group.members)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(uid == group.ownerId ? Icons.star : Icons.person),
                      title: Text(_nameOf(uid)),
                      subtitle: uid == group.ownerId ? const Text('방장') : null,
                      trailing: _isOwner && uid != Backend.uid
                          ? IconButton(
                              tooltip: '내보내기',
                              icon: const Icon(Icons.person_remove),
                              onPressed: () async {
                                final ok = await _confirm(context, '멤버 내보내기',
                                    '${_nameOf(uid)}님을 그룹에서 내보낼까요? 서로의 위치를 더 이상 볼 수 없게 됩니다.');
                                if (!ok || !context.mounted) return;
                                await run(context, () async {
                                  await GroupService.remove(group.id, uid);
                                  return null;
                                });
                              },
                            )
                          : null,
                    ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.logout),
                label: const Text('그룹 나가기'),
                onPressed: () async {
                  final ok = await _confirm(context, '그룹 나가기',
                      "'${group.name}' 그룹을 나갈까요? 멤버들이 내 위치를 더 이상 볼 수 없게 됩니다.");
                  if (!ok || !context.mounted) return;
                  await run(context, () async {
                    await GroupService.leave(group.id);
                    return '그룹을 나갔어요.';
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _nameOf(String uid) {
    if (uid == Backend.uid) return '나';
    return members.members[uid]?.displayName ?? '멤버';
  }
}

class _InviteRow extends StatelessWidget {
  const _InviteRow({required this.group, required this.run});
  final Group group;
  final Future<void> Function(BuildContext, Future<String?> Function()) run;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valid = group.inviteValid;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('초대코드', style: theme.textTheme.titleSmall),
              Text(
                valid ? group.inviteCode! : '만료됨',
                style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: 4),
              ),
              if (valid)
                Text('${DateFormat('M/d HH:mm').format(group.inviteExpiresAt!)}까지 유효',
                    style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        if (valid)
          IconButton(
            tooltip: '복사',
            icon: const Icon(Icons.copy),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await Clipboard.setData(ClipboardData(
                  text: "'${group.name}' 그룹 초대코드: ${group.inviteCode}\n"
                      '패밀리 위치 앱 > 그룹 > 초대코드 입력에서 사용하세요.'));
              messenger.showSnackBar(const SnackBar(content: Text('초대 메시지를 복사했어요.')));
            },
          ),
        IconButton(
          tooltip: '새 코드 발급',
          icon: const Icon(Icons.refresh),
          onPressed: () => run(context, () async {
            await GroupService.regenerateInvite(group.id);
            return '새 초대코드를 발급했어요. 이전 코드는 더 이상 사용할 수 없어요.';
          }),
        ),
      ],
    );
  }
}
