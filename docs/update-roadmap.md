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
- [ui-preview/](ui-preview/README.md): 클릭 가능한 로컬 HTML 시안. 기존 앱·현재 프로토타입 캡처와 나란히 비교, 한/영·큰 글자·A/B·라이트/다크 전환, 필수 상태 36개 갤러리, 합성 fixture.
- [ui-implementation-backlog.md](ui-implementation-backlog.md): 5단계 후속 구현 순서. 각 항목에 현재/목표, 파일, 데이터 의존성, 시각 확인, 회귀 검사.

다음 작업은 [공동 검토된 Phase 1 계획](ui-phase1-implementation-plan.md)에 따라 홈 UI → Phase 1B 편집·미확정·복구 UX → 목표 설정 순서로 진행한다. 최종 A/B 결정은 내비게이션 연결 전으로 분리한다. 이번 홈·추가 배치와 브랜드·테마의 사용자 결정은 아직 미확정이다.

후속까지 포함한 사용자 결정 대기: 화면 구조(A/B), 브랜드 유지 범위(크림·민트·그린·Binggrae 숫자·계란 워드마크), 다크 모드 지원 여부, 목표 진입점, 계산기 옵션 범위. 결정 전에는 제품 화면을 교체하지 않는다.

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

## 2026-10-01 Phase 1 구현

기록 홈/기존 편집 시트 테마와 표시 컴포넌트, 원본·보정 구분, 미확정 안내를 구현했다. 저장·이관 계약과 기본 실행 경로는 유지한다. [구현·검증 기록](evidence/2026-09-30-ui-phase1/README.md)을 참고하며, UI 검증 제한이 남아 있으므로 출시 준비 완료로 간주하지 않는다. 다음 기능 구현은 Phase 1B 편집·미확정 닫기 확인·복구 UX다.

## 2026-10-05 일반 iPhone 보정

Phase 1 홈을 일반 iPhone(SE 3세대 375 pt, iPhone 17 402 pt, iOS 26.5 시뮬레이터)에서 실행했다. 실제 문제는 SE에서 날짜 줄 좌우 4.5 pt 잘림 하나였고 `DayStrip`만 보정했다(비접근성 글자 7일 균등 폭 고정, 접근성 글자는 가로 스크롤 유지). 두 기기에서 홈·달력·과거·펼침·총량 시트·추가/수정/삭제·미확정 재확인·AX3·시스템 다크 시나리오를 XCTest 하네스로 통과했고 Core 45·Migration 64·앱 32 테스트가 통과했다. [실행 증거](evidence/2026-10-05-iphone-ui/README.md). Duo 동시 대응은 연기했으며 이전 Duo 결과는 일반 iPhone QA 근거로 쓰지 않는다. 실제 VoiceOver·iOS 15·실기기는 미검증이고 기본 활성화·출시는 하지 않았다.


## 2026-10-06 PR #5 이후 계획

PR #5는 2026-10-05 main에 병합됐다(`64b9688ee674a8bdb831ea4298f1cfeb847f05ab`). 다음 작업은 [Phase 1B 편집 확인과 저장 결과 안내](ui-phase1b-editing-recovery-plan.md)다. 본사 기획·디자인·개발·QA·마케팅·프롬프트 엔지니어·그로스 7개 직무의 [공동 검토](reviews/2026-10-06-phase1b-team-review.md)를 반영했다.

취소/스와이프의 초안 버리기 확인, 삭제 확인, 미확정 닫기와 재확인 안내, 조건부 복구 문구를 먼저 구현한다. 인라인 입력 안내·키보드 액세서리·검증된 문의 연결은 후속으로 분리한다. 그다음 목표 설정과 기존 무료 검색·즐겨찾기 연결을 진행한다. 일반 iPhone 기준과 Duo 연기 결정을 유지하며, 위 9월의 미확정 UI 방향 기록은 당시 이력이다. 현재 홈을 다시 설계하는 작업은 이번 범위에 없다. 이번에는 계획 문서만 작성했고 제품 수정이나 새 실행 테스트는 하지 않았다.

## 2026-10-06 Phase 1B 구현

[Phase 1B 계획](ui-phase1b-editing-recovery-plan.md)대로 두 편집 시트(음식 기록·하루 총량)에 취소·스와이프 공통 닫기 정책(처리 중 차단 → 미확정 닫기 확인 → 초안 버리기 확인 → 바로 닫기), 저장된 값 기준 삭제 확인, 미확정 닫기 확인을 넣고 복구 화면 문구를 상태 플래그 조건부로 정리했다. 저장 schema·commit·이관 판정·ID 수명·플래그 기본값·최소 OS는 바꾸지 않았다. 미반영·재확인 읽기 실패는 DEBUG 전용 저장소 대역(`-HelloProteinSaveOutcomeOnce`)으로 검증했고 실제 `afterReplace` 재확인과 구분해 기록했다. [실행 증거](evidence/2026-10-06-phase1b/README.md). iOS 15 런타임·실기기·VoiceOver는 미검증이며 기본 활성화·출시는 하지 않았다.


