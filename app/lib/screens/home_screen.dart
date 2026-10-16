import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../config.dart';
import '../models/member.dart';
import '../widgets/map_tiles.dart';
import '../services/auth_service.dart';
import '../services/backend.dart';
import '../services/group_service.dart';
import '../services/location_service.dart';
import '../services/messaging_service.dart';
import '../services/plan.dart';
import 'disclosure_screen.dart';
import 'name_setup_screen.dart';
import 'groups_screen.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _map = MapController();
  final _members = MembersController();
  List<Group> _groups = const [];
  StreamSubscription<List<Group>>? _groupsSub;
  StreamSubscription<String>? _ringSub;
  bool _centeredOnce = false;

  @override
  void initState() {
    super.initState();
    _groupsSub = GroupService.myGroups().listen((g) => setState(() => _groups = g));
    _ringSub = MessagingService.incomingRings.listen(_onRing);
    _members.addListener(_onMembersChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startup());
  }

  @override
  void dispose() {
    _groupsSub?.cancel();
    _ringSub?.cancel();
    _members.dispose();
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
    // 구글로 가입한 사용자는 처음 한 번 이름을 정한다.
    if (data['nameConfirmed'] != true && !AuthService.usesPassword) {
      await NameSetupScreen.show(context, (data['displayName'] as String?) ?? '');
      if (!mounted) return;
    }
    if ((data['sharing'] as bool?) ?? true) await ensureSharing(context);
  }

  void _onMembersChanged() {
    if (!_centeredOnce && _members.me?.position != null) {
      _centeredOnce = true;
      _map.move(_members.me!.position!, 15);
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
    if (m.position != null) _map.move(m.position!, 16);
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
        listenable: _members,
        builder: (context, _) {
          final all = [if (_members.me != null) _members.me!, ..._members.others];
          final located = all.where((m) => m.position != null && m.sharing).toList();
          return Stack(
            children: [
              FlutterMap(
                mapController: _map,
                options: const MapOptions(
                  initialCenter: LatLng(37.5665, 126.9780), // 서울시청
                  initialZoom: 11,
                ),
                children: [
                  const AppTileLayer(),
                  MarkerLayer(
                    markers: [
                      for (final m in located)
                        Marker(
                          point: m.position!,
                          width: 120,
                          height: 72,
                          alignment: Alignment.topCenter,
                          child: GestureDetector(
                            onTap: () => _openMember(m),
                            child: MemberPin(member: m, isMe: m.uid == Backend.uid),
                          ),
                        ),
                    ],
                  ),
                  const AppMapAttribution(),
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
                          title: Text(m.uid == Backend.uid ? '${m.displayName} (나)' : m.displayName),
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
              title: Text(m.displayName, style: Theme.of(context).textTheme.titleLarge),
              subtitle: Text(m.statusText),
              trailing: BatteryLabel(member: m),
            ),
            if (m.accuracy != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text('정확도 약 ${m.accuracy!.round()}m',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
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

class MemberAvatar extends StatelessWidget {
  const MemberAvatar({super.key, required this.member, this.radius = 20});
  final Member member;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final online = member.isOnline && member.sharing;
    return CircleAvatar(
      radius: radius,
      backgroundColor: online ? scheme.primary : scheme.outline,
      foregroundColor: online ? scheme.onPrimary : scheme.surface,
      child: Text(member.displayName.characters.first),
    );
  }
}

class MemberPin extends StatelessWidget {
  const MemberPin({super.key, required this.member, required this.isMe});
  final Member member;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
          ),
          child: Text(
            member.isOnline ? member.displayName : '${member.displayName} · 마지막 위치',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
        ),
        const SizedBox(height: 2),
        DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: isMe ? scheme.tertiary : Colors.white, width: 3),
          ),
          child: MemberAvatar(member: member, radius: 18),
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
