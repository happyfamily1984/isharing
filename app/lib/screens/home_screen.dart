import 'dart:async';
import 'dart:math' as math;
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../config.dart';
import '../models/member.dart';
import '../widgets/family_map.dart';
import '../services/alert_service.dart';
import '../services/auth_service.dart';
import '../services/backend.dart';
import '../services/family_status.dart';
import '../services/group_service.dart';
import '../services/location_service.dart';
import '../services/messaging_service.dart';
import '../services/place_service.dart';
import '../services/plan.dart';
import '../services/together_service.dart';
import '../widgets/ui.dart';
import 'alerts_screen.dart';
import 'disclosure_screen.dart';
import 'profile_screen.dart';
import 'groups_screen.dart';
import 'places_screen.dart';
import 'history_screen.dart';
import 'settings_screen.dart';
import 'together_screen.dart';
import '../services/avatars.dart';

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
  Timer? _live;
  bool _batteryOptimized = false;
  bool _batteryBannerClosed = false;
  StreamSubscription<Map<String, TogetherRecord>>? _togetherSub;
  Map<String, TogetherRecord> _together = const {};
  bool _centeredOnce = false;
  late final Stream<List<AppAlert>> _alertsStream = AlertService.recent(limit: 20);

  /// 아래 가족 목록이 화면에서 차지하는 비율 (끌어 올리면 커진다)
  double _sheetExtent = _sheetInitial;

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
    _startLive();
  }

  /// 앱을 보고 있는 동안 1분마다 가족 폰에 "위치를 빠르게 올려줘" 신호를 보낸다.
  void _startLive() {
    _live?.cancel();
    MessagingService.requestLive();
    _live = Timer.periodic(const Duration(seconds: 60), (_) => MessagingService.requestLive());
  }

  void _stopLive() {
    _live?.cancel();
    _live = null;
  }

  @override
  void dispose() {
    _groupsSub?.cancel();
    _ringSub?.cancel();
    _alertSub?.cancel();
    _clock?.cancel();
    _stopLive();
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
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) _stopLive();
    if (state != AppLifecycleState.resumed) return;
    _startLive();
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
      isScrollControlled: true,
      builder: (ctx) => _MemberSheet(
        member: m,
        placeLabel: nearPlaceLabel(m.position, _places.all),
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

  void _openGroups() => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => GroupsScreen(members: _members)));

  void _openSettings() =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));

  void _openAlerts() =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AlertsScreen()));

  /// 더보기: 그룹 · 장소 · 설정
  void _openMore() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FeatureRow(
                leading: const IconBubble(Icons.groups, size: 38),
                title: '그룹',
                subtitle: '초대코드 · 가입 승인 · 멤버 관리',
                trailing: const Icon(Icons.chevron_right, color: AppColors.sub),
                onTap: () {
                  Navigator.pop(ctx);
                  _openGroups();
                },
              ),
              FeatureRow(
                leading: const IconBubble(Icons.place, size: 38),
                title: '장소 (집 · 회사 · 학교)',
                subtitle: '가족이 도착하면 서로에게 알림이 와요',
                trailing: const Icon(Icons.chevron_right, color: AppColors.sub),
                onTap: () {
                  Navigator.pop(ctx);
                  // 그룹이 하나면 바로 그 그룹의 장소로, 여러 개면 그룹 화면에서 고른다.
                  if (_groups.length == 1) {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => PlacesScreen(group: _groups.first, myPosition: _members.me?.position),
                    ));
                  } else {
                    _openGroups();
                  }
                },
              ),
              FeatureRow(
                leading: const IconBubble(Icons.settings, size: 38),
                title: '설정',
                subtitle: '위치 공유 · 알림 · 프로필',
                trailing: const Icon(Icons.chevron_right, color: AppColors.sub),
                onTap: () {
                  Navigator.pop(ctx);
                  _openSettings();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: StreamBuilder<List<AppAlert>>(
        stream: _alertsStream,
        builder: (context, snap) => ListenableBuilder(
          listenable: _members,
          builder: (context, _) {
            final seen = _members.me?.alertsSeenAt;
            final unread = (snap.data ?? const <AppAlert>[])
                .where((a) => a.createdAt != null && (seen == null || a.createdAt!.isAfter(seen)))
                .length;
            return AppBottomNav(
              unreadAlerts: unread,
              onHistory: () => _openHistory(Backend.uid),
              onAlerts: _openAlerts,
              onMore: _openMore,
            );
          },
        ),
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
                      color: AppColors.place,
                    ),
                ],
                pins: [
                  for (final p in _places.all)
                    MapPin(
                      id: 'place-${p.groupId}-${p.id}',
                      position: p.position,
                      label: p.name,
                      emoji: p.emoji,
                      color: AppColors.place,
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
                          ? AppColors.me
                          : m.isOnline
                              ? AppColors.primary
                              : AppColors.offline,
                      onTap: () => _openMember(m),
                    ),
                ],
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      PillBar(
                        leading: const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: AppLogo(size: 32),
                        ),
                        title: AppConfig.appName,
                        actions: [
                          IconButton(
                            tooltip: '이동경로',
                            icon: const Icon(Icons.route, size: 23),
                            onPressed: () => _openHistory(Backend.uid),
                          ),
                          IconButton(
                            tooltip: '그룹',
                            icon: const Icon(Icons.groups, size: 23),
                            onPressed: _openGroups,
                          ),
                          IconButton(
                            tooltip: '설정',
                            icon: const Icon(Icons.settings, size: 23),
                            onPressed: _openSettings,
                          ),
                        ],
                      ),
                      if (_members.me?.sharing ?? true) const _SharingProblemBanner(),
                      if ((_members.me?.sharing ?? true) && _batteryOptimized && !_batteryBannerClosed)
                        _BatteryBanner(onClose: () => setState(() => _batteryBannerClosed = true)),
                      if (_groups.isEmpty) _EmptyGroupsBanner(onTap: _openGroups),
                    ],
                  ),
                ),
              ),
              // 오른쪽 아래: 가족 아이콘을 누르면 그 사람 위치로 이동
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, box) {
                    // 지도에서 가족 목록에 가려진 부분: 이동·모두 보기는 보이는 부분 가운데로 맞춘다
                    final cover = box.maxHeight * _sheetExtent;
                    _map
                      ..bottomCover = cover
                      ..viewHeight = box.maxHeight;
                    // 가족 목록을 끌어 올려도 아이콘 줄이 그 바로 위에 보이게 한다 (공간이 좁으면 스크롤)
                    final space = box.maxHeight - cover - 24 - 120;
                    if (space < 64) return const SizedBox.shrink();
                    return Align(
                      alignment: Alignment.bottomRight,
                      child: Padding(
                        padding: EdgeInsets.only(right: 10, bottom: cover + 10),
                        child: _MemberJumpBar(
                          members: located,
                          maxHeight: math.min(280, space),
                          onMember: (m) => _map.moveTo(m.position!, zoom: memberZoom),
                          onAll: () => _map.fit(located.map((m) => m.position!).toList()),
                        ),
                      ),
                    );
                  },
                ),
              ),
              NotificationListener<DraggableScrollableNotification>(
                onNotification: (n) {
                  if ((n.extent - _sheetExtent).abs() > 0.005) setState(() => _sheetExtent = n.extent);
                  return false;
                },
                child: DraggableScrollableSheet(
                  initialChildSize: _sheetInitial,
                  minChildSize: _sheetInitial,
                  maxChildSize: 0.7,
                  builder: (context, scroll) => DecoratedBox(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                      boxShadow: [BoxShadow(color: Color(0x1A000000), blurRadius: 20, offset: Offset(0, -4))],
                    ),
                    child: ListView(
                      controller: scroll,
                      padding: EdgeInsets.zero,
                      children: [
                        Center(
                          child: Container(
                            margin: const EdgeInsets.only(top: 8, bottom: 2),
                            width: 40,
                            height: 5,
                            decoration: BoxDecoration(
                              color: const Color(0xFFD2DBD9),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                        for (final (i, m) in all.indexed) ...[
                          if (i > 0) const InsetDivider(indent: 72),
                          MemberCard(
                            member: m,
                            isMe: m.uid == Backend.uid,
                            placeLabel: nearPlaceLabel(m.position, _places.all),
                            together: m.uid == Backend.uid
                                ? null
                                : _together[m.uid]?.on(DateTime.now()),
                            onTap: () => _openMember(m),
                          ),
                        ],
                        const SizedBox(height: 12),
                      ],
                    ),
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

/// 아래 가족 목록의 처음 높이 (화면 비율): 내 카드 하나가 보이는 정도
const _sheetInitial = 0.13;

/// 가족 위치로 이동할 때의 확대 수준: 주변 동네와 길이 함께 보이는 정도
const memberZoom = 15.0;

/// 앱 로고 (앱 아이콘 그림)
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.24),
        child: Image.asset('assets/images/app_icon.png', width: size, height: size),
      );
}

/// 아래 가족 목록의 한 사람 카드.
class MemberCard extends StatelessWidget {
  const MemberCard({
    super.key,
    required this.member,
    required this.isMe,
    this.placeLabel,
    this.together,
    this.onTap,
  });

  final Member member;
  final bool isMe;
  final String? placeLabel;
  final Duration? together;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final m = member;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 8, 8),
        child: Row(
          children: [
            MemberAvatar(member: m, radius: 23),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          isMe ? '${m.displayName} (나)' : m.displayName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OnlineBadge(member: m),
                    ],
                  ),
                  if (placeLabel != null) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.location_on, size: 14, color: AppColors.ink),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(placeLabel!,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink)),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.schedule, size: 12, color: AppColors.sub),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(m.freshnessText,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: AppColors.sub)),
                      ),
                    ],
                  ),
                  if (together != null && together!.inMinutes >= 1) ...[
                    const SizedBox(height: 2),
                    Text('🤝 오늘 함께 ${formatDuration(together!)}',
                        style: const TextStyle(fontSize: 12, color: AppColors.sub)),
                  ],
                ],
              ),
            ),
            BatteryLabel(member: m),
            const Icon(Icons.chevron_right, size: 22, color: AppColors.sub),
          ],
        ),
      ),
    );
  }
}

