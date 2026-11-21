import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/member.dart';
import '../services/backend.dart';
import '../services/group_service.dart';
import '../services/plan.dart';
import '../widgets/ui.dart';
import 'places_screen.dart';
import '../services/avatars.dart';

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

  Future<void> _createGroup(BuildContext context) async {
    final name = await _prompt(context, '새 그룹', '그룹 이름 (예: 우리 가족)');
    if (name == null || name.isEmpty || !context.mounted) return;
    await _run(context, () async {
      final code = await GroupService.create(name);
      return '그룹을 만들었어요. 초대코드: $code';
    });
  }

  Future<void> _joinGroup(BuildContext context) async {
    final code = await _prompt(context, '그룹 참여', '초대코드 6자리', caps: TextCapitalization.characters);
    if (code == null || code.isEmpty || !context.mounted) return;
    await _run(context, () async {
      final name = await GroupService.requestJoin(code);
      return "'$name' 그룹에 가입을 요청했어요. 방장이 승인하면 위치가 공유됩니다.";
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const PillAppBar(title: '그룹'),
      body: MintBackground(
        child: StreamBuilder<List<Group>>(
          stream: GroupService.myGroups(),
          builder: (context, snap) {
            final groups = snap.data ?? const <Group>[];
            return ListView(
              padding: EdgeInsets.fromLTRB(12, MediaQuery.paddingOf(context).top + 72, 12, 24),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('그룹 만들기'),
                        onPressed: () => _createGroup(context),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(backgroundColor: Colors.white),
                        icon: const Icon(Icons.vpn_key),
                        label: const Text('초대코드 입력'),
                        onPressed: () => _joinGroup(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (snap.connectionState == ConnectionState.waiting)
                  const Center(child: CircularProgressIndicator())
                else if (groups.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(24, 8, 24, 24),
                    child: Text(
                      '그룹을 만들어 초대코드를 가족에게 보내거나,\n받은 초대코드를 입력하세요.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.sub, fontSize: 15, height: 1.5),
                    ),
                  ),
                for (final g in groups) _GroupSection(group: g, members: members, run: _run),
                SoftCard(
                  color: const Color(0xFFE9F7F3),
                  padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                  onTap: () => _createGroup(context),
                  child: const Row(
                    children: [
                      Text('👨‍👩‍👧', style: TextStyle(fontSize: 28)),
                      SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('가족과 함께하는 안전한 위치생활',
                                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.ink)),
                            SizedBox(height: 2),
                            Text('지금 바로 그룹을 만들어 시작해보세요!',
                                style: TextStyle(fontSize: 12.5, color: AppColors.sub)),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, size: 22, color: AppColors.sub),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 그룹 하나: 정보 카드 + 멤버 카드 + 그룹 나가기.
class _GroupSection extends StatelessWidget {
  const _GroupSection({required this.group, required this.members, required this.run});

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

  void _showPlan(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('요금제'),
        content: Text('무료: 멤버 ${Plan.free.maxMembers}명 · 이동경로 ${Plan.free.historyDays}일\n'
            '프리미엄: 멤버 ${Plan.premium.maxMembers}명 · 이동경로 ${Plan.premium.historyDays}일\n\n'
            '가족끼리 쓰는 앱이라 지금은 모두 무료로 써요.'),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('확인'))],
      ),
    );
  }

  Future<void> _memberActions(BuildContext context, String uid) async {
    if (!_isOwner || uid == Backend.uid) return;
    final ok = await _confirm(context, '멤버 내보내기',
        '${_nameOf(uid)}님을 그룹에서 내보낼까요? 서로의 위치를 더 이상 볼 수 없게 됩니다.');
    if (!ok || !context.mounted) return;
    await run(context, () async {
      await GroupService.remove(group.id, uid);
      return null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final plan = Plan.parse(group.planName);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SoftCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                child: Row(
                  children: [
                    const IconBubble(Icons.groups, size: 44, background: AppColors.mint),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(group.name,
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.ink)),
                          const SizedBox(height: 2),
                          Text('멤버 ${group.members.length}/${plan.maxMembers}명 · 이동경로 ${plan.historyDays}일',
                              style: const TextStyle(fontSize: 12.5, color: AppColors.sub)),
                        ],
                      ),
                    ),
                    TagChip(
                      plan == Plan.premium ? '프리미엄' : '무료',
                      trailing: Icons.chevron_right,
                      onTap: () => _showPlan(context),
                    ),
                  ],
                ),
              ),
              if (_isOwner) ...[
                const InsetDivider(),
                _InviteRow(group: group, run: run),
                StreamBuilder<List<JoinRequest>>(
                  stream: GroupService.requests(group.id),
                  builder: (context, snap) {
                    final reqs = snap.data ?? const <JoinRequest>[];
                    if (reqs.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 8, 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('가입 요청',
                              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.ink)),
                          for (final r in reqs)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const IconBubble(Icons.person_add, size: 36),
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
                      ),
                    );
                  },
                ),
              ],
              const InsetDivider(),
              FeatureRow(
                leading: const IconBubble(Icons.location_on, size: 40, color: AppColors.primaryDark),
                title: '장소 (집 · 회사 · 학교)',
                subtitle: '가족이 도착하면 서로에게 알림이 와요',
                trailing: const Icon(Icons.chevron_right, size: 22, color: AppColors.sub),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PlacesScreen(group: group, myPosition: members.me?.position),
                )),
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
        SoftCard(
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 6),
          child: ListenableBuilder(
            listenable: members,
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionLabel('멤버'),
                for (final (i, uid) in _sortedMembers().indexed) ...[
                  if (i > 0) const InsetDivider(indent: 60),
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _memberActions(context, uid),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          _MemberFace(
                            emoji: members.members[uid]?.badge ?? '🙂',
                            highlight: uid == Backend.uid,
                            owner: uid == group.ownerId,
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(_nameOf(uid),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: AppColors.ink)),
                          ),
                          if (uid == group.ownerId) ...[
                            const SizedBox(width: 8),
                            const TagChip('방장'),
                          ],
                          const Spacer(),
                          const Icon(Icons.chevron_right, size: 22, color: AppColors.sub),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(backgroundColor: Colors.white, minimumSize: const Size.fromHeight(46)),
            icon: const Icon(Icons.logout),
            label: Text(group.name.isEmpty ? '그룹 나가기' : "'${group.name}' 나가기"),
            onPressed: () async {
              final ok = await _confirm(
                  context, '그룹 나가기', "'${group.name}' 그룹을 나갈까요? 멤버들이 내 위치를 더 이상 볼 수 없게 됩니다.");
              if (!ok || !context.mounted) return;
              await run(context, () async {
                await GroupService.leave(group.id);
                return '그룹을 나갔어요.';
              });
            },
          ),
        ),
      ],
    );
  }

  /// 나 → 방장 → 나머지 순서
  List<String> _sortedMembers() {
    final list = [...group.members];
    int rank(String uid) => uid == Backend.uid ? 0 : (uid == group.ownerId ? 1 : 2);
    list.sort((a, b) => rank(a).compareTo(rank(b)));
    return list;
  }

  String _nameOf(String uid) {
    if (uid == Backend.uid) return '나';
    return members.members[uid]?.displayName ?? '멤버';
  }
}

