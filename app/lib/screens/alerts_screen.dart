import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/alert_service.dart';
import '../widgets/ui.dart';

/// 장소 도착 · 거리 · 벨 알림 기록 (최근 30일).
class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  late final Stream<List<AppAlert>> _alerts = AlertService.recent();

  @override
  void initState() {
    super.initState();
    AlertService.markSeen();
  }

  static IconData _icon(String type) => switch (type) {
        'place' => Icons.place,
        'distance' => Icons.social_distance,
        'ring' => Icons.notifications_active,
        _ => Icons.notifications,
      };

  static String _day(DateTime t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = today.difference(DateTime(t.year, t.month, t.day)).inDays;
    if (days == 0) return '오늘';
    if (days == 1) return '어제';
    return DateFormat('M월 d일 (E)', 'ko').format(t);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const PillAppBar(title: '알림'),
      body: StreamBuilder<List<AppAlert>>(
        stream: _alerts,
        builder: (context, snap) {
          final alerts = snap.data ?? const <AppAlert>[];
          if (snap.connectionState == ConnectionState.waiting && alerts.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (alerts.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  '아직 알림이 없어요.\n가족이 장소에 도착하거나 멀어지면 여기에 모여요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.sub, fontSize: 16, height: 1.5),
                ),
              ),
            );
          }
          final children = <Widget>[];
          String? lastDay;
          for (final a in alerts) {
            final t = a.createdAt ?? DateTime.now();
            final day = _day(t);
            if (day != lastDay) {
              children.add(SectionLabel(day));
              lastDay = day;
            }
            children.add(SoftCard(
              margin: const EdgeInsets.only(bottom: 12),
              padding: EdgeInsets.zero,
              child: FeatureRow(
                leading: IconBubble(_icon(a.type), size: 48),
                title: a.body.isEmpty ? a.title : a.body,
                subtitle: '${a.title} · ${DateFormat('a h:mm', 'ko').format(t)}',
              ),
            ));
          }
          return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: children);
        },
      ),
    );
  }
}
