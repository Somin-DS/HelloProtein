# 일반 iPhone UI 보정·검증 인계 계획

작성: 2026-10-05 (Asia/Seoul) · 대상: 후속 구현 AI 에이전트

## 1. 요청과 목표

사용자는 Phase 1 캡처가 iPhone Duo에 맞춰진 것에 이의를 제기했고, **일반 iPhone에 맞게 수정하며 Duo 동시 대응은 추후로 미룬다**고 결정했다. 이후 구현을 중단하고 다른 에이전트에게 넘길 plan 문서 작성을 요청했다. 이 문서 작성 과정에서는 제품 코드를 수정하지 않았다.

목표는 기존 Phase 1 구현을 일반 iPhone 세로 화면에서 사용할 수 있게 보정하고, 실제 일반 iPhone 시뮬레이터에서 기능·레이아웃을 검증하는 것이다. 새로운 디자인 전면 개편이나 다음 기능 개발이 아니다.

완료 결과물은 코드 diff, 재현 가능한 검증 기록, 기능별 실제 PNG 캡처, PR에 사용할 변경·검증 설명이다. 새 기본 실행 경로 활성화, 출시, 관리자 우회 병합은 이번 인계의 완료 조건이 아니다.

## 2. 현재 상태와 인계 주의사항

| 항목 | 2026-10-05 확인 결과 |
| --- | --- |
| 작업 폴더 | `/Users/somin/orca/HelloProtein` |
| 브랜치 | `feat/renewal-home-phase1` |
| HEAD | `d6ad3dd0f42643bc53c4814cdd037ea65d5c59dd` |
| Phase 1 구현 | 로컬 미커밋 변경과 untracked 신규 파일로 존재 |
| 일반 iPhone 보정 | 조사만 수행. 보정 코드 미적용 |
| 기존 실행 증거 | Duo 런타임에서 확보. 일반 iPhone 검증을 대체하지 못함 |
| 새 검증·PR·머지 | 미완료 |

**원격 브랜치나 HEAD만 checkout하면 Phase 1 구현이 따라오지 않는다.** 현재 작업 폴더에서 이어받거나, 새 작업 폴더로 옮길 경우 tracked diff와 필요한 untracked 파일을 함께 인계한 뒤 확인한다. `reset --hard`, `clean`, 전체 checkout으로 기존 작업을 버리지 않는다. Orca 작업 폴더를 새로 만들거나 에이전트를 실행하는 경우 해당 환경의 orca-cli 스킬을 따른다.

수정된 주요 파일:

- `ProteinTracker/ProteinTracker.xcodeproj/project.pbxproj`
- `ProteinTracker/ProteinTracker/Renewal/RecordHomePrototypeView.swift`
- `ProteinTracker/ProteinTracker/Localization/{en,ko}.lproj/Localizable.strings`
- `ProteinTracker/ProteinTrackerTests/RecordHomeViewModelTests.swift`
- `docs/ui-direction-plan.md`, `docs/ui-implementation-backlog.md`, `docs/ui-spec.md`, `docs/update-roadmap.md`

새 파일/폴더:

- `ProteinTracker/ProteinTracker/Renewal/Components/`
- `ProteinTracker/ProteinTracker/Renewal/RenewalTheme.swift`
- `ProteinTracker/ProteinTracker/Renewal/GoalProgressPresentation.swift`
- `docs/ui-phase1-implementation-plan.md`, `docs/reviews/`, `docs/evidence/2026-09-30-ui-phase1/`

`.DS_Store` 및 `agents/`도 상태에 나타난다. 이번 구현 파일로 일괄 stage하지 말고, 소유·관련성을 확인한다. 기존 사용자 변경은 보존한다. 시작 시 `git status --short`, `git diff --stat`, 관련 소스와 적용되는 `AGENTS.md`를 다시 확인한다.

## 3. 문제의 원인과 해석

현재 Renewal 소스에서 Duo 전용 분기는 확인되지 않았다. 기존 캡처의 오른쪽 시스템 표시와 툴바 배치는 Duo 실행 환경에서 관찰된 결과이며, 이를 없애려고 임의의 음수 padding, 상태바 숨기기, 고정 화면 폭, 전역 UIKit appearance 변경을 넣지 않는다.

현재 `RecordHomeView`는 `NavigationView` + `.stack`, 본문 `ScrollView`, 하단 `safeAreaInset` 구조다. **먼저 일반 iPhone에서 현재 코드를 실행해 실제 문제를 확인한다.** 그대로 정상인 영역은 유지하고, 실제 작은 화면 문제만 보정한다.