/// 멤버 이모지 동그라미. 나는 청록 테두리, 방장은 별 표시.
class _MemberFace extends StatelessWidget {
  const _MemberFace({required this.emoji, required this.highlight, required this.owner});

  final String emoji;
  final bool highlight;
  final bool owner;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: highlight ? AppColors.mintSoft : const Color(0xFFEFF2F1),
            border: highlight ? Border.all(color: AppColors.primary, width: 2.5) : null,
          ),
          alignment: Alignment.center,
          child: AvatarGlyph(emoji, size: 36),
        ),
        if (owner)
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 17,
              height: 17,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(Icons.star, size: 10, color: Colors.white),
            ),
          ),
      ],
    );
  }
}

class _InviteRow extends StatelessWidget {
  const _InviteRow({required this.group, required this.run});
  final Group group;
  final Future<void> Function(BuildContext, Future<String?> Function()) run;

  @override
  Widget build(BuildContext context) {
    final valid = group.inviteValid;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('초대코드', style: TextStyle(fontSize: 12.5, color: AppColors.sub)),
                const SizedBox(height: 2),
                Text(
                  valid ? group.inviteCode! : '만료 됨',
                  style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                      letterSpacing: valid ? 4 : 0),
                ),
                if (valid)
                  Text('${DateFormat('M/d HH:mm').format(group.inviteExpiresAt!)}까지 유효',
                      style: const TextStyle(fontSize: 12, color: AppColors.sub)),
              ],
            ),
          ),
          if (valid)
            _CircleAction(
              tooltip: '복사',
              icon: Icons.copy,
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                await Clipboard.setData(ClipboardData(
                    text: "'${group.name}' 그룹 초대코드: ${group.inviteCode}\n"
                        '패밀리 위치 앱 > 그룹 > 초대코드 입력에서 사용하세요.'));
                messenger.showSnackBar(const SnackBar(content: Text('초대 메시지를 복사했어요.')));
              },
            ),
          const SizedBox(width: 8),
          _CircleAction(
            tooltip: '새 코드 발급',
            icon: Icons.refresh,
            onTap: () => run(context, () async {
              await GroupService.regenerateInvite(group.id);
              return '새 초대코드를 발급했어요. 이전 코드는 더 이상 사용할 수 없어요.';
            }),
          ),
        ],
      ),
    );
  }
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({required this.tooltip, required this.icon, required this.onTap});

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.mint,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 42, height: 42, child: Icon(icon, size: 21, color: AppColors.primaryDark)),
        ),
      ),
    );
  }
}
