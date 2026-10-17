import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../config.dart';
import '../models/member.dart';
import '../widgets/family_map.dart';
import '../services/auth_service.dart';
import '../services/backend.dart';
import '../services/group_service.dart';
import '../services/location_service.dart';
import '../services/messaging_service.dart';
import '../services/place_service.dart';
import '../services/plan.dart';
import 'disclosure_screen.dart';
import 'profile_screen.dart';
import 'groups_screen.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _map = FamilyMapController();
  final _members = MembersController();
  final _places = PlacesController();
  List<Group> _groups = const [];
  StreamSubscription<List<Group>>? _groupsSub;
  StreamSubscription<String>? _ringSub;
  StreamSubscription<String>? _alertSub;
  Timer? _clock;
  bool _centeredOnce = false;

  @override
  void initState() {
    super.initState();
    _groupsSub = GroupService.myGroups().listen((g) {
      setState(() => _groups = g);
      _places.setGroups(g.map((group) => group.id));
    });
    _ringSub = MessagingService.incomingRings.listen(_onRing);
    _alertSub = MessagingService.incomingAlerts.listen((text) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ));
    });
    _members.addListener(_onMembersChanged);
    // "3분 전", 온라인/오프라인 표시가 저절로 바뀌도록 30초마다 다시 그린다
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _startup());
  }

  @override
  void dispose() {
    _groupsSub?.cancel();
    _ringSub?.cancel();
    _alertSub?.cancel();
    _clock?.cancel();
    _members.dispose();
    _places.dispose();
    super.dispose();
  }

  Future<void> _startup() async {
    try {
      await MessagingService.init();
    } catch (e) {
      debugPrint('messaging init failed: $e');
    }
    final me = await Backend.userDoc(Backend.uid).get();
    if (!mounted) return;
    final data = me.data() ?? const <String, dynamic>{};
    // 처음 한 번 이름과 지도에 보일 캐릭터를 정한다.
    if (data['avatar'] == null ||
        (data['nameConfirmed'] != true && !AuthService.usesPassword)) {
      await ProfileScreen.show(
        context,
        name: (data['displayName'] as String?) ?? '',
        avatar: data['avatar'] as String?,
        required: true,
      );
      if (!mounted) return;
    }
    if ((data['sharing'] as bool?) ?? true) {
      final started = await ensureSharing(context);
      if (started && mounted) await _checkPreciseLocation();
    }
  }

  /// "대략적인 위치"만 허용돼 있으면 오차가 수 km 라서 정확한 위치를 켜도록 안내한다.
  Future<void> _checkPreciseLocation() async {
    if (!await LocationService.isApproximateOnly() || !mounted) return;
    if (Platform.isIOS) {
      await Geolocator.requestTemporaryFullAccuracy(purposeKey: 'FamilyLocation');
      return;
    }
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.gps_fixed),
        title: const Text('정확한 위치를 켜주세요'),
        content: const Text('지금은 "대략적인 위치"만 허용돼 있어서 가족에게 보이는 내 위치가 '
            '1~3km 까지 틀릴 수 있어요.\n\n'
            '설정 > 권한 > 위치에서 "정확한 위치 사용"을 켜주세요.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('나중에')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('설정 열기')),
        ],
      ),
    );
    if (go == true) await Geolocator.openAppSettings();
  }

  void _onMembersChanged() {
    if (!_centeredOnce && _members.me?.position != null) {
      _centeredOnce = true;
      _map.moveTo(_members.me!.position!, zoom: 15);
    }
  }

  void _onRing(String fromName) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.notifications_active, size: 40),
        title: const Text('휴대폰 찾기'),
        content: Text(fromName.isEmpty ? '벨이 울리고 있어요' : '$fromName님이 벨을 울리고 있어요'),
        actions: [
          FilledButton(
            onPressed: () {
              MessagingService.stopRinging();
              Navigator.pop(ctx);
            },
            child: const Text('벨 끄기'),
          ),
        ],
      ),
    );
  }

  /// 나와 해당 멤버가 함께 속한 그룹 중 가장 좋은 요금제 (이동경로 열람 기간 결정)
  Plan _planWith(String uid) {
    final shared = _groups.where((g) => g.members.contains(uid));
    return shared.any((g) => Plan.parse(g.planName) == Plan.premium) ? Plan.premium : Plan.free;
  }

  void _openHistory(String uid) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => HistoryScreen(
        members: _members,
        initialUid: uid,
        historyDaysFor: (uid) =>
            uid == Backend.uid ? Plan.premium.historyDays : _planWith(uid).historyDays,
      ),
    ));
  }

  void _openMember(Member m) {
    if (m.position != null) _map.moveTo(m.position!, zoom: 16);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => _MemberSheet(
        member: m,
        isMe: m.uid == Backend.uid,
        onHistory: () {
          Navigator.pop(ctx);
          _openHistory(m.uid);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConfig.appName),
        actions: [
          IconButton(
            tooltip: '이동경로',
            icon: const Icon(Icons.route),
            onPressed: () => _openHistory(Backend.uid),
          ),
          IconButton(
            tooltip: '그룹',
            icon: const Icon(Icons.groups),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => GroupsScreen(members: _members))),
          ),
          IconButton(
            tooltip: '설정',
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([_members, _places]),
        builder: (context, _) {
          final all = [if (_members.me != null) _members.me!, ..._members.others];
          final located = all.where((m) => m.position != null && m.sharing).toList();
          return Stack(
            children: [
              FamilyMap(
                controller: _map,
                onReady: () {
                  final me = _members.me?.position;
                  if (me != null) {
                    _centeredOnce = true;
                    _map.moveTo(me, zoom: 15);
                  }
                },
                circles: [
                  for (final p in _places.all)
                    MapCircle(
                      id: 'place-${p.groupId}-${p.id}',
                      center: p.position,
                      radius: p.radius,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                ],
                pins: [
                  for (final p in _places.all)
                    MapPin(
                      id: 'place-${p.groupId}-${p.id}',
                      position: p.position,
                      label: p.name,
                      emoji: p.emoji,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                  for (final m in located)
                    MapPin(
                      id: m.uid,
                      position: m.position!,
                      label: m.uid == Backend.uid ? '나' : m.displayName,
                      emoji: m.badge,
                      // 다른 가족은 위치가 언제 것인지 함께 보여준다
                      subLabel: m.uid == Backend.uid
                          ? null
                          : m.isOnline
                              ? m.updatedLabel
                              : '오프라인 · ${m.updatedLabel}',
                      color: m.uid == Backend.uid
                          ? Theme.of(context).colorScheme.tertiary
                          : m.isOnline
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey,
                      onTap: () => _openMember(m),
                    ),
                ],
              ),
              if (_groups.isEmpty) _EmptyGroupsBanner(members: _members),
              DraggableScrollableSheet(
                initialChildSize: 0.25,
                minChildSize: 0.12,
                maxChildSize: 0.7,
                builder: (context, scroll) => Material(
                  elevation: 8,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  child: ListView(
                    controller: scroll,
                    children: [
                      Center(
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 10),
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.outlineVariant,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      for (final m in all)
                        ListTile(
                          leading: MemberAvatar(member: m),
                          title: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  m.uid == Backend.uid ? '${m.displayName} (나)' : m.displayName,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              OnlineBadge(member: m),
                            ],
                          ),
                          subtitle: Text(m.statusText),
                          trailing: BatteryLabel(member: m),
                          onTap: () => _openMember(m),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 위치 공유를 시작한다. 권한이 없으면 명시적 고지 화면부터 보여준다.
Future<bool> ensureSharing(BuildContext context) async {
  if (await LocationService.instance.start()) return true;
  if (!context.mounted) return false;
  final granted = await DisclosureScreen.show(context);
  return granted && await LocationService.instance.start();
}

class _EmptyGroupsBanner extends StatelessWidget {
  const _EmptyGroupsBanner({required this.members});
  final MembersController members;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 16,
      right: 16,
      top: 16,
      child: Card(
        child: ListTile(
          leading: const Icon(Icons.group_add),
          title: const Text('아직 그룹이 없어요'),
          subtitle: const Text('그룹을 만들거나 초대코드로 참여해 위치를 공유하세요.'),
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => GroupsScreen(members: members))),
        ),
      ),
    );
  }
}

class _MemberSheet extends StatefulWidget {
  const _MemberSheet({required this.member, required this.isMe, required this.onHistory});
  final Member member;
  final bool isMe;
  final VoidCallback onHistory;

  @override
  State<_MemberSheet> createState() => _MemberSheetState();
}

class _MemberSheetState extends State<_MemberSheet> {
  bool _ringing = false;

  Future<void> _ring() async {
    setState(() => _ringing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await MessagingService.ring(widget.member.uid);
      messenger.showSnackBar(
          SnackBar(content: Text('${widget.member.displayName}님의 휴대폰 벨을 울렸어요 (최대 1분)')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(Backend.errorMessage(e))));
    } finally {
      if (mounted) setState(() => _ringing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.member;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: MemberAvatar(member: m, radius: 24),
              title: Row(
                children: [
                  Flexible(
                    child: Text(m.displayName,
                        style: Theme.of(context).textTheme.titleLarge, overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 8),
                  OnlineBadge(member: m),
                ],
              ),
              subtitle: Text(m.statusText),
              trailing: BatteryLabel(member: m),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (!widget.isMe)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _ringing ? null : _ring,
                      icon: const Icon(Icons.volume_up),
                      label: const Text('벨 울리기'),
                    ),
                  ),
                if (!widget.isMe) const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: widget.onHistory,
                    icon: const Icon(Icons.route),
                    label: const Text('이동경로'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// ● 온라인 / ○ 오프라인 표시
class OnlineBadge extends StatelessWidget {
  const OnlineBadge({super.key, required this.member});
  final Member member;

  @override
  Widget build(BuildContext context) {
    final online = member.isOnline && member.sharing;
    final color = online ? const Color(0xFF2E9E5B) : Theme.of(context).colorScheme.outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(online ? Icons.circle : Icons.circle_outlined, size: 8, color: color),
          const SizedBox(width: 4),
          Text(member.onlineLabel,
              style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class MemberAvatar extends StatelessWidget {
  const MemberAvatar({super.key, required this.member, this.radius = 20});
  final Member member;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final online = member.isOnline && member.sharing;
    final emoji = member.avatar != null;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: radius,
          backgroundColor: online ? scheme.primary : scheme.outline,
          child: CircleAvatar(
            radius: radius - 2.5,
            backgroundColor: emoji ? scheme.surface : (online ? scheme.primary : scheme.outline),
            foregroundColor: online ? scheme.onPrimary : scheme.surface,
            child: Text(member.badge, style: TextStyle(fontSize: emoji ? radius * 1.1 : null)),
          ),
        ),
        // 오른쪽 아래 온라인 점
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: radius * 0.55,
            height: radius * 0.55,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: online ? const Color(0xFF2E9E5B) : scheme.outline,
              border: Border.all(color: scheme.surface, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

class BatteryLabel extends StatelessWidget {
  const BatteryLabel({super.key, required this.member});
  final Member member;

  @override
  Widget build(BuildContext context) {
    final level = member.battery;
    if (level == null) return const SizedBox.shrink();
    final icon = member.charging
        ? Icons.battery_charging_full
        : level <= 15
            ? Icons.battery_alert
            : Icons.battery_std;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: level <= 15 && !member.charging ? Colors.red : null),
        Text('$level%'),
      ],
    );
  }
}