명확한 점검 대상은 `DayStrip`이다. 현재 최소 44pt 버튼 7개와 6pt 간격 6개로 최소 344pt가 필요하다. 375pt 화면의 좌우 20pt 여백을 제외하면 335pt여서 기본 글자 크기에서도 날짜 줄이 가로 스크롤된다. 일반 글자 크기에서는 7일을 한눈에 볼 수 있도록 개선하되, 접근성 큰 글씨에서는 글자를 줄이거나 터치 영역을 포기하지 않고 스크롤 등으로 대응한다.

## 4. 범위

### 포함

- 일반 iPhone 세로 화면의 홈, 날짜 선택, 기록 추가·수정·삭제, 과거 합계 편집, 저장 상태 안내.
- 상단 제목·오늘·달력의 배치, safe area, 하단 버튼과 마지막 목록 항목의 겹침 확인.
- 일반 글자 크기에서 날짜 7개 표시, 큰 글씨에서 읽기·조작 가능성.
- 키보드 표시 상태에서 입력·저장·취소·스크롤 가능성.
- 한국어·영어 화면 확인 및 실제 기능별 캡처.
- 기존 저장·이관 동작의 회귀 검사와 검증 기록 갱신.

### 제외

- Duo 전용 분기·듀얼 디스플레이·동시 최적화. Duo용 커스텀 처리는 새로 만들지 않는다.
- iPad 최적화, 가로 UI 재설계, 앱 전체 지원 방향 변경.
- 검색·즐겨찾기·목표 설정·히스토리·설정 연결, 새 탭 바.
- Phase 1B의 삭제/초안 버리기 확인 정책 변경, AI·구독·광고·Android.
- 데이터 스키마·저장 API·마이그레이션·Realm 업그레이드, 최소 OS 변경.
- 전역 색상 변경, 새 흐름 기본 활성화, 배포.

기존 크림·민트·진한 녹색 테마와 본문 시스템 글꼴/숫자 Binggrae는 이번 보정의 기준으로 유지한다. 일반 iPhone 보정 위임을 전체 디자인 최종 승인으로 해석하지 않는다.

## 5. 실행 환경 확보 — 첫 단계

2026-10-05 확인:

- `xcode-select -p`: `/Users/somin/Downloads/Xcode.app/Contents/Developer`
- `/Applications/Xcode.app`도 존재하며 `xcodebuild -version`은 Xcode 26.5, build 17F42. 이 경로에는 `Simulator.app`이 있다.
- 등록된 런타임은 iOS 27.1, build 24A94401 하나이며 지원 기기 목록은 **iPhone Duo만**이다.
- 이전 턴에 `/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -downloadPlatform iOS`를 요청했다. 턴 중단으로 최종 결과를 확보하지 못했다. 문서 작성 시에도 일반 iPhone 런타임은 목록에 없었다. 다운로드 실행 중 여부는 확인되지 않았다.

실행 순서:

1. 설치된 Xcode·SDK·런타임과 남은 다운로드 작업을 확인한다. 이미 진행 중인 다운로드를 중복 실행하지 않는다.
2. 일반 iPhone 지원 런타임을 설치한다. 권한·네트워크 제한은 환경의 승인 절차를 따른다. 앱 코드를 바꾸어 Duo를 일반 iPhone처럼 보이게 만드는 우회는 하지 않는다.
3. 선택한 Xcode를 **명령별 `DEVELOPER_DIR`**로 일관되게 지정한다. 사용자 전역 `xcode-select`를 임의로 바꾸지 않는다. 빌드·simctl·UI 하네스에 같은 개발 도구를 사용한다.
4. 전용 합성 데이터 기기를 만든다. 작은 기기(가능하면 iPhone SE 3세대, 375×667pt)와 일반 크기 기기(설치 런타임이 지원하는 iPhone, 대략 390~402pt 폭)를 선택한다. 정확한 기종과 실제 크기를 기록한다.
5. `orca-emulator` 스킬을 읽고 일반 iPhone에 attach한다. 기존의 SimulatorKit 부재는 Downloads Xcode에서의 과거 실패이므로 새 Xcode에서도 실패한다고 단정하지 않는다.
6. Orca 제어가 실패하면 구체적인 오류를 기록하고 XCTest UI 하네스 등으로 실제 일반 iPhone 앱을 조작·캡처한다. HTML이나 Duo 캡처를 대체 증거로 제출하지 않는다.

