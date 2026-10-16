/// 출시 전에 실제 값으로 바꿔야 하는 설정.
class AppConfig {
  AppConfig._();

  static const appName = '패밀리 위치';

  /// Play Console 에 등록할 개인정보처리방침 URL (필수).
  static const privacyPolicyUrl = 'https://example.com/privacy';

  /// Play 정책상 앱 밖에서도 계정 삭제를 요청할 수 있는 웹 페이지가 필요하다.
  static const accountDeletionUrl = 'https://example.com/delete-account';

  /// OpenStreetMap 타일. 상용 트래픽이 많아지면 유료 타일 제공자로 교체해야 한다
  /// (OSM 타일 사용 정책: https://operations.osmfoundation.org/policies/tiles/).
  static const tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const tileUserAgent = 'com.happyfamily.familylocator';
}
