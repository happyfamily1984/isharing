import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'config.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'widgets/ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // android/app/google-services.json, ios/Runner/GoogleService-Info.plist 로 초기화
  await Firebase.initializeApp();
  await initializeDateFormatting('ko');
  if (AppConfig.naverMapClientId.isNotEmpty) {
    await FlutterNaverMap().init(
      clientId: AppConfig.naverMapClientId,
      onAuthFailed: (e) => debugPrint('네이버 지도 인증 실패: $e'),
    );
  }
  runApp(const FamilyLocatorApp());
}

class FamilyLocatorApp extends StatelessWidget {
  const FamilyLocatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      // 디자인 시안은 밝은 화면 하나라 다크 모드에서도 같은 화면을 쓴다.
      theme: buildAppTheme(),
      themeMode: ThemeMode.light,
      // 폰의 글자 크기 설정이 커도 메뉴가 지도를 가리지 않도록 확대를 제한한다.
      builder: (context, child) =>
          MediaQuery.withClampedTextScaling(maxScaleFactor: 1.1, child: child!),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          return snap.data == null
              ? const LoginScreen()
              : HomeScreen(key: ValueKey(snap.data!.uid));
        },
      ),
    );
  }
}
