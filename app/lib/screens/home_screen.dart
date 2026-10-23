import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
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
import '../services/together_service.dart';
import 'disclosure_screen.dart';
import 'profile_screen.dart';
import 'groups_screen.dart';
import 'history_screen.dart';
import 'settings_screen.dart';
import 'together_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _map = FamilyMapController();
  final _members = MembersController();
  final _places = PlacesController();
  List<Group> _groups = const [];
  StreamSubscription<List<Group>>? _groupsSub;
  StreamSubscription<String>? _ringSub;
  StreamSubscription<String>? _alertSub;
  Timer? _clock;
  bool _batteryOptimized = false;
  bool _batteryBannerClosed = false;
  StreamSubscription<Map<String, TogetherRecord>>? _togetherSub;
  Map<String, TogetherRecord> _together = const {};
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
    WidgetsBinding.instance.addObserver(this);
    _togetherSub = TogetherService.mine().listen(
      (t) => setState(() => _together = t),
      onError: (Object e) => debugPrint('함께한 시간 불러오기 실패: $e'),
    );
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
    WidgetsBinding.instance.removeObserver(this);
    _togetherSub?.cancel();
    _members.dispose();
    _places.dispose();
    super.dispose();
  }

  Future<void> _startup() async {
    // 알림 등록은 서버 응답이 늦거나 알림 허용 창에 답하지 않아도 위치 공유를 막지 않도록 따로 진행한다.
    unawaited(MessagingService.init()
        .timeout(const Duration(seconds: 30))
        .then((_) {}, onError: (Object e) => debugPrint('messaging init failed: $e')));

    // 내 정보: 인터넷이 불안정하면 기기에 저장된 값으로 진행한다.
    Map<String, dynamic>? data;
    final doc = Backend.userDoc(Backend.uid);
    try {
      data = (await doc.get().timeout(const Duration(seconds: 8))).data();
    } catch (e) {
      debugPrint('profile load failed, using cache: $e');
      try {
        data = (await doc.get(const GetOptions(source: Source.cache))).data();
      } catch (_) {}
    }
    if (!mounted) return;

    // 처음 한 번 이름과 지도에 보일 캐릭터를 정한다 (내 정보를 확인했을 때만).
    if (data != null &&
        (data['avatar'] == null || (data['nameConfirmed'] != true && !AuthService.usesPassword))) {
      await ProfileScreen.show(
        context,
        name: (data['displayName'] as String?) ?? '',
        avatar: data['avatar'] as String?,
        required: true,
      );
      if (!mounted) return;
    }

    // 사용자가 직접 끈 경우가 아니면 위치 공유를 시작한다.
    if ((data?['sharing'] as bool?) ?? true) {
      final started = await ensureSharing(context);
      if (started && mounted) await _checkPreciseLocation();
      if (started) await _checkBattery();
    }
  }

  /// 설정에서 GPS·권한을 켜고 돌아오면 바로 공유를 다시 시작한다.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final sharing = _members.me?.sharing ?? true;
    if (sharing) LocationService.instance.start();
    _checkBattery();
  }

  Future<void> _checkBattery() async {
    final optimized = await LocationService.isBatteryOptimized();
    if (mounted && optimized != _batteryOptimized) setState(() => _batteryOptimized = optimized);
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

  String _listSubtitle(Member m) {
    final today = _together[m.uid]?.on(DateTime.now()) ?? Duration.zero;
    if (m.uid == Backend.uid || today.inMinutes < 1) return m.statusText;
    return '${m.statusText}\n🤝 오늘 함께 ${formatDuration(today)}';
  }

  void _onMembersChanged() {
    if (!_centeredOnce && _members.me?.position != null) {
      _centeredOnce = true;
      _map.moveTo(_members.me!.position!, zoom: 15);
    }
  }

  void _onRing(String fromName) {
    if (!mounted) return;
    // 폰을 찾았다는 뜻이므로 화면 어디를 눌러도(창 밖, 창 안, 버튼) 벨을 끈다.
    showDialog<void>(
      context: context,
      builder: (ctx) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.pop(ctx),
        child: AlertDialog(
          icon: const Icon(Icons.notifications_active, size: 40),
          title: const Text('휴대폰 찾기'),
          content: Text(
            '${fromName.isEmpty ? '벨이 울리고 있어요' : '$fromName님이 벨을 울리고 있어요'}\n아무 곳이나 누르면 꺼져요',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('벨 끄기'),
            ),
          ],
        ),
      ),
    ).then((_) => MessagingService.stopRinging());
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
    if (m.position != null) _map.moveTo(m.position!, zoom: memberZoom);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => _MemberSheet(
        member: m,
        isMe: m.uid == Backend.uid,
        together: _together[m.uid],
        onHistory: () {
          Navigator.pop(ctx);
          _openHistory(m.uid);
        },
        onTogether: () {
          Navigator.pop(ctx);
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => TogetherScreen(member: m, places: _places),
          ));
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
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: Column(
                  children: [
                    if (_members.me?.sharing ?? true) const _SharingProblemBanner(),
                    if ((_members.me?.sharing ?? true) && _batteryOptimized && !_batteryBannerClosed)
                      _BatteryBanner(onClose: () => setState(() => _batteryBannerClosed = true)),
                    if (_groups.isEmpty) _EmptyGroupsBanner(members: _members),
                  ],
                ),
              ),
              // 오른쪽 아래: 가족 아이콘을 누르면 그 사람 위치로 이동
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, box) => Align(
                    alignment: Alignment.bottomRight,
                    child: Padding(
                      // 아래 가족 목록(화면의 25%) 바로 위에 놓는다
                      padding: EdgeInsets.only(right: 12, bottom: box.maxHeight * 0.25 + 12),
                      child: _MemberJumpBar(
                        members: located,
                        onMember: (m) => _map.moveTo(m.position!, zoom: memberZoom),
                        onAll: () => _map.fit(located.map((m) => m.position!).toList()),
                      ),
                    ),
                  ),
                ),
              ),
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
                          subtitle: Text(_listSubtitle(m)),
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

