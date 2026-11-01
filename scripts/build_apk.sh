#!/usr/bin/env bash
# 테스트용 APK 빌드 (GitHub Actions 없이, Claude 작업 환경이나 PC 에서 실행).
#
# 필요한 환경변수 (GitHub Secret 과 같은 값):
#   GOOGLE_SERVICES_JSON : Firebase 에서 받은 google-services.json 파일 내용 전체
#   NAVER_MAP_CLIENT_ID  : 네이버 클라우드 플랫폼 Maps 의 Client ID
# 필요한 도구: flutter, Android SDK (ANDROID_HOME), JDK 17 이상
#
# 결과: app/build/app/outputs/flutter-apk/app-release.apk
set -euo pipefail
cd "$(dirname "$0")/../app"

if [ -z "${GOOGLE_SERVICES_JSON:-}" ]; then
  echo "GOOGLE_SERVICES_JSON 환경변수가 없습니다." >&2
  exit 1
fi
printf '%s' "$GOOGLE_SERVICES_JSON" > android/app/google-services.json

flutter pub get
flutter analyze
flutter test
# 빌드 번호는 설치할 때 "업데이트"로 인식되도록 시각(분 단위)으로 늘린다.
flutter build apk --release \
  --build-number="$(( $(date +%s) / 60 ))" \
  --dart-define=NAVER_MAP_CLIENT_ID="${NAVER_MAP_CLIENT_ID:-}"

ls -la build/app/outputs/flutter-apk/app-release.apk
