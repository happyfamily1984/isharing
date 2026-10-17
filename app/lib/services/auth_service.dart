import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'backend.dart';
import 'location_service.dart';
import 'messaging_service.dart';

class AuthService {
  AuthService._();

  static bool _googleReady = false;

  static Future<GoogleSignIn> _google() async {
    if (!_googleReady) {
      // Android: google-services.json 의 웹 OAuth 클라이언트를 자동으로 사용한다.
      await GoogleSignIn.instance.initialize();
      _googleReady = true;
    }
    return GoogleSignIn.instance;
  }

  static Future<void> signUp(String email, String password, String name) async {
    final cred = await Backend.auth
        .createUserWithEmailAndPassword(email: email, password: password);
    await cred.user!.updateDisplayName(name);
    await _createProfile(cred.user!.uid, name, nameConfirmed: true);
  }

  static Future<void> signIn(String email, String password) =>
      Backend.auth.signInWithEmailAndPassword(email: email, password: password);

  /// 구글 계정으로 로그인. 처음이면 프로필을 만든다.
  static Future<void> signInWithGoogle() async {
    final account = await (await _google()).authenticate();
    final cred = await Backend.auth.signInWithCredential(
      GoogleAuthProvider.credential(idToken: account.authentication.idToken),
    );
    final user = cred.user!;
    final profile = await Backend.userDoc(user.uid).get();
    if (!profile.exists || profile.data()?['displayName'] == null) {
      // 구글 이름은 첫 화면(ProfileScreen)에서 확인·수정받는다.
      await _createProfile(user.uid, account.displayName ?? user.displayName ?? '',
          nameConfirmed: false);
    }
  }

  static Future<void> _createProfile(String uid, String name, {required bool nameConfirmed}) =>
      Backend.userDoc(uid).set({
        'displayName': name,
        'nameConfirmed': nameConfirmed,
        'sharing': true,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  /// 그룹 멤버에게 보일 이름과 이모지를 저장한다.
  ///
  /// 신호가 약해도 멈추거나 실패하지 않게 서버 응답을 기다리지 않는다.
  /// Firestore 는 기기에 먼저 저장해 화면에 바로 반영하고, 연결되면 알아서 서버에 올린다.
  static void setProfile({required String name, required String avatar}) {
    final user = Backend.auth.currentUser!;
    unawaited(Backend.userDoc(user.uid).set(
      {'displayName': name, 'avatar': avatar, 'nameConfirmed': true},
      SetOptions(merge: true),
    ).then((_) {}, onError: (Object e) => debugPrint('프로필 저장 실패: $e')));
    // 로그인 계정의 표시 이름은 부가 정보(앱은 Firestore 이름을 씀)라 실패해도 무시한다.
    unawaited(user
        .updateDisplayName(name)
        .then((_) {}, onError: (Object e) => debugPrint('계정 이름 변경 실패: $e')));
  }

  static Future<void> resetPassword(String email) =>
      Backend.auth.sendPasswordResetEmail(email: email);

  /// 이메일/비밀번호로 가입한 계정인지 (탈퇴 시 비밀번호 확인 여부 결정)
  static bool get usesPassword =>
      Backend.auth.currentUser?.providerData.any((p) => p.providerId == 'password') ?? false;

  static Future<void> signOut() async {
    await LocationService.instance.stop();
    await MessagingService.clearToken();
    if (_googleReady) await GoogleSignIn.instance.signOut();
    await Backend.auth.signOut();
  }

  /// 회원 탈퇴. 본인 확인 후 서버에서 그룹 탈퇴 + 위치기록 삭제, 마지막으로 계정을 삭제한다.
  /// 이메일 계정은 [password], 구글 계정은 구글 재로그인으로 확인한다.
  static Future<void> deleteAccount({String? password}) async {
    final user = Backend.auth.currentUser!;
    if (usesPassword) {
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: user.email!, password: password ?? ''),
      );
    } else {
      final account = await (await _google()).authenticate();
      await user.reauthenticateWithCredential(
        GoogleAuthProvider.credential(idToken: account.authentication.idToken),
      );
    }
    await LocationService.instance.stop();
    await MessagingService.clearToken();
    await Backend.call('deleteMyData');
    await user.delete();
    if (_googleReady) await GoogleSignIn.instance.disconnect();
  }
}
