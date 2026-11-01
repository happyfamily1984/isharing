#!/usr/bin/env bash
# 서버(Cloud Functions + Firestore 보안 규칙) 배포 (GitHub Actions 없이).
#
# 필요한 환경변수 (GitHub Secret 과 같은 값):
#   FIREBASE_SERVICE_ACCOUNT : 서비스 계정 키(JSON) 내용 전체
#   FIREBASE_PROJECT_ID      : Firebase 프로젝트 ID
# 필요한 도구: node 22, gcloud
set -euo pipefail
cd "$(dirname "$0")/.."

: "${FIREBASE_SERVICE_ACCOUNT:?FIREBASE_SERVICE_ACCOUNT 환경변수가 없습니다.}"
: "${FIREBASE_PROJECT_ID:?FIREBASE_PROJECT_ID 환경변수가 없습니다.}"

key="$(mktemp)"
trap 'rm -f "$key"' EXIT
printf '%s' "$FIREBASE_SERVICE_ACCOUNT" > "$key"
export GOOGLE_APPLICATION_CREDENTIALS="$key"

(cd functions && npm ci && npm test)

npx --yes firebase-tools@14 deploy \
  --only firestore,functions \
  --project "$FIREBASE_PROJECT_ID" \
  --non-interactive --force

# firebase deploy 는 호출형(onCall) 함수의 공개 호출 권한을 "처음 만들 때만" 설정하므로 매번 확실히 설정한다.
# 호출자 인증·권한 검사는 각 함수 코드가 한다.
gcloud auth activate-service-account --key-file="$key" --quiet
for fn in createGroup regenerateInvite requestJoin respondJoin leaveGroup removeMember deleteMyData ringDevice requestLive; do
  service=$(echo "$fn" | tr '[:upper:]' '[:lower:]')
  gcloud run services add-iam-policy-binding "$service" \
    --project "$FIREBASE_PROJECT_ID" --region asia-northeast3 \
    --member=allUsers --role=roles/run.invoker --quiet >/dev/null
  echo "✔ $fn"
done
