import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'config.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';

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
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
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