## 2026-10-06 PR #6 이후 다음 계획

PR #6은 main에 병합됐다(`e6acbed`). 다음은 [목표 설정·목표 이력 구현 계획](goal-settings-implementation-plan.md)이다. 본사 7개 직무 [공동 검토](reviews/2026-10-06-goal-settings-team-review.md)를 반영했다. 오늘 홈에서 직접 목표를 설정·변경하고 과거 목표를 보존하며, 같은 날 교체·자정·이관 값·미확정 저장을 검증한다. 계산기·온보딩·전체 설정·수익화는 후속이다. 그 시점에는 계획만 작성했고, 구현은 아래 항목에서 같은 날 진행했다.

## 2026-10-06 목표 설정·목표 이력 구현

[목표 설정 계획](goal-settings-implementation-plan.md)대로 오늘 홈에 임시 ‘목표 설정/변경’ 진입을 두고 하루 단백질 목표 시트를 구현했다. 새 목표는 시트를 연 시점의 오늘부터 적용되고, 같은 날 두 번 저장하면 그날 항목 하나를 교체하며, 이전 날짜의 목표·기록·합계는 보존된다. 저장 진입 시 최신 시각으로 오늘을 다시 검사해 날짜가 바뀌었으면 쓰기 없이 거부하고, 사용자가 적용일을 명시적으로 갱신한 뒤 다시 저장한다. 이관 검토 flag 정리는 목표 저장과 같은 commit에서 수행하고 원문은 보존한다. 동일한 값은 쓰기 없는 no-op이다. 재확인 읽기 실패는 이제 `.reconfirmFailed`로 구분해 중립 문구를 쓴다(Phase 1B 미검증 항목 해소). 처리 중·자정은 DEBUG 전용 지연·시계 대역으로 UI에서 결정적으로 재현했다. 저장 schema·commit·이관 판정·플래그 기본값·최소 OS는 바꾸지 않았다. [실행 증거](evidence/2026-10-06-goal-settings/README.md). 계산기·온보딩·설정 화면·iOS 15·실기기·VoiceOver는 범위 밖 또는 미검증이다.


## 2026-10-07 PR #7 이후 계획

PR #7은 `c4ab644`로 병합됐다. 다음은 [즐겨찾기·검색 연결 계획](favorites-search-implementation-plan.md)이며 [본사 7개 직무 공동 검토](reviews/2026-10-07-favorites-search-team-review.md)를 반영했다. A는 즐겨찾기 조회·관리·원자적 다중 기록 추가, B는 공급자 기준량 검증 후 검색·최근 검색·검색 언어 연결이다. 그 시점에는 plan만 작성했고, A단계 구현은 아래 항목에서 같은 날 진행했다. 기존 무료 기능·이관 원문·전역 미확정 잠금을 보존한다.

## 2026-10-07 즐겨찾기 연결(A단계) 구현

[즐겨찾기·검색 계획](favorites-search-implementation-plan.md)의 A단계를 구현했다. 홈의 추가 버튼은 이제 직접 입력/즐겨찾기 2탭 시트를 열고, 열 때의 선택 날짜를 세션 동안 고정한다(과거 날짜 기록 가능, 자정에도 유지). 이관된 즐겨찾기는 position 순서로 보이고 ID·원문·signed 값·legacySourceID를 그대로 둔다. 0·음수 값은 숨기지 않고 선택만 막으며 목록 안 편집 모드로 실제 수정할 수 있다. 직접 입력과 기존 기록 수정에 ‘즐겨찾기에도 저장’을 두어 기록과 즐겨찾기를 한 commit으로 저장하고, 이름(trim)·양이 정확히 같은 항목은 재사용한다. 즐겨찾기 다중 선택은 한 번의 modify로 N행을 추가하거나 0행이며, 선택 이후 바뀐 항목이 있으면 전체를 거부하고 재확인을 요구한다. 탭 전환은 현재 탭이 dirty일 때만 확인하고 그 탭의 초안만 버린다. 쓰기마다 작업 종류를 들고 있어 미확정 재확인 성공 시 기록/다중 추가는 시트를 닫고, 즐겨찾기 편집은 목록으로 돌아가고, 삭제는 머문다. 저장 schema·이관·플래그 기본값·최소 OS는 바꾸지 않았고 무료 즐겨찾기에 개수 제한을 두지 않았다. [실행 증거](evidence/2026-10-07-favorites/README.md). B단계(검색)는 공급자 기준량 확인 후 별도 PR이다.
