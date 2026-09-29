# HelloProtein 업데이트 실행 현황

2026-09-23 시작. iOS 기존 사용자 보존과 Android 신규 출시를 함께 준비한다.

디자인 참고: [디자이너 임시 와이어프레임 검토](figma-designer-wireframe-review.md). Figma `313:1951`의 날짜 탐색·다중 음식 추가·캘린더/그래프 전환을 반영한다. 이전 3탭 제안은 확정하지 않고 이 기존 안과 비교한다.

## 아키텍처 검토에 따른 선행 조건

사용자가 전체 구조에 대한 개발자 검토를 요청했다. 기능 구현을 더 확장하기 전에 다음 설계를 먼저 확정한다.

- 날짜가 있는 기록을 기준 데이터로 삼고, 합계는 기록과 명시적인 레거시 보정값에서 계산한다. UserDefaults에 별도 누적 합계를 유지하는 구조를 새 모델에 옮기지 않는다.
- 화면 표시, 기록/계산 규칙, 저장소·검색 공급자를 분리한다. 화면에서 Realm 쓰기/HTTP 요청/이관을 직접 수행하지 않는다.
- iOS·Android 공통 UI 기술 검증 전 기존 UIKit 전체를 MVVM 등으로 재작성하지 않는다. 이중 구현 비용을 피하도록 필요한 이관 경계와 사용자 흐름만 먼저 검증한다.
- `MigrationCore`는 검증 초안이다. 실제 원본 날짜 증거 보존, 검색 이력 범위, 충돌 데이터 복구 정책, 새 모델 매핑과 원자적 저장 설계 후 연결한다. 순수 변환 테스트 통과를 실제 업그레이드 검증으로 취급하지 않는다.

아래 작업 순서는 이 선행 조건을 포함해 진행한다. 이번 검토 중 제품 코드는 추가 변경하지 않는다.

## 순서 및 완료 기준

1. **기존 앱 기준·이관 계약 확보 (완료, 실데이터 미검증)**: 저장 위치/키 목록, 원본을 열지 않는 Realm 복사본 읽기, 형식이 보존되는 UserDefaults 캡처, 캡처 백업과 SHA-256 지문을 구현했다. 실제 배포 데이터 파일 검증은 남아 있다.
2. **핵심 모델 및 화면 기술 검증 (iOS 완료)**: 날짜별 추가·수정·삭제/합계/목표 이력을 `HelloProteinCore`로 분리하고 SwiftUI 기록 화면을 제품 시작 흐름(플래그 뒤)에 연결했다. Android Compose 구현과 양쪽 동작 비교는 남아 있다.
3. **실제 이관 (시뮬레이터 검증 완료)**: Realm/UserDefaults 읽기 → 검증 → 새 저장소 원자적 교체 → 합계 검산 → 완료 마커. 원본 삭제 없음, 교체 직전/직후 강제 종료 후 재실행 검증. 중간 버전 건너뛰기는 schema 1 파일 승격 경로로만 커버한다.
4. **핵심 기능**: 기록/통계/설정, 영어/단위/접근성. 과거 합계만 남은 날짜를 상세 기록이 있는 날짜와 구분하는 UI는 구현했다. 통계·설정·검색 화면의 새 저장소 연결은 남아 있다.
5. **양쪽 플랫폼 베타**: iOS 업데이트와 Android 새 설치를 각각 검증한다. 실사용 데이터 보존을 출시 조건으로 둔다.
6. **유료 기능 검증**: 기존 무료 기록/즐겨찾기는 유지한다. 신규 AI 입력은 결제 동의 없이 성공 저장 3회 체험을 초기 가설로 둔다. 취소·실패는 체험 횟수에서 제외하되 서버 요청 비용 제한은 별도로 둔다. 기능의 재사용과 비용 검증 후 Pro 출시 여부 결정.

## 현재 코드에서 확인한 기준

- 앱 식별자: `com.devsom.ProteinTracker`, 프로젝트 최소 OS: iOS 13. 새 흐름은 iOS 15 이상에서만 실행되고, 그 미만에서는 데이터를 건드리지 않는 안내 화면을 띄운다.
- Realm: DailyProtein(오늘 음식 상세), StatProtein(과거 합계), Favorites, SearchHistory.
- UserDefaults: `Date`(날짜 객체), `date`(지역화된 날짜 문자열), `totalIntake`, `targetProtein`, `searchLanguage`.
- `ShowViewController.viewWillAppear`가 날짜 변경 시 `Storage.resetData()`를 호출해 오늘 상세를 삭제한다. 새 저장소 증거가 있으면 `SceneDelegate`가 기존 UIKit 경로를 만들지 않으므로 이관 뒤에는 이 코드가 실행되지 않는다.
- 새로운 iOS UI를 크게 수정하기 전에 Android 공통 기술을 결정한다. 이번 Swift 모듈은 iOS 구버전 데이터 이관 경계이며 Android 공통 런타임 선택이 아니다.