/// 가족 위치로 이동할 때의 확대 수준: 주변 동네와 길이 함께 보이는 정도
const memberZoom = 15.0;

/// 지도 오른쪽 아래의 가족 아이콘 줄. 누르면 그 사람 위치로 지도를 옮긴다.
class _MemberJumpBar extends StatelessWidget {
  const _MemberJumpBar({required this.members, required this.onMember, required this.onAll});

  final List<Member> members;
  final void Function(Member) onMember;
  final VoidCallback onAll;

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 4,
      color: scheme.surface,
      borderRadius: BorderRadius.circular(28),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: ConstrainedBox(
          // 가족이 많으면 스크롤
          constraints: const BoxConstraints(maxHeight: 300),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (members.length > 1)
                  Tooltip(
                    message: '모두 보기',
                    child: IconButton(
                      onPressed: onAll,
                      icon: const Icon(Icons.groups),
                    ),
                  ),
                for (final m in members)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Tooltip(
                      message: m.uid == Backend.uid ? '나' : m.displayName,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => onMember(m),
                        child: MemberAvatar(member: m, radius: 21),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 위치 공유를 시작한다. 권한이 없으면 명시적 고지 화면부터 보여준다.
Future<bool> ensureSharing(BuildContext context) async {
  if (await LocationService.instance.start()) return true;
  // GPS 가 꺼진 경우는 권한 문제가 아니므로 홈 화면 경고에서 켜도록 안내한다.
  if (LocationService.instance.problem.value == SharingProblem.serviceOff) return false;
  if (!context.mounted) return false;
  final granted = await DisclosureScreen.show(context);
  return granted && await LocationService.instance.start();
}

/// 내 위치가 공유되지 않고 있을 때 원인과 해결 버튼을 보여준다.
class _SharingProblemBanner extends StatelessWidget {
  const _SharingProblemBanner();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SharingProblem>(
      valueListenable: LocationService.instance.problem,
      builder: (context, problem, _) {
        if (problem == SharingProblem.none) return const SizedBox.shrink();
        final (text, action, onPressed) = switch (problem) {
          SharingProblem.serviceOff => (
              '폰의 위치(GPS) 기능이 꺼져 있어서 가족에게 내 위치가 보이지 않아요.',
              '위치 켜기',
              () => Geolocator.openLocationSettings(),
            ),
          SharingProblem.permissionDenied => (
              '위치 권한이 없어서 가족에게 내 위치가 보이지 않아요.',
              '권한 허용',
              () => ensureSharing(context),
            ),
          SharingProblem.permissionDeniedForever => (
              '위치 권한이 꺼져 있어요. 설정 > 권한 > 위치에서 "항상 허용"을 선택해주세요.',
              '설정 열기',
              () => Geolocator.openAppSettings(),
            ),
          SharingProblem.none => ('', '', () async => false),
        };
        final scheme = Theme.of(context).colorScheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Card(
            color: scheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  Icon(Icons.location_disabled, color: scheme.onErrorContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(text, style: TextStyle(color: scheme.onErrorContainer)),
                  ),
                  TextButton(onPressed: onPressed, child: Text(action)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 배터리 최적화 대상이면 화면이 꺼진 뒤 위치 공유가 끊길 수 있어 안내한다.
class _BatteryBanner extends StatelessWidget {
  const _BatteryBanner({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Card(
        color: scheme.tertiaryContainer,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Row(
            children: [
              Icon(Icons.battery_alert, color: scheme.onTertiaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '절전 설정 때문에 화면이 꺼지면 위치 공유가 멈출 수 있어요.\n'
                  '앱 설정 > 배터리에서 "제한 없음"을 선택해주세요.',
                  style: TextStyle(color: scheme.onTertiaryContainer),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () => Geolocator.openAppSettings(),
                    child: const Text('설정 열기'),
                  ),
                  TextButton(onPressed: onClose, child: const Text('닫기')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyGroupsBanner extends StatelessWidget {
  const _EmptyGroupsBanner({required this.members});
  final MembersController members;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
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
  const _MemberSheet({
    required this.member,
    required this.isMe,
    required this.onHistory,
    required this.onTogether,
    this.together,
  });
  final Member member;
  final bool isMe;
  final VoidCallback onHistory;
  final VoidCallback onTogether;
  final TogetherRecord? together;

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
            if (!widget.isMe)
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: const Text('🤝', style: TextStyle(fontSize: 26)),
                  title: Text(
                      '오늘 함께한 시간 ${formatDuration(widget.together?.on(DateTime.now()) ?? Duration.zero)}'),
                  subtitle: Text(
                      '최근 7일 ${formatDuration(widget.together?.lastDays(7) ?? Duration.zero)} · 언제 어디서 함께했는지 보기'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: widget.onTogether,
                ),
              )
            else
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
