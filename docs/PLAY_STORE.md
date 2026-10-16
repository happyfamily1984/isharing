# Google Play 출시 체크리스트

위치 공유 앱은 Play 심사에서 가장 까다로운 분야 중 하나입니다. 아래 항목을 모두 챙겨야 합니다.

## 1. 앱 정보
- [ ] 앱 이름/아이콘 확정. "iSharing" 은 이미 존재하는 앱 이름(상표)이라 사용하면 안 됩니다.
- [ ] 패키지명 확정 (현재 `com.happyfamily.familylocator`). **한 번 출시하면 바꿀 수 없음**
  - 바꾸려면: `app/android/app/build.gradle.kts` 의 `namespace`/`applicationId`, Kotlin 폴더 경로·`package` 줄,
    `functions` 쪽은 영향 없음, iOS `PRODUCT_BUNDLE_IDENTIFIER`
- [ ] `app/lib/config.dart` 의 `privacyPolicyUrl`, `accountDeletionUrl` 을 실제 페이지로 교체

## 2. 릴리스 서명
```bash
keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```
`app/android/key.properties` (git에 올리지 말 것, 이미 .gitignore 처리):
```
storePassword=...
keyPassword=...
keyAlias=upload
storeFile=/절대경로/upload-keystore.jks
```
빌드: `cd app && flutter build appbundle --release` → `build/app/outputs/bundle/release/app-release.aab` 업로드.
Play App Signing 사용 권장.

## 3. 위치 권한 정책 (가장 중요)
- [x] **앱 내 명시적 고지(Prominent Disclosure)**: 권한 요청 전에 `DisclosureScreen` 이 무엇을 수집하고
  누구와 공유하는지 보여주고 동의를 받음
- [x] 위치 공유 중 상시 알림 표시 (몰래 추적 앱 = 스토커웨어 정책 위반 방지)
- [x] 사용자가 언제든 공유 중지/그룹 탈퇴 가능, 앱 아이콘 숨김 없음
- [ ] Play Console > 앱 콘텐츠 > **위치 권한(백그라운드 위치) 선언서** 제출
  - 핵심 기능 설명: "가족/그룹 멤버 간 실시간 위치 공유 및 이동경로 확인"
  - **동영상 필수**: 고지 화면 → 권한 허용 → 앱을 닫아도 다른 기기 지도에 위치가 갱신되는 모습 (30초 내외, 유튜브 미등록 링크)
- [ ] 심사용 테스트 계정 2개와, 이미 같은 그룹에 묶어둔 상태를 "앱 액세스" 항목에 기재

## 4. 포그라운드 서비스 선언 (Android 14+)
Play Console > 앱 콘텐츠 > 포그라운드 서비스 권한에서 아래 두 가지를 선언 (각각 동영상 필요할 수 있음):
- `location` : 앱이 백그라운드일 때 그룹 멤버에게 위치 공유
- `mediaPlayback` : 그룹 멤버가 요청한 "휴대폰 찾기" 벨 재생 (사용자가 끌 수 있는 알림과 함께 최대 1분)

전체화면 인텐트(`USE_FULL_SCREEN_INTENT`)는 Android 14부터 알람/통화 앱만 쓸 수 있어 사용하지 않습니다.

## 5. 데이터 보안(Data safety) 양식
| 데이터 | 수집 | 공유 | 목적 | 비고 |
| --- | --- | --- | --- | --- |
| 정확한 위치 | 예 | 아니요* | 앱 기능 | *사용자가 고른 그룹 멤버에게 보이는 것은 "공유"가 아닌 앱 기능으로 분류 |
| 이메일 주소 | 예 | 아니요 | 계정 관리 | |
| 이름 | 예 | 아니요 | 앱 기능 | |
| 기기 ID(푸시 토큰) | 예 | 아니요 | 앱 기능 | 벨 울리기/알림 |
| 배터리 상태 | 예 | 아니요 | 앱 기능 | 기타 앱 활동으로 분류 |
- 전송 중 암호화: 예 (Firebase TLS)
- 데이터 삭제 요청: 예 (앱 내 회원 탈퇴 + 웹 페이지)

## 6. 계정 삭제
- [x] 앱 내 회원 탈퇴 (설정 > 회원 탈퇴 → 그룹 탈퇴 + 위치 기록 삭제 + 계정 삭제)
- [ ] 앱 밖 삭제 요청 웹 페이지 URL 을 Play Console 에 등록 (`accountDeletionUrl`)

## 7. 기타
- [ ] 콘텐츠 등급 설문, 타겟 연령: **만 13세 이상 권장**. 아동 대상(가족 정책)으로 등록하면 요구사항이 크게 늘어남
- [ ] 국내 서비스 시: **위치정보사업/위치기반서비스사업 신고** (위치정보법). 방송통신위원회 신고 대상인지 확인 필요
- [ ] 개인정보처리방침에 위치정보 수집 항목·보관기간(30일)·파기 방법 명시
- [ ] 신규 개인 개발자 계정은 출시 전 **비공개 테스트(테스터 12명 이상, 14일)** 필요