## 구현 현황 (2026-09-28)

`HelloProteinCore` (schema 2 저장 계약)

- `AppState` 봉투: logs/favorites/searchHistory/settings/goals/migration을 한 문서로 저장하고, 디코딩 뒤에도 `validate()`로 중복 날짜·중복 ID·목표 이력 충돌을 거부한다.
- `FileAppStateStore`: 검증 → 같은 디렉터리 임시 파일(POSIX write+fsync, 실패는 예외가 아닌 오류로 보고) → 디코드/비교 → `rename` → 디코드/비교. 경로별 재귀 락, 파일 보호 `.completeUntilFirstUserAuthentication`, 실패 주입용 `StoreFileWriter`/`StoreCommitHooks`, 1시간 이상 지난 임시 파일만 정리. 디렉터리 fsync는 하지 않으므로 전원 차단 내구성은 보장하지 않는다.
- 커밋 결과 계약(`StoreCommitError`): `rename` 이전 실패는 `notCommitted`(이전 파일 그대로, 같은 작업 재시도 가능), `rename` 이후 확인 실패는 `indeterminate`(교체는 됐을 수 있음, 되돌리지 않음). `indeterminate` 뒤에는 `load()`가 성공할 때까지 모든 쓰기를 거부한다. 각 사용자 저장은 operation ID를 문서의 `lastOperationID`에 남기므로 다시 읽었을 때 그 작업이 반영됐는지 판단할 수 있다. 값이 없는 기존 schema 2 파일은 nil로 읽는다.
- 입력 검증(`ProteinInput`): 음식 입력은 양수만, 구버전 날짜의 일일 총량 편집은 0과 음수를 허용한다(삭제로 음수가 된 보정값을 그대로 다시 저장할 수 있어야 하므로). 빈 값, 숫자 아님, 자릿수 초과, 범위 초과를 구분한다.
- `LegacyAggregate`로 원본 총량·원본 라벨·시각·사용자 수정 총량을 보정값과 별도로 보존한다. 총량 = 상세 합계 + 보정값.

`MigrationCore` (캡처 → 검증 → 매핑 → 조정자)

- 캡처는 검증 전에 백업하고, UserDefaults 값의 누락/0/형식 오류를 구분해 기록한다. 지문은 정렬 키 JSON의 SHA-256.
- 결정적 ID(`legacy:daily:<id>` 등), 0.01g 정수 변환과 범위 초과 검사, 0 이하 음식은 복구 화면으로, 잘못된 목표는 원문 보존 + `goalNeedsReview`, 목표는 이관 당일부터 적용.
- `MigrationCoordinator` 시작 판정: ready / corrupt / unsupported / unreadable / schema1 승격 / missing(완료 증거 → storeLost, 레거시 → 이관, 백업만 → 백업에서 이관, 없음 → 명시적 새 설치). 완료 마커는 보조 증거다.
- 증거 파일 판정(`EvidenceInspection`): missing / valid / corrupt / unreadable / unsupported를 구분한다. 목적 저장소가 없을 때 완료 마커나 백업이 존재하지만 읽거나 해독할 수 없으면 구 원본을 조사하지도 않고 `evidenceCorrupt`/`evidenceUnreadable`/`evidenceUnsupported` 복구 상태로 멈춘다. 새 저장소·재이관·빈 설치를 만들지 않고 파일 바이트를 바꾸지 않는다. 목적 저장소가 정상이면 손상된 보조 증거는 사용자 기록을 막지 않지만 자동으로 덮어쓰지도 않는다(정말 없을 때만 다시 쓴다). 백업·완료 파일에는 `evidenceFormatVersion`이 있고, 필드가 없는 기존 파일은 1로 읽는다.

iOS 앱 연결