일반 iPhone 실행 환경을 확보하지 못하면 보정 소스와 실행 미검증을 명확히 나누어 보고한다. 화면을 확인하지 않은 채 일반 iPhone 대응 완료로 표시하지 않는다.

## 6. 구현 순서와 완료 기준

### A. 동일 데이터 기준 화면 확보

현재 미커밋 Phase 1 코드를 일반 iPhone에서 먼저 빌드·실행하고 홈/추가/편집의 수정 전 캡처를 남긴다. 사용자 실데이터나 기존 Duo 검증 설치는 초기화하지 않는다. 신규 전용 시뮬레이터의 합성 데이터만 사용한다.

fixture는 `Migration/LegacyFixtureSeeder.swift`와 실제 실행 인자 처리 코드를 확인한다. 기존 시더 인자 `-HelloProteinRenewalFlow YES -HelloProteinSeedLegacyFixture YES`는 빈 설치의 최초 준비용이다. 이관된 설치에 플래그를 반복 전달한다고 데이터가 초기화되는 것은 아니다.

기존 UI 하네스의 09-23/09-20 날짜, 주 이동 횟수와 목표 132g 기대값을 그대로 재사용하지 않는다. 10-01 이후 날짜 변화·누적 기록 때문에 결과가 달라진다. 달력으로 고정 fixture 날짜를 직접 선택하거나 테스트에서 실행일 기준으로 날짜를 계산하고, 기대 합계를 명시한다.

### B. 홈 보정

| 대상 | 구현/확인 기준 |
| --- | --- |
| 날짜 줄 | 기본 글자에서 7일 모두 표시. 균등 폭/간격 축소 등 최소 변경. 터치 영역 약 44pt 이상 유지 |
| 큰 글씨 | 날짜·요일이 잘리지 않고 선택 날짜 접근 가능. 필요 시 가로 스크롤, 본문 세로 스크롤 유지 |
| 상단 | 제목·오늘·달력 접근 가능. 시스템 툴바의 실제 iPhone 동작을 확인한 뒤 수정 |
| 요약 | 큰 합계·목표 없음·목표 이력 없음·초과량의 의미 및 단위 유지 |
| 음식 목록 | 긴 이름과 단백질량 읽기 가능. 마지막 행을 하단 추가 버튼에 가리지 않게 끝까지 스크롤 가능 |
| 추가 버튼 | 홈 인디케이터와 겹치지 않음. 작은 기기에서도 접근 가능. 선택 날짜에 추가 |
| 가져온 기록 | 원본·음식 합계·signed 보정·현재 합계의 의미 유지. 펼친 내용과 편집 진입까지 스크롤 가능 |

주요 대상: `Renewal/Components/DayStrip.swift`, `DaySummary.swift`, `FoodRow.swift`, `LegacyTotalDisclosure.swift`, `RenewalTheme.swift`, `RecordHomePrototypeView.swift`. 실제 문제 없는 컴포넌트까지 재작성하지 않는다.

### C. 편집 시트 보정

음식 추가·수정과 하루 합계 편집에서 기본/소수 키보드, 긴 음식명, 저장·취소·삭제를 확인한다. 불필요한 고정 높이를 두지 않고 작은 화면의 스크롤을 보장한다. UIKit 전역 설정이나 별도의 키보드 높이 하드코딩보다 SwiftUI safe area 동작을 우선한다.

`@StateObject`, `EditorTarget`의 날짜/record ID, 입력값, pending 상태 수명을 보존한다. UI 보정으로 `perform`/`reconfirm` 또는 정수 centigram 계산을 변경하지 않는다. 저장 중·미확정 중의 비활성 조건과 홈 재확인 동작도 유지한다.

### D. 검증·캡처·문서

아래 검증표를 실행하고 실제 결과를 기록한다. 실패한 레이아웃만 보완한 후 영향받는 시나리오를 다시 확인한다. 통과 수를 맞추기 위해 기대값을 변경하지 않는다.

## 7. 필수 검증표