/// 화면 아래 메뉴: 위치 · 위치기록 · 알림 · 더보기.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.unreadAlerts,
    required this.onHistory,
    required this.onAlerts,
    required this.onMore,
  });

  final int unreadAlerts;
  final VoidCallback onHistory;
  final VoidCallback onAlerts;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, -2))],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 54,
          child: Row(
            children: [
              const _NavItem(icon: Icons.location_on, label: '위치', selected: true),
              _NavItem(icon: Icons.history, label: '위치기록', onTap: onHistory),
              _NavItem(icon: Icons.notifications_none, label: '알림', badge: unreadAlerts, onTap: onAlerts),
              _NavItem(icon: Icons.more_horiz, label: '더보기', onTap: onMore),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, this.selected = false, this.badge = 0, this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final int badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.ink;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Badge(
              isLabelVisible: badge > 0,
              backgroundColor: AppColors.danger,
              label: Text(badge > 9 ? '9+' : '$badge'),
              child: Icon(icon, size: 23, color: color),
            ),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(fontSize: 11.5, color: color, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
            const SizedBox(height: 3),
            Container(
              width: 28,
              height: 2.5,
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 지도 오른쪽 아래의 가족 아이콘 줄. 누르면 그 사람 위치로 지도를 옮긴다.
class _MemberJumpBar extends StatelessWidget {
  const _MemberJumpBar({
    required this.members,
    required this.onMember,
    required this.onAll,
    this.maxHeight = 300,
  });

  final List<Member> members;
  final void Function(Member) onMember;
  final VoidCallback onAll;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: AppColors.shadow,
      ),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: ConstrainedBox(
        // 가족이 많으면 스크롤
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (members.length > 1)
                Tooltip(
                  message: '모두 보기',
                  child: IconButton(
                    onPressed: onAll,
                    icon: const Icon(Icons.groups, size: 22, color: AppColors.ink),
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
                      child: MemberAvatar(member: m, radius: 20),
                    ),
                  ),
                ),
            ],
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

/// 지도 위 안내 카드 (위치 문제 · 절전 · 그룹 없음).
class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.icon, required this.text, required this.actions, this.color = AppColors.danger});

  final IconData icon;
  final String text;
  final List<Widget> actions;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      child: Row(
        children: [
          IconBubble(icon, size: 34, color: color, background: color.withValues(alpha: 0.1)),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: AppColors.ink, height: 1.35))),
          Column(mainAxisSize: MainAxisSize.min, children: actions),
        ],
      ),
    );
  }
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
        return _NoticeCard(
          icon: Icons.location_disabled,
          text: text,
          actions: [TextButton(onPressed: onPressed, child: Text(action))],
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
    return _NoticeCard(
      icon: Icons.battery_alert,
      color: const Color(0xFFE08A00),
      text: '절전 설정 때문에 화면이 꺼지면 위치 공유가 멈출 수 있어요.\n'
          '앱 설정 > 배터리에서 "제한 없음"을 선택해주세요.',
      actions: [
        TextButton(onPressed: () => Geolocator.openAppSettings(), child: const Text('설정 열기')),
        TextButton(onPressed: onClose, child: const Text('닫기')),
      ],
    );
  }
}

