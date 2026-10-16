import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'backend.dart';
import 'location_service.dart';
import 'messaging_service.dart';

class AuthService {
  AuthService._();

  static Future<void> signUp(String email, String password, String name) async {
    final cred = await Backend.auth
        .createUserWithEmailAndPassword(email: email, password: password);
    await cred.user!.updateDisplayName(name);
    await Backend.userDoc(cred.user!.uid).set({
      'displayName': name,
      'sharing': true,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> signIn(String email, String password) =>
      Backend.auth.signInWithEmailAndPassword(email: email, password: password);

  static Future<void> resetPassword(String email) =>
      Backend.auth.sendPasswordResetEmail(email: email);

  static Future<void> signOut() async {
    await LocationService.instance.stop();
    await MessagingService.clearToken();
    await Backend.auth.signOut();
  }

  /// 회원 탈퇴. 서버에서 그룹 탈퇴 + 위치기록 삭제 후 계정을 삭제한다.
  static Future<void> deleteAccount(String password) async {
    final user = Backend.auth.currentUser!;
    await user.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: user.email!, password: password),
    );
    await LocationService.instance.stop();
    await Backend.call('deleteMyData');
    await user.delete();
  }
}