- `RenewalLaunchPolicy`: 기본은 기존 경로. `-HelloProteinRenewalFlow YES` 또는 `HELLOPROTEIN_RENEWAL_FLOW=1`일 때만 새 흐름. 새 저장소 증거(`app-state.json` 또는 완료 마커 `migration-completed.json`)가 있으면 플래그와 무관하게 새 흐름(또는 iOS 15 미만 안내)으로 강제한다. 캡처·백업 디렉터리만 있는 상태(커밋 전 실패)는 증거로 보지 않으므로 기존 앱을 계속 쓸 수 있다.
- `RealmLegacySourceGateway`: 원본 Realm을 열지 않는다. 닫힌 원본을 증거 디렉터리로 복사하고, 별도 사본을 읽기 전용으로 연다.
- `SceneDelegate`가 창을 직접 만들고(스토리보드 자동 생성 제거) 로딩 → 기록 화면/복구 화면으로 분기한다. 복구 화면에는 재시도만 있고 초기화·삭제가 없다.
- SwiftUI 기록 화면: 주간 날짜 띠, 달력 시트, 추가/수정/삭제, 과거 합계만 있는 날짜 표시, 일일 총량 편집, 저장 실패 시 시트 유지와 경고.
- 저장 결과 미확정 처리: `rename` 이후 확인 실패는 "저장 결과 미확인" 경고와 함께 시트를 유지하고, 저장 버튼을 비활성화하며, "저장 결과 확인" 동작으로 저장소를 다시 읽는다. 반영됐으면 시트를 닫고, 반영되지 않았으면 입력을 유지한 채 다시 저장하게 한다. 확인 전에는 홈 화면 배너가 뜨고 모든 저장이 거부된다. 편집 세션은 같은 record ID를 유지하므로 재시도로 중복 행이 생기지 않는다. 저장 중에는 취소도 비활성화한다.
- DEBUG 전용 `-HelloProteinFailAfterReplaceOnce YES`: 시작 후 첫 사용자 저장을 `rename` 직후 실패시켜 미확정 경로를 시뮬레이터에서 재현한다. 권한을 바꾸지 않는다.
- DEBUG 전용 실행 인자: `-HelloProteinSeedLegacyFixture YES`(합성 구버전 데이터), `-HelloProteinInterruptAt <beforeBackup|afterBackup|afterMapping|afterTemporaryWrite|beforeReplace|afterReplace|beforeFirstScreen>`(SIGKILL).

## UI 기준 정리 (2026-09-29, 권장안 / 미확정)

`docs/ui-direction-plan.md`에 따라 제품 코드 변경 없이 문서·시안만 작성했다.

- [ui-audit.md](ui-audit.md): 기존 UIKit 앱(실행 캡처·코드), Figma 의도(2026-09-23 검토 문서 기준, 원본은 이번 세션에서 접근 거부), 현재 SwiftUI 프로토타입을 요소별로 비교. 관찰/계산/추론을 구분했다.
- [ui-spec.md](ui-spec.md): 화면 트리(권장안 A 홈+하단 액션 바, 대안 B 3탭+FAB), 8개 핵심 흐름, 화면별 상태, 색·서체·간격 토큰 초안, 결정 기록, §6 저장 계약 재확인.
- [ui-preview/](ui-preview/README.md): 클릭 가능한 로컬 HTML 시안. 기존 앱·현재 프로토타입 캡처와 나란히 비교, 한/영·큰 글자·A/B·라이트/다크 전환, 필수 상태 34개 갤러리, 합성 fixture.
- [ui-implementation-backlog.md](ui-implementation-backlog.md): 5단계 후속 구현 순서. 각 항목에 현재/목표, 파일, 데이터 의존성, 시각 확인, 회귀 검사.

사용자 결정 대기: 화면 구조(A/B), 브랜드 유지 범위(크림·민트·그린·Binggrae 숫자·계란 워드마크), 다크 모드 지원 여부, 목표 진입점, 계산기 옵션 범위. 결정 전에는 제품 화면을 교체하지 않는다.

## 아직 해결할 사항

- 실제 사용자 Realm 파일, 실기기, iOS 13/14 기기, 배포 바이너리와 저장소 HEAD 일치 여부는 미검증이다. 새 흐름의 Release 기본 활성화(플래그 제거)는 하지 않았다.
- 통계·설정·검색·즐겨찾기 화면은 아직 기존 UIKit 구현이며 새 저장소와 연결되지 않았다. 새 흐름에서는 기록 화면만 제공된다.
- 전원 차단 수준의 내구성(fsync 이후 디스크 동작)은 시뮬레이터 SIGKILL로만 검증했다.
- 설치된 Xcode 27.1은 iOS 13 시뮬레이터 타깃을 지원하지 않아 검증 명령에서만 iOS 15를 지정했다. 프로젝트 최소 OS 13은 아직 바꾸지 않았다.
- `Config.xcconfig`의 안전한 기본값과 선택적 로컬 `Secrets.xcconfig` 포함으로 빌드 설정을 복구했다. 사용 흔적이 없는 누락 `GoogleService-Info.plist` 리소스 참조도 제거했다.
- Android 개발 도구는 현재 환경에서 발견되지 않았다. iOS SwiftUI와 같은 기록 계약으로 Compose 흐름을 만드는 단계에서 설치·검증한다.

