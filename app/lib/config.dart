/// 출시 전에 실제 값으로 바꿔야 하는 설정.
class AppConfig {
  AppConfig._();

  static const appName = '패밀리 위치';

  /// Play Console 에 등록할 개인정보처리방침 URL (필수).
  static const privacyPolicyUrl = 'https://example.com/privacy';

  /// Play 정책상 앱 밖에서도 계정 삭제를 요청할 수 있는 웹 페이지가 필요하다.
  static const accountDeletionUrl = 'https://example.com/delete-account';

  /// 지도 타일: OpenStreetMap 데이터에 CARTO 의 차분한 스타일을 입힌 것.
  /// 무료 사용 한도(월 7만5천 지도 조회)를 넘으면 유료 플랜 또는 네이버/카카오 지도로 교체해야 한다.
  /// https://carto.com/basemaps
  static const tileUrlLight =
      'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png';
  static const tileUrlDark = 'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';
  static const tileUserAgent = 'com.happyfamily.familylocator';
}
