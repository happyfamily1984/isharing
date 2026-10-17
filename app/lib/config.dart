/// 출시 전에 실제 값으로 바꿔야 하는 설정.
class AppConfig {
  AppConfig._();

  static const appName = '패밀리 위치';

  /// Play Console 에 등록할 개인정보처리방침 URL (필수).
  static const privacyPolicyUrl = 'https://example.com/privacy';

  /// Play 정책상 앱 밖에서도 계정 삭제를 요청할 수 있는 웹 페이지가 필요하다.
  static const accountDeletionUrl = 'https://example.com/delete-account';

  /// 네이버 클라우드 플랫폼 Maps 의 Client ID. 빌드할 때
  /// `--dart-define=NAVER_MAP_CLIENT_ID=...` 로 넣는다 (GitHub Actions 는 Secret 에서 자동으로 넣음).
  static const naverMapClientId = String.fromEnvironment('NAVER_MAP_CLIENT_ID');
}
