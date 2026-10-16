import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/member.dart';
import 'backend.dart';

class GroupService {
  GroupService._();

  static Stream<List<Group>> myGroups() => Backend.db
      .collection('groups')
      .where('members', arrayContains: Backend.uid)
      .snapshots()
      .map((s) => s.docs.map(Group.fromDoc).toList());

  static Stream<List<JoinRequest>> requests(String groupId) => Backend.db
      .collection('groups')
      .doc(groupId)
      .collection('requests')
      .snapshots()
      .map((s) => s.docs
          .map((d) => JoinRequest(d.id, (d.data()['displayName'] as String?) ?? '이름 없음'))
          .toList());

  static Future<String> create(String name) async =>
      (await Backend.call('createGroup', {'name': name}))['inviteCode'] as String;

  /// 가입 요청을 보내고 그룹 이름을 돌려준다. 방장 승인 후 멤버가 된다.
  static Future<String> requestJoin(String code) async =>
      (await Backend.call('requestJoin', {'code': code}))['groupName'] as String;

  static Future<void> respond(String groupId, String uid, {required bool approve}) =>
      Backend.call('respondJoin', {'groupId': groupId, 'uid': uid, 'approve': approve});

  static Future<void> regenerateInvite(String groupId) =>
      Backend.call('regenerateInvite', {'groupId': groupId});

  static Future<void> leave(String groupId) => Backend.call('leaveGroup', {'groupId': groupId});

  static Future<void> remove(String groupId, String uid) =>
      Backend.call('removeMember', {'groupId': groupId, 'uid': uid});
}

class JoinRequest {
  JoinRequest(this.uid, this.displayName);
  final String uid;
  final String displayName;
}

/// 나와 같은 그룹에 있는 모든 멤버(나 포함)의 실시간 위치를 구독한다.
/// users/{me}.viewers 는 서버가 관리하는 "같은 그룹 멤버" 목록이다.
class MembersController extends ChangeNotifier {
  MembersController() {
    _meSub = Backend.userDoc(Backend.uid).snapshots().listen(_onMe);
  }

  final Map<String, Member> members = {};
  final Map<String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>> _subs = {};
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _meSub;

  Member? get me => members[Backend.uid];
  List<Member> get others =>
      members.values.where((m) => m.uid != Backend.uid).toList()
        ..sort((a, b) => a.displayName.compareTo(b.displayName));

  void _onMe(DocumentSnapshot<Map<String, dynamic>> doc) {
    members[doc.id] = Member.fromDoc(doc);
    final viewers = Set<String>.from(doc.data()?['viewers'] as List? ?? const []);
    for (final uid in _subs.keys.toList()) {
      if (!viewers.contains(uid)) {
        _subs.remove(uid)?.cancel();
        members.remove(uid);
      }
    }
    for (final uid in viewers) {
      _subs.putIfAbsent(
        uid,
        () => Backend.userDoc(uid).snapshots().listen(
          (d) {
            if (d.exists) {
              members[uid] = Member.fromDoc(d);
              notifyListeners();
            }
          },
          // 그룹에서 빠져 권한이 사라진 직후에는 permission-denied 가 올 수 있다.
          onError: (Object _) {
            members.remove(uid);
            notifyListeners();
          },
        ),
      );
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _meSub?.cancel();
    for (final s in _subs.values) {
      s.cancel();
    }
    super.dispose();
  }
}

class HistoryService {
  HistoryService._();

  static Future<List<LocationPoint>> load(String uid, DateTime from, DateTime to) async {
    final snap = await Backend.userDoc(uid)
        .collection('locations')
        .where('ts', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
        .where('ts', isLessThan: Timestamp.fromDate(to))
        .orderBy('ts')
        .limit(2000)
        .get();
    return snap.docs.map(LocationPoint.fromDoc).toList();
  }
}