| 시나리오 | 작은 iPhone | 일반 iPhone | 기대 결과 |
| --- | --- | --- | --- |
| 한국어/영어 홈, 기본 글자 | 필수 | 필수 | 날짜 7개, 상단 동작, 하단 추가 정상 |
| 과거 날짜 조회·오늘 복귀·달력 선택 | 필수 | 필수 | 선택 날짜와 내용 일치 |
| 추가→수정→재실행→삭제 | 필수 | 필수 | 날짜·값 저장 유지, 수정이 중복 추가되지 않음 |
| 음식/총량 입력과 키보드 | 필수 | 필수 | 입력·저장·취소 접근 가능 |
| 원본55/상세45/보정10 및 합계 전용70 | 필수 | 필수 | 값 구분, 펼침/편집 가능 |
| 목표 없음/이력 없음/목표 달성·초과 | 필수 | 필수 | 실제 상태별 문구·값 일치 |
| 큰 글씨 AX3, 긴 음식명·긴 안내 | 필수 | 필수 | 잘림 없이 스크롤/조작 가능 |
| 미확정→닫기→홈 재확인 | 필수 | 필수 | 입력·추가 잠금, 안내 접근, 중복 저장 없음 |
| 시스템 다크에서 Renewal 라이트 | 대표 기기 | 대표 기기 | 시트·달력까지 읽을 수 있음 |
| VoiceOver 핵심 읽기·조작 | 가능한 대표 기기에서 실제 확인 | 결과 기록 | 날짜·합계·행·추가·오류의 순서/라벨 |

VoiceOver를 실제 사용하지 못하면 미검증으로 남긴다. 접근성 트리 조회를 발화·초점 검증으로 보고하지 않는다. iOS 15 런타임/실기기 검증 여부도 별도 표기한다.

자동 검사 기준:

- 변경 후 앱 빌드 및 앱 테스트 실행. 코어/이관은 이전 미커밋 전체를 PR로 묶는 시점에 회귀 확인.
- 이전 기록은 Core 45개, MigrationCore 64개, 앱 테스트 32개 통과, Duo UI 최종 시나리오 3개 통과다. 이는 **이전 실행 결과**이며 이번 일반 iPhone 결과로 재사용하지 않는다.
- `git diff --check`, Xcode 프로젝트 및 수정한 strings의 구문 검사.
- 이전 빌드의 `IPHONEOS_DEPLOYMENT_TARGET=15.0` override는 환경용이었다. 필요 시 사용 사실을 기록하고 프로젝트 최소 OS를 변경하지 않는다.

명령 템플릿(실제 기기 ID/결과 경로는 새 값으로 대체):

```sh
swift test --package-path HelloProteinCore --scratch-path /private/tmp/hp-iphone-core
swift test --package-path MigrationCore --scratch-path /private/tmp/hp-iphone-migration
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project ProteinTracker/ProteinTracker.xcodeproj -scheme ProteinTracker \
  -configuration Debug -destination 'platform=iOS Simulator,id=<일반-iPhone-UDID>' \
  -derivedDataPath /private/tmp/hp-iphone-build \
  -resultBundlePath /private/tmp/hp-iphone-tests-<실행별고유값>.xcresult \
  -onlyUsePackageVersionsFromResolvedFile -disableAutomaticPackageResolution \
  test CODE_SIGNING_ALLOWED=NO IPHONEOS_DEPLOYMENT_TARGET=15.0
```

기존 UI 하네스는 `docs/evidence/2026-09-30-ui-phase1/ui-harness/`에 보존돼 있다. `/private/tmp/HPPhase1UITests/` 존재에 의존하지 말고 보존본을 사용해 날짜·fixture·기기 대상으로 수정한다. 제품 타깃에 임시 테스트 메뉴를 넣지 않는다. 기존 실패 사례처럼 일부만 보이는 행을 tap해 추가 버튼을 누를 수 있으므로, 행을 온전히 노출하고 `Edit entry` 진입을 확인한 뒤 편집을 검증한다.

## 8. 제출할 화면 증거

`docs/evidence/<실행일>-iphone-ui/` 아래 기기별 폴더로 저장한다. Duo 자료는 과거 기록으로 보존하고 덮어쓰지 않는다.

최소 캡처: `home-ko.png`, `home-en.png`, `date-picker.png`, `past-records.png`, `legacy-expanded.png`, `aggregate-only.png`, `add-keyboard.png`, `edit-keyboard.png`, `total-editor.png`, `goal-reached.png`, `pending-sheet.png`, `pending-home.png`, `large-text.png`.

README에는 Xcode/SDK/런타임/기종/화면 크기, 소스 상태, fixture, 재현 명령, 기대값/실제값, 테스트 결과와 미검증을 남긴다. 합계가 캡처마다 다르면 시나리오별 데이터 차이를 설명한다.