class _EmptyGroupsBanner extends StatelessWidget {
  const _EmptyGroupsBanner({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: const FeatureRow(
        leading: IconBubble(Icons.group_add, size: 38),
        title: '아직 그룹이 없어요',
        subtitle: '그룹을 만들거나 초대코드로 참여해 위치를 공유하세요.',
        trailing: Icon(Icons.chevron_right, color: AppColors.sub),
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
    this.placeLabel,
    this.together,
  });
  final Member member;
  final bool isMe;
  final VoidCallback onHistory;
  final VoidCallback onTogether;
  final String? placeLabel;
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
            MemberCard(member: m, isMe: widget.isMe, placeLabel: widget.placeLabel),
            const SizedBox(height: 8),
            if (!widget.isMe)
              SoftCard(
                padding: EdgeInsets.zero,
                onTap: widget.onTogether,
                child: FeatureRow(
                  leading: const EmojiBubble('🤝', size: 38),
                  title: '오늘 함께한 시간 ${formatDuration(widget.together?.on(DateTime.now()) ?? Duration.zero)}',
                  subtitle:
                      '최근 7일 ${formatDuration(widget.together?.lastDays(7) ?? Duration.zero)} · 언제 어디서 함께했는지 보기',
                  trailing: const Icon(Icons.chevron_right, color: AppColors.sub),
                ),
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

/// ● 온라인 / ○ 오프라인 표시
class OnlineBadge extends StatelessWidget {
  const OnlineBadge({super.key, required this.member});
  final Member member;

  @override
  Widget build(BuildContext context) {
    final online = member.isOnline && member.sharing;
    return TagChip(
      member.onlineLabel,
      dot: !online,
      color: online ? AppColors.online : AppColors.sub,
      background: online ? AppColors.onlineBg : const Color(0xFFEDF1F0),
    );
  }
}

/// 이모지 프로필: 흰 동그라미 + 청록 테두리 + 오른쪽 아래 온라인 점.
class MemberAvatar extends StatelessWidget {
  const MemberAvatar({super.key, required this.member, this.radius = 20});
  final Member member;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final online = member.isOnline && member.sharing;
    final emoji = member.avatar != null;
    final ring = online ? AppColors.primaryDark : AppColors.offline;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: radius * 2,
          height: radius * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: emoji ? Colors.white : ring,
            border: Border.all(color: ring, width: radius > 24 ? 4 : 3),
          ),
          alignment: Alignment.center,
          child: emoji
              ? ClipOval(child: AvatarGlyph(member.badge, size: radius * 1.7))
              : Text(member.badge,
                  style: TextStyle(fontSize: radius * 0.8, color: Colors.white, fontWeight: FontWeight.w700)),
        ),
        // 오른쪽 아래 온라인 점
        Positioned(
          right: radius * 0.02,
          bottom: radius * 0.02,
          child: Container(
            width: radius * 0.42,
            height: radius * 0.42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: online ? AppColors.online : AppColors.offline,
              border: Border.all(color: Colors.white, width: 2),
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
    final low = level <= 15 && !member.charging;
    final icon = member.charging
        ? Icons.battery_charging_full
        : low
            ? Icons.battery_alert
            : Icons.battery_std;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: low ? AppColors.danger : AppColors.sub),
        Text('$level%', style: TextStyle(fontSize: 12, color: low ? AppColors.danger : AppColors.sub)),
      ],
    );
  }
}