## 검증 명령

```sh
swift test --package-path HelloProteinCore --scratch-path /private/tmp/helloprotein-core-tests
swift test --package-path MigrationCore --scratch-path /private/tmp/helloprotein-migration-tests
xcodebuild -project ProteinTracker/ProteinTracker.xcodeproj -scheme ProteinTracker -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/helloprotein-next/build \
  -onlyUsePackageVersionsFromResolvedFile -disableAutomaticPackageResolution build \
  CODE_SIGNING_ALLOWED=NO IPHONEOS_DEPLOYMENT_TARGET=15.0
xcodebuild -project ProteinTracker/ProteinTracker.xcodeproj -scheme ProteinTracker \
  -destination 'platform=iOS Simulator,id=B67306B6-85DB-44CC-BC0D-2F5673D79D7D' \
  -derivedDataPath /private/tmp/helloprotein-next/build -resultBundlePath /private/tmp/helloprotein-next/test-3.xcresult \
  -onlyUsePackageVersionsFromResolvedFile -disableAutomaticPackageResolution test \
  CODE_SIGNING_ALLOWED=NO IPHONEOS_DEPLOYMENT_TARGET=15.0
```

2026-09-28 결과: `HelloProteinCore` 40개, `MigrationCore` 53개, 앱 테스트 타깃 25개 통과(로그 `/private/tmp/helloprotein-next/core-tests-3.log`, `migration-tests-3.log`, `app-test-5.log`, 모두 exit 0). 앱 Debug 빌드 성공(`/private/tmp/helloprotein-next/app-build-5-debug.log`, exit 0). 별도 코드 리뷰 패스에서 나온 상위/중간 지적(예외로 죽는 FileHandle 쓰기, 실패한 이관이 기존 앱을 막는 증거 판정, 빈 이름 검산 오류, 임시 파일 중단 지점 누락, 0/음수 총량 편집 불가, 목표 이력 오류를 빈 상태로 표시, 복구 화면의 원시 상세 노출, 임시 파일 일괄 삭제, 픽스처 시더 보호, 달력 범위)은 반영했고, 시트 3개 체인·`FileRecordRepository` 잔존·보정값 0인 날의 안내 표시는 남겨 두었다. 시뮬레이터 시나리오(정상 업그레이드, 교체 직전/직후 강제 종료 후 재실행, 과거 날짜 추가·총량 편집, 저장 실패, 기본 경로 유지, 손상 저장소 복구 화면)는 `docs/evidence/2026-09-28-simulator/README.md`에 정리했다. 실제 사용자 파일·실기기·Android는 미검증.

2026-09-28 후속(PR #2 리뷰 R1·R2) 결과: 증거 파일 판정 계약과 커밋 결과 계약(`notCommitted`/`indeterminate`, 경로 단위 쓰기 차단, 읽기 재확인, operation ID)을 넣고 회귀 테스트를 먼저 추가했다. 별도 코드 리뷰 패스의 지적(미확정 차단이 인스턴스에만 있고 `inspect()`가 풀지 않아 이관 미확정 뒤 저장이 영구 실패, 배너의 `notApplied` 무시, 증거 문제 시 백업 유무 오보, `afterReplace` 중단 분류, `commit()`의 검증 오류 포장, 플래그 읽기 락, 미확정 중 행 편집, 캡처 버전 프로브, 인자 truthy 판정)을 반영했다. 2차 리뷰에서 백업 본문의 SHA-256을 fingerprint와 대조하지 않던 판정과 미확정 중 입력란이 열려 있던 문제를 고쳤다. `HelloProteinCore` 45개, `MigrationCore` 64개, 앱 테스트 타깃 30개 통과(로그 `/private/tmp/helloprotein-next/core-tests-5.log`, `migration-tests-6.log`, `app-test-10.log`, 모두 exit 0). 앱 Debug/Release 빌드 성공(`app-build-8-debug.log`, `app-build-8-release.log`, exit 0)이며 Release 바이너리에는 실패 주입·픽스처 인자 문자열이 없다. 시뮬레이터 시나리오(정상 이관 후 과거 날짜 추가, 손상 완료 마커의 복구 화면과 파일 보존, `rename` 이후 읽기 실패 → 재확인 → 재실행에서 한 행)는 `docs/evidence/2026-09-28-pr2-followup/README.md`에 정리했다. `notApplied` 경로, 권한 없음/상위 버전 증거, 실제 사용자 파일·실기기는 미검증.
