# 패밀리 위치 (가칭)

가족·친구가 서로의 위치를 실시간으로 확인하고, 시간대별 이동경로를 보고,
분실한 휴대폰의 벨을 무음 모드에서도 울릴 수 있는 위치 공유 앱입니다.

| 기능 | 구현 방식 |
| --- | --- |
| 실시간 위치 공유 | `geolocator` 포그라운드 서비스(Android)/백그라운드 위치(iOS) → Firestore `users/{uid}.lastLocation` |
| 시간대별 이동경로 | 50m 이상 이동할 때마다 `users/{uid}/locations` 에 기록 → 날짜 + 시간대 슬라이더로 지도에 경로 표시 |
| 벨 울리기 (무음 무시) | Cloud Function → FCM 고우선순위 메시지 → **네이티브** `RingReceiver`/`RingService`가 알람 스트림을 최대 볼륨으로 1분간 재생 |
| 전원 꺼짐 시 마지막 위치 | 서버에 항상 최신 위치가 남고, 20분 이상 갱신이 없으면 "전원 꺼짐/연결 끊김 · 마지막 위치 N분 전"으로 표시. 배터리 5% 이하가 되면 마지막 위치를 한 번 더 올림 |

## 구조

```
app/              Flutter 앱 (Android, iOS)
  lib/
    main.dart               로그인 상태에 따라 화면 전환
    config.dart             출시 전 바꿔야 할 값 (개인정보처리방침 URL 등)
    models/member.dart      Member / LocationPoint / Group
    services/               위치 수집, 그룹, 푸시(벨), 인증, 요금제
    screens/                로그인, 위치 고지, 지도 홈, 이동경로, 그룹, 설정
  android/app/src/main/kotlin/.../
    RingReceiver.kt         FCM 'ring' 메시지 수신 (앱이 꺼져 있어도 동작)
    RingService.kt          알람 스트림 재생 + "벨 끄기" 알림
functions/        Cloud Functions (TypeScript) - 그룹/초대/승인/벨/데이터 정리
firestore.rules   보안 규칙 - 같은 그룹 멤버만 위치 열람 가능
rules-test/       보안 규칙 테스트 (Firestore 에뮬레이터)
docs/PLAY_STORE.md  Play 스토어 출시 체크리스트
```

## 위치를 볼 사람 등록 방식 (그룹 + 초대코드 + 방장 승인)

1. 한 사람이 **그룹 만들기** → 6자리 초대코드 발급 (48시간 유효, 언제든 재발급 가능)
2. 가족에게 초대코드를 카카오톡 등으로 전달
3. 받은 사람이 **초대코드 입력** → 가입 *요청*
4. **방장이 승인**해야 멤버가 되고 서로 위치가 보임 (코드가 유출돼도 모르는 사람은 볼 수 없음)
5. 누구나 언제든 그룹 나가기 / 위치 공유 일시중지 / 회원 탈퇴 가능. 방장은 멤버 내보내기 가능

그룹 멤버십은 **Cloud Functions에서만** 바꿀 수 있습니다. 함수가 각 사용자의
`viewers`(같은 그룹 멤버 목록)를 다시 계산하고, 보안 규칙은 이 목록에 있는 사람만
위치·이동경로를 읽게 허용합니다. 클라이언트를 조작해도 남의 위치는 볼 수 없습니다
(`rules-test/` 에서 검증).

## 수익 모델 (준비만 되어 있음)

광고나 유료 앱(선결제) 대신 **무료 + 그룹 단위 프리미엄 구독**을 전제로 설계했습니다.
가족 모두가 설치해야 하는 앱이라 선결제는 설치를 가로막고, 광고 SDK는 위치 데이터를
다루는 앱의 신뢰도와 Play 데이터 보안 신고에 불리합니다.

- `groups/{id}.plan` = `free` | `premium` (서버만 변경 가능)
- 무료: 멤버 6명, 이동경로 2일 조회 / 프리미엄: 멤버 20명, 이동경로 30일 조회
- 값은 `functions/src/index.ts` 의 `PLAN_LIMITS` 와 `app/lib/services/plan.dart` 에서 함께 관리
- 결제 연동 시: `in_app_purchase` 로 구독 → 영수증을 서버 함수에서 Google Play Developer API로 검증 → 해당 그룹 `plan` 을 `premium` 으로 변경

## 개발 환경 설정

필요한 것: Flutter (stable), Node 22, Firebase CLI (`npm i -g firebase-tools`), Android Studio / Xcode

1. [Firebase 콘솔](https://console.firebase.google.com)에서 프로젝트 생성
   - **Authentication** → 이메일/비밀번호 사용 설정
   - **Firestore** 생성 (리전: `asia-northeast3` 서울 권장)
   - **Blaze 요금제** (Cloud Functions에 필요)
2. Android 앱 등록 (패키지: `com.happyfamily.familylocator`) → `google-services.json` 을 `app/android/app/` 에 저장
3. iOS 앱 등록 (번들 ID: `com.happyfamily.familylocator`) → `GoogleService-Info.plist` 를 Xcode에서 `Runner` 에 추가
   - APNs 인증 키(.p8)를 Firebase 프로젝트 설정 > 클라우드 메시징에 업로드
   - Xcode > Signing & Capabilities: **Push Notifications**, **Background Modes**(Location updates, Remote notifications) 추가
4. 서버 배포
   ```bash
   firebase login
   firebase use --add            # 만든 프로젝트 선택
   cd functions && npm install && cd ..
   firebase deploy --only firestore,functions
   ```
5. 앱 실행
   ```bash
   cd app && flutter pub get && flutter run
   ```

### 보안 규칙 테스트

```bash
cd rules-test && npm install && npm test
```

## 플랫폼별 제약 (중요)

- **iOS에서 무음 모드 벨 울리기**: Apple이 일반 앱에는 허용하지 않습니다. 서버는 이미
  Critical Alert 형식으로 보내도록 되어 있지만, Apple에
  [Critical Alerts 권한](https://developer.apple.com/contact/request/notifications-critical-alerts-entitlement/)을
  신청해 승인받고 `com.apple.developer.usernotifications.critical-alerts` entitlement를 추가해야 동작합니다.
  승인 전에는 iOS에서 일반 알림음(무음 모드에선 진동)으로만 울립니다.
- **Android 방해금지 모드**: 알람 스트림을 쓰므로 대부분의 기기에서 무음/진동 모드여도 울리지만,
  사용자가 방해금지 모드에서 "알람"까지 막아두면 울리지 않을 수 있습니다.
- **휴대폰 재시작 후**: Android에서 재부팅하면 앱을 한 번 열어야 위치 공유가 다시 시작됩니다.
  (부팅 시 자동 시작은 추후 과제)
- **지도 타일**: 지금은 OpenStreetMap 공개 타일을 씁니다. 사용자가 늘면 OSM 정책상 상용 타일
  제공자(MapTiler, Stadia, 네이버/카카오 지도 등)로 바꿔야 합니다 → `app/lib/config.dart`.