**사용자에게 로컬 이미지를 Markdown으로 붙였을 때 두 번 표시되지 않았다.** 최종 보고에는 반드시 캡처 폴더의 절대 경로와 기능별 파일명을 제공한다. 실제 PNG를 보존하고, AI로 재생성하거나 시스템 표시를 지워 일반 iPhone처럼 만든 이미지는 제출하지 않는다.

## 9. 완료 기준 및 PR 정리

- [ ] 현재 미커밋 Phase 1 코드와 신규 파일을 보존하고 이어받음.
- [ ] 일반 iPhone 두 크기에서 실행 환경·실제 크기 확인.
- [ ] 작은 iPhone 기본 글자에서 날짜 7개가 보이고 주요 동작이 겹치지 않음.
- [ ] 추가·편집·총량 시트의 키보드와 저장 동작 정상.
- [ ] 저장/이관·pending 계약 회귀 없음.
- [ ] 실제 일반 iPhone 캡처와 실행 증거 제출. 미검증은 별도로 명시.
- [ ] Duo 대응 연기와 일반 iPhone 기준을 기존 plan/QA 기록에 반영.
- [ ] PR에 포함될 전체 diff 검토. `.DS_Store`, 임시 파일, 무관한 agents 자료 제외.

PR 설명에는 기존 Phase 1 구현과 이번 일반 iPhone 보정을 함께 묶는지 명시하고, 구체적인 전후 문제와 검증 기기를 적는다. 완료되지 않은 검사까지 ‘전체 QA 완료’로 표현하지 않는다. 원격 PR 생성/머지 여부는 인계받은 세션의 사용자 지시를 따르며, 이 문서 작성 요청 자체를 관리자 우회 병합 지시로 해석하지 않는다.

## 10. 다음 에이전트에게 전달할 지시문

> `docs/iphone-ui-correction-plan.md`를 읽고 현재 미커밋 Phase 1 구현을 보존하면서 일반 iPhone 세로 화면 보정과 검증을 진행해 주세요. Duo 동시 대응은 추후입니다. 먼저 일반 iPhone 런타임/기기를 확보하고 실제 화면을 확인한 뒤 필요한 부분만 수정하세요. 작은 iPhone과 일반 크기 iPhone에서 홈·날짜 선택·추가·수정·삭제·총량 편집·미확정 저장을 검증하고, 기능별 실제 PNG 및 절대 파일 경로를 제출해 주세요. 저장·이관·스키마·새 흐름 기본 활성화는 변경하지 마세요. 기존 Duo 결과를 일반 iPhone QA 통과 근거로 쓰지 마세요.

참고: [기존 Phase 1 계획](ui-phase1-implementation-plan.md), [공동 검토 기록](reviews/2026-09-30-ui-phase1-team-review.md), [기존 실행 증거](evidence/2026-09-30-ui-phase1/README.md), [UI 명세](ui-spec.md).

## 11. 2026-10-05 진행 결과

인계 후 같은 날 실행했다. 상세는 [실행 증거](evidence/2026-10-05-iphone-ui/README.md).

- 환경: `/Applications/Xcode.app`(26.5)로 iOS 26.5 런타임을 설치하고 iPhone SE 3세대(375×667)·iPhone 17(402×874) 전용 기기를 만들었다. 기존 iOS 27.1 런타임은 Duo 전용임을 재확인했다. Orca emulator attach는 `runtime_unavailable`로 실패해 XCTest UI 하네스로 조작했다.
- 실제 문제: 수정 전 SE에서 날짜 줄 첫/마지막 버튼이 인셋 밖으로 4.5 pt씩 잘려 스크롤됐다(§3 분석과 일치). iPhone 17과 그 외 화면(시트·달력·키보드·펼침·하단 버튼)은 수정 전에도 정상이었다.
- 보정: `DayStrip.swift`만 변경. 비접근성 글자에서는 7일 균등 폭(≥44 pt) 고정 배치, 접근성 글자에서는 기존 가로 스크롤 유지.
- 검증: 두 기기 × 시나리오 7개 통과(홈·달력·과거·펼침·총량 시트·합계 전용, 추가→목표 달성→수정→재실행→삭제, 한국어, 미확정→닫기→재확인, AX3, 시스템 다크). Core 45·Migration 64·앱 32 테스트 통과. 데이터 검산 정상.
- 미검증: 실제 VoiceOver, iOS 15 런타임·실기기, notApplied UI 주입, Duo 재검증. §9 체크리스트 중 PR 생성·머지는 사용자 지시 대기.
