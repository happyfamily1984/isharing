import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Firebase 접근 지점 모음. Cloud Functions 리전은 functions/src/index.ts 와 같아야 한다.
class Backend {
  Backend._();

  static FirebaseAuth get auth => FirebaseAuth.instance;
  static FirebaseFirestore get db => FirebaseFirestore.instance;
  static FirebaseFunctions get functions =>
      FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  static String get uid => auth.currentUser!.uid;

  static DocumentReference<Map<String, dynamic>> userDoc(String uid) =>
      db.collection('users').doc(uid);

  static Future<Map<String, dynamic>> call(String name, [Map<String, dynamic>? data]) async {
    final result = await functions.httpsCallable(name).call<Map<String, dynamic>>(data);
    return Map<String, dynamic>.from(result.data);
  }

  /// 함수/인증 오류를 사용자에게 보여줄 문장으로 바꾼다.
  static String errorMessage(Object e) {
    if (e is FirebaseFunctionsException) return e.message ?? '요청을 처리하지 못했습니다.';
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'invalid-email':
          return '이메일 형식이 올바르지 않습니다.';
        case 'email-already-in-use':
          return '이미 가입된 이메일입니다.';
        case 'weak-password':
          return '비밀번호는 6자 이상이어야 합니다.';
        case 'invalid-credential':
        case 'wrong-password':
        case 'user-not-found':
          return '이메일 또는 비밀번호가 올바르지 않습니다.';
        default:
          return e.message ?? '인증 오류가 발생했습니다.';
      }
    }
    return '오류가 발생했습니다: $e';
  }
}
