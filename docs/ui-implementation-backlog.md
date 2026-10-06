# UI 후속 구현 backlog

작성 2026-09-29. 근거: [ui-audit.md](ui-audit.md), 명세: [ui-spec.md](ui-spec.md), 시안: [ui-preview/](ui-preview/README.md). 계획: [ui-direction-plan.md](ui-direction-plan.md) §F.

상태: **권장안 / 미확정**. 2026-09-30 공동 검토에 따라 Phase 1은 [상세 실행 계획](ui-phase1-implementation-plan.md)을 우선한다. 이번 홈·추가 배치, 브랜드와 테마를 확정한 뒤 적용한다. 최종 A/B 결정은 실제 내비게이션 연결 전에 수행하며 Phase 1 착수 조건이 아니다. 아직 확정되지 않은 제품 디자인을 승인으로 간주하지 않는다.

2026-10-01 구현 상태: Phase 1 홈/테마/기존 편집 화면 표현과 미확정 문구 수정을 작업 브랜치에 구현했다. [실행 증거](evidence/2026-09-30-ui-phase1/README.md)에 빌드·테스트·캡처 및 실행 제한을 기록한다. Phase 1B 확인 정책, 목표·검색·즐겨찾기·최종 내비게이션과 출시 활성화는 미구현이다. 2026-10-06: Phase 1B 확인 정책(초안 버리기·삭제 확인·미확정 닫기·조건부 복구 안내)을 [계획](ui-phase1b-editing-recovery-plan.md)대로 구현했다([실행 증거](evidence/2026-10-06-phase1b/README.md)). 인라인 입력 안내·키보드 액세서리·문의 연결은 후속으로 남는다.

공통 원칙

- 이미 검증된 저장 로직(`HelloProteinCore` `FileAppStateStore`, `MigrationCore`, `RecordHomeViewModel`의 저장·미확정·재확인 흐름)은 재작성하지 않는다. UI 단계는 뷰 계층과 문자열, 토큰만 바꾼다.
- 각 단계는 새 흐름 플래그(`-HelloProteinRenewalFlow YES`) 뒤에서만 보이며, Release 기본 활성화는 이 backlog 범위가 아니다.
- 회귀 검사의 기준선: `HelloProteinCore` 45개, `MigrationCore` 64개, iOS 앱 테스트 30개 (2026-09-28 PR #3 기준). 단계마다 이 수가 줄지 않아야 하고 UI 스냅샷·수동 확인은 별도로 기록한다.
- 시각 확인은 시안 갤러리의 같은 fixture(`-HelloProteinSeedLegacyFixture YES`)로 시뮬레이터 캡처를 남기고 `docs/evidence/<날짜>-ui-phaseN/`에 둔다.
- 검색·즐겨찾기·히스토리·설정은 기존 UIKit 화면이 새 저장소와 연결되지 않은 상태다(로드맵 "아직 해결할 사항"). 이 backlog는 새 흐름 안에 SwiftUI로 다시 만드는 순서다.

---

## 1단계. 토큰·공통 컴포넌트·기록 홈 시각 정리

전제: 이번 홈·추가 배치, 브랜드 유지 범위, 테마 범위 확정. 최종 A/B는 후속. Phase 1 뒤에는 §2의 편집·미확정·복구 UX를 Phase 1B로 먼저 진행하고 목표 설정으로 넘어간다. 날짜 탐색 확장은 별도 우선순위로 둔다.

### 1.1 색·서체·간격 토큰 도입

- 현재: 새 흐름은 SwiftUI 기본값(`.accentColor` 미정의 → 시스템 파랑, 시스템 서체, 선택은 초록 임시색). 기존 UIKit은 `Assets.xcassets/color` 에셋과 코드 내 hex를 섞어 씀.
- 목표: ui-spec §4의 의미 토큰(`bg.canvas`, `action.primary`, `ink.*`, `selection`, `danger`, `warning`)을 하나의 Swift 타입으로 정의하고 새 흐름 뷰가 그것만 참조. 다크 지원 시 같은 이름에 다크 값. 숫자용 서체 Binggrae-Bold 44pt를 `Font.custom`으로, 본문은 시스템 텍스트 스타일(Dynamic Type 자동).
- 변경 파일: `ProteinTracker/ProteinTracker/Renewal/`에 `RenewalTheme.swift`(신규), `Assets.xcassets/color/`에 새 컬러셋 추가(기존 에셋은 삭제하지 않음, 기존 UIKit 경로가 아직 쓰기 때문), `Info.plist`의 `UIAppFonts`는 이미 Binggrae 포함이므로 변경 없음. 기존 `AccentColor.colorset`은 변경하지 않고 Renewal 화면 계층에만 테마를 적용.
- 데이터 의존성: 없음.
- 시각 확인: 홈·시트·경고에서 파란색이 남지 않음. 라이트에서 크림 배경·흰 카드 구분이 보임. 큰 글자(AX3)에서 숫자 44pt가 화면을 넘지 않음(줄바꿈이 아니라 축소 허용 여부 결정).
- 회귀 검사: 앱 테스트 30개 유지. 기존 UIKit 경로(플래그 없음)의 화면이 픽셀 단위로 그대로인지 D1 캡처와 비교.

### 1.2 공통 컴포넌트

- 현재: `RecordHomePrototypeView.swift` 한 파일 안에 날짜 띠·요약·목록·시트·경고가 함께 있음.
- 목표: `DayStrip`, `DaySummary`(숫자+진행 막대+목표 줄), `LegacyTotalDisclosure`, `FoodRow`, `ActionBar`(A) 또는 `TabBar`+`FAB`(B), `NoticeBand`(warning/danger), `SheetHeader`를 분리. 동작은 그대로, 뷰만 나눔.
- 변경 파일: `Renewal/RecordHomePrototypeView.swift` 분할 → `Renewal/Components/*.swift`(신규). `RecordHomeViewModel.swift`는 건드리지 않음.
- 데이터 의존성: 없음.
- 시각 확인: 갤러리 "홈 4상태"와 1:1 비교. 행의 긴 영어 이름 2줄 말줄임, 소수 그램(`31.5 g`) 표기, 우측 정렬 tabular 숫자.
- 회귀 검사: `RecordHomeViewModelTests` 그대로 통과. 시뮬레이터 A1·A2·A4 시나리오 재캡처 시 합계·행 수 동일.

### 1.3 기록 홈 시각 적용

- 현재: 링 없음, 목표가 있는 날짜는 기존 `ProgressView` 있음, 임시 초록 선택, "Previous version total" 영문 내부 용어, 파란 "Add protein" 전폭 버튼.
- 목표: ui-spec §3.1. 진행 막대(목표 없으면 숨김, 초과 시 100% 고정 + `목표 +Ng` + 달성 배지), 선택 날짜 잉크색 캡슐, 기록 있는 날 밑줄 점, 오늘 점, 이전 합계 접힘 박스(기본 접힘, 총량 편집 링크 안에 포함), 이번에는 동작하는 단일 추가 버튼 유지, 최종 액션 바/탭은 후속. 빈 상태 문구는 오늘/과거 구분. 목표 설정 진입점 연결 전에는 설명만 표시하며 가짜 링크를 만들지 않음.
- 변경 파일: `Renewal/RecordHomePrototypeView.swift`, `Renewal/RenewalStrings.swift`, `Localization/ko.lproj`·`en.lproj` `Localizable.strings`.
- 데이터 의존성: `RecordHomeViewModel.goalState` (`.goal/.noHistory/.notSet/.needsReview/.integrityError`)를 그대로 매핑. `.integrityError`는 danger 밴드로 표시하고 숨기지 않음.
- 시각 확인: 갤러리 홈 4상태 + 과거 3상태(상세+보정, 합계만, 음수 보정)와 비교. 음수 보정값은 부호를 유지하며 정상 보정을 오류 색상으로 강제하지 않음. 영어에서 "Previous version total" 대신 확정 문구.
- 회귀 검사: 앱 테스트 유지. 시뮬레이터 A3(합계만) → A4(추가) → A5/A6(총량 편집) 재캡처, 합계 88g/75g 계산이 이전 캡처와 같음.

---

## 2단계. 날짜 탐색·과거 기록·편집 시트·복구 UX

### 2.1 날짜 탐색

- 현재: 주간 띠 좌우 화살표, 달력 시트(`DatePicker`), "Today" 버튼. 선택 상태는 프로세스 내 유지, 재실행 시 오늘.
- 목표: 띠 스와이프(주 단위), 달력은 히스토리 화면으로 통합(2.4/5.1 전까지는 기존 달력 시트 유지), 오늘 버튼은 오늘 선택 중 비활성. 자정 넘김 시 `refreshToday()`로 오늘 점만 갱신하고 선택 날짜는 유지.
- 변경 파일: `Renewal/Components/DayStrip.swift`, `RecordHomePrototypeView.swift`.
- 데이터 의존성: `RecordHomeViewModel.visibleDays`(±3일) → 주 단위(일~토)로 바꾸려면 VM에 `weekDays(containing:)` 추가. 저장 로직 무관.
- 시각 확인: 큰 글자에서 7칸이 한 줄에 유지되는지(AX3에서 요일 라벨 생략 허용). 영어 요일 1글자, 한국어 1글자.
- 회귀 검사: `RecordHomeViewModelTests`의 날짜 선택·경계(2000-01-01, 미래 제한) 테스트 통과. 자정 경계 테스트 추가.

### 2.2 추가/편집 시트

- 현재: 이름·단백질 텍스트필드, 저장 실패 경고 후 시트 유지, 저장 중 취소·저장 비활성, 미확정 시 필드 잠금(`saveUnconfirmed`). 검증 오류는 경고창.
- 목표: ui-spec §3.2. 날짜 읽기 전용 행(시트 연 시점 고정), 검증 오류 인라인(필드 아래 danger 문구, 경고창 없음), 키보드 위 저장 액세서리, 취소 시 입력 있으면 버리기 확인, 삭제는 편집 시트 하단 danger 텍스트 버튼 + 확인. 저장 중 스피너 밴드.
- 변경 파일: `RecordHomePrototypeView.swift`의 시트 부분 → `Renewal/RecordEditorSheet.swift`(신규), `RenewalStrings.swift`, strings.
- 데이터 의존성: `ActionError.input(ProteinInputError)`의 6개 케이스(`empty`, `notANumber`, `groupingSeparatorNotAllowed`, `tooManyFractionDigits`, `notPositive`, `overflow`)를 각각 인라인 문구로 매핑(합치지 않음). `addRecord(id:)`의 세션 고정 ID 유지.
- 시각 확인: 갤러리 "추가 5상태"(직접 입력+키보드, 검증 오류, 저장 중, 실패, 편집). 한국어·영어 모두 키보드 열린 상태에서 필드가 가려지지 않음.
- 회귀 검사: 앱 테스트 중 저장 실패·재시도 중복 없음 테스트 통과. 시뮬레이터 C1→C3(실패 후 성공) 재캡처.

### 2.3 미확정 저장 UX

- 현재: 경고창 + 시트 유지 + 필드 잠금 + "저장 결과 확인" 버튼, 홈 배너, 모든 저장 거부. 미반영이면 입력 유지.
- 목표: 동작 변경 없음(미확정 중 취소 허용, 초안 미보존은 현재 동작 유지). 닫기 중재가 추가되는 UX 변경이며 저장 계약은 유지. Phase 1에는 초안 미보존 상시 안내와 홈/시트 미반영 문구 정확성 수정만 포함하고, 확인창은 Phase 1B에서 완료. ui-spec §3.3: 미확정 중 취소·스와이프 시 "입력한 내용은 남지 않아요" 확인 대화상자 추가, 시트 안 warning 밴드(경고창 대신 1회 안내 후 밴드 상주), 잠긴 필드는 chip 배경, 홈 배너에 "저장 결과 확인" 링크, 재확인 실패는 밴드 유지 + 짧은 경고, 미반영은 입력 재개 안내.
- 변경 파일: `RecordEditorSheet.swift`, `Components/NoticeBand.swift`, `RecordHomePrototypeView.swift`(배너).
- 데이터 의존성: `PendingSave.operationID`, `ActionError.unconfirmed/.notApplied`, `reconfirm()` 그대로.
- 시각 확인: 갤러리 "미확정 4상태". 잠금 중 ＋·행·총량 편집이 비활성으로 보임.
- 회귀 검사: `RecordHomeViewModelTests`의 unconfirmed/reconfirm/notApplied/cross-instance 테스트 통과. 시뮬레이터 S1–S3e(`-HelloProteinFailAfterReplaceOnce`) 재캡처.

### 2.4 이전 합계·총량 편집

- 현재: 요약 아래 항상 펼쳐진 섹션, "Edit daily total" 링크, 시트에서 signed 총량 입력.
- 목표: 접힘 박스(합계만 있는 날은 힌트 문구 포함), 총량 편집 시트에 계산 설명 각주, 음수 결과 허용 문구.
- 변경 파일: `Components/LegacyTotalDisclosure.swift`, `Renewal/LegacyTotalSheet.swift`(신규).
- 데이터 의존성: `DailyLog.hasLegacyTotal`, `LegacyAggregate`, `setLegacyTotal` 그대로. 상세 없는 날에 가짜 행을 만들지 않음.
- 시각 확인: 갤러리 "합계 전용 · 하루 총량 수정". 접힘 상태에서 총량 편집 진입이 2탭 이내.
- 회귀 검사: 음수 보정 저장·재저장 테스트 통과. 시뮬레이터 A5/A6 재캡처.

### 2.5 복구·로딩 화면

- 현재: `RecoveryViewController`(UIKit)에 재시도만 있고 상세는 DEBUG 전용. 로딩은 `LaunchLoadingViewController`.
- 목표: 토큰 적용(크림 배경, 제목 20pt, 본문 시스템), 상태별 문구(재시도 가능/이관 기록 손상+백업 있음/재시도로 해결 안 됨), 재시도 불가 상태는 danger 밴드 + 문의 링크(기존 QnA 경로 재사용). 삭제·초기화 버튼은 계속 없음.
- 변경 파일: `Migration/RecoveryViewController.swift`, `Migration/LaunchLoadingViewController.swift`, strings.
- 데이터 의존성: `MigrationCoordinator`의 복구 상태(`storeCorrupt`, `storeUnsupportedSchema`, `evidenceCorrupt/Unreadable/Unsupported`, `backupAvailable`)를 문구로 매핑. 상태 추가·의미 변경 없음.
- 시각 확인: 갤러리 "복구 3상태". 큰 글자에서 버튼이 스크롤 아래로 밀리지 않음.
- 회귀 검사: `MigrationCore` 64개 유지. 시뮬레이터 R1(손상 저장소) 재캡처, B2/B4(중단 후 재실행) 경로 동일.

---

## 3단계. 목표 설정/수정과 목표 이력

### 3.1 목표 화면 (설정 → 하루 목표)

- 현재: 새 흐름에 목표 편집 없음. 기존 UIKit `SettingTargetViewController`는 UserDefaults `targetProtein`에 씀(새 저장소와 무관).
- 목표: ui-spec §3.4. 현재 목표·적용 시작일 표시, 새 목표 입력(양수, 소수 허용 여부는 `ProteinInput` 규칙 따름), "오늘부터 적용" 고정 문구, 잘못된 기존 값(`needsReview`)은 원문 표시 후 새 입력 요구, 목표 없음 상태.
- 변경 파일: `Renewal/GoalEditorView.swift`(신규), `RecordHomeViewModel.swift`에 `setGoal(text:completion:)` 추가(기존 `perform` 경로 재사용, 새 저장 경로 없음), 저장은 기존 `AppState.replaceGoal(on:with:)`(같은 날 재설정은 이 API의 교체 규칙을 따름)를 쓰고 새 API를 만들지 않음.
- 데이터 의존성: `GoalHistory.validate`(중복 시작일 거부), `state.goal(on:)`. 과거 시작일 추정 금지: 시작일은 항상 오늘(기기 시간대 `CalendarDay.today`).
- 시각 확인: 갤러리 "목표 4상태". 잘못된 기존 값 화면에서 원문이 그대로 보이고 임의 숫자로 치환되지 않음.
- 회귀 검사: `HelloProteinCore` 목표 이력 테스트(같은 날 두 번 설정 시 `replaceGoal` 동작을 UI 문구가 그대로 반영하는지), VM 테스트에 목표 설정 후 `goalState` 전이 추가. 저장 실패·미확정 경로가 목표 저장에도 동일하게 적용되는지 테스트.

### 3.2 계산기 시트

- 현재: 기존 `Calculator.swift`(kg × 1.2/1.4/1.6)와 `InitViewController` 단일 화면. 새 흐름에 없음.
- 목표: 목표 화면과 온보딩에서 여는 시트. 몸무게(kg/lb 선택은 미결정 → kg만), 활동량 3단계, 결과 소수 1자리, "목표로 사용" 시 3.1 입력란에 채움(저장은 3.1 경로). 임신·수유·고령 옵션은 근거 확인 전 미포함.
- 변경 파일: `Renewal/GoalCalculatorSheet.swift`(신규), `Calculator.swift` 재사용(수정 없음).
- 데이터 의존성: 없음(계산만).
- 시각 확인: 갤러리 "목표 · 계산기 시트". 영어에서 활동량 라벨 폭.
- 회귀 검사: `Calculator` 단위 테스트 추가(68kg 보통 → 95.2).

### 3.3 홈 목표 진입점

- 현재: 없음.
- 목표: 목표 없음/검토 필요 상태에서만 홈 요약에 "목표 설정" 링크. 목표가 있으면 설정 경유만.
- 변경 파일: `Components/DaySummary.swift`.
- 데이터 의존성: `goalState`.
- 시각 확인: 갤러리 "홈 · 목표 없음".
- 회귀 검사: 없음(내비게이션만).

### 3.4 온보딩 (신규 설치만)

- 현재: `MigrationCoordinator`의 명시적 새 설치 판정 후 바로 홈. 기존 `Init.storyboard`는 기존 경로 전용.
- 목표: 새 설치 판정일 때만 목표 입력 1화면(워드마크 헤더, 계산기 링크, 건너뛰기 없음 여부 미결정 → 시안은 건너뛰기 없음). 이관 사용자는 절대 보지 않음.
- 변경 파일: `Renewal/OnboardingGoalView.swift`(신규), `Migration/RenewalLaunchGate.swift`(분기 1줄), `Renewal/RenewalPrototypeFactory.swift`.
- 데이터 의존성: 새 설치 판정 결과만. 온보딩 완료 여부를 별도 플래그로 저장하지 않고 "목표 이력 비어 있음 + 이관 증거 없음"으로 판단.
- 시각 확인: 갤러리 "온보딩". 워드마크 대비(크림 글자+잉크 외곽선 on 민트).
- 회귀 검사: `RenewalLaunchPolicyTests`·`MigrationRealmEndToEndTests`에서 이관 사용자가 온보딩으로 가지 않는 테스트 추가. D1(신규 설치) 재캡처.

---

## 4단계. 즐겨찾기·검색·다중 추가

### 4.1 추가 시트 탭 구조

- 현재: 직접 입력만.
- 목표: 직접 입력/검색/즐겨찾기 3탭. 시트 헤더의 날짜는 세 탭 공통, 저장 버튼은 직접 입력 탭에서만, 검색·즐겨찾기는 하단 "N개 · Ng 추가" 버튼.
- 변경 파일: `Renewal/RecordEditorSheet.swift` → `Renewal/AddSheet.swift`(탭 컨테이너) + `ManualEntryTab.swift`.
- 데이터 의존성: 없음.
- 시각 확인: 갤러리 "추가 · 직접 입력" 헤더가 탭 추가 후에도 동일.
- 회귀 검사: 2.2·2.3의 테스트 그대로 통과.

### 4.2 즐겨찾기

- 현재: 새 저장소 `AppState.favorites`에 이관된 데이터가 있으나 UI 없음. 기존 UIKit은 별도 Realm.
- 목표: 목록(이름·g), 다중 선택, 직접 입력 탭의 ★ 저장, 편집 시트의 ★ 토글, 스와이프 삭제. 즐겨찾기 개수 제한 없음(기존 사용자에게 새 제한 금지).
- 변경 파일: `Renewal/FavoritesTab.swift`(신규), `RecordHomeViewModel.swift`에 `favorites`, `addFavorite/removeFavorite`, `addRecords(from:)`(한 커밋에 여러 행) 추가, `HelloProteinCore` `AppState.favorites` 조작 API 확인.
- 데이터 의존성: 이관된 `favorites`의 ID 규칙(`legacy:favorite:<id>`), 다중 추가는 **한 번의 `modify`** 로 커밋(부분 성공 없음). 미확정 시 동일 잠금.
- 시각 확인: 갤러리 "즐겨찾기 · 비어 있음/목록". 긴 이름 말줄임.
- 회귀 검사: 다중 추가 실패 시 0행 추가·입력 유지 테스트, 재시도 중복 없음(행마다 세션 고정 ID) 테스트. `MigrationCore` 즐겨찾기 매핑 테스트 유지.

### 4.3 검색

- 현재: 기존 UIKit `SearchViewController`가 KO는 외부 API, EN은 로컬 `Protein-En.json`을 **키워드와 무관하게** 반환(감사 §1의 버그). 새 흐름에 없음.
- 목표: 검색 공급자 프로토콜(`FoodSearchProvider`)로 KO API/EN 로컬을 분리, EN 로컬은 키워드 필터 구현(버그 수정), 결과 다중 선택, 100g당 표기, 최근 검색(`AppState.searchHistory`) 표시. 네트워크 실패는 danger 밴드 + 재시도, 오프라인 문구.
- 변경 파일: `Renewal/SearchTab.swift`(신규), `Renewal/Search/FoodSearchProvider.swift`·`LocalEnglishFoodSearch.swift`·`KoreanAPIFoodSearch.swift`(신규, 기존 `SearchViewController`의 요청 코드를 옮기되 UI와 분리), `RecordHomeViewModel.swift`에 검색 이력 저장.
- 데이터 의존성: `AppState.searchHistory`, 설정의 검색 언어(현재 UserDefaults `searchLanguage` → 새 저장소 `settings`로 옮기는 매핑은 `MigrationCore`에 이미 있는지 확인, 없으면 5.2에서).
- 시각 확인: 갤러리 "검색 · 여러 항목 선택". 영어 결과의 긴 이름, 소수 g.
- 회귀 검사: EN 로컬 검색 키워드 필터 단위 테스트(기존 동작 "모두 반환"이 사라졌음을 명시). 검색 결과 추가가 4.2와 같은 다중 커밋 경로를 쓰는지 테스트.

---

## 5단계. 히스토리·설정 완성 및 출시 전 검증

### 5.1 히스토리 (캘린더/그래프)

- 현재: 새 흐름에 없음. 기존 `StatsViewController`는 Charts 주간 막대, 기존 Realm `StatProtein`.
- 목표: ui-spec §3.6. 캘린더(기록 있음 ●, 합계만 ◯), 주간 막대 + 목표선(그 주 각 날짜의 목표 이력), 기록한 날 평균, 날짜 탭 → 홈으로 복귀하며 선택. 새 저장소만 읽음.
- 변경 파일: `Renewal/HistoryView.swift`(신규), `Renewal/HistoryViewModel.swift`(신규, 읽기 전용), Swift Charts(iOS 16+) 사용 시 iOS 15 fallback 결정 필요 → 15 지원이면 직접 그린 막대.
- 데이터 의존성: `AppState.logs` 전체 순회, 목표선은 날짜별 `state.goal(on:)`(그 주 전부 이력이 없으면 목표선 없음, 현재 목표를 과거 주에 소급하지 않음). 쓰기 없음.
- 시각 확인: 갤러리 "히스토리 2상태". 다크에서 막대·목표선 대비.
- 회귀 검사: 주간 합계가 홈 합계와 같은 계산(`totalProteinCentigrams`)을 쓰는지 테스트. 이관 fixture(목표 2026-09-28부터)에서 9/21–27 주에 목표선이 없고 9/28 주에 있는지 테스트. 이관 fixture(9/20 합계만, 9/23 상세)에서 ◯/● 구분 테스트.

### 5.2 설정

- 현재: 새 흐름에 없음. 기존 `SettingViewController` 4항목(목표/언어/문의/오픈소스), UserDefaults 기반.
- 목표: 같은 4항목 + "데이터" 정보 행(이관 완료·백업 유무, 읽기 전용). 검색 언어는 새 저장소 `settings`에 저장. 오픈소스 목록은 새 흐름 의존성으로 갱신(Charts·Realm 등 제거 여부는 실제 의존성 기준).
- 변경 파일: `Renewal/SettingsView.swift`(신규), `Renewal/OpenSourceView.swift`(기존 `InfoOpenSourceViewController` 목록 재사용), `RecordHomeViewModel.swift` 또는 별도 `SettingsViewModel`에 언어 저장(`perform` 경로).
- 데이터 의존성: `AppState.settings`(`searchLanguage`, `goalNeedsReview`, `legacyTargetRaw`), `MigrationCoordinator` 증거 조회(백업 존재 여부는 `EvidenceInspection` 결과 재사용, 파일을 다시 열지 않음).
- 시각 확인: 갤러리 "설정". 워드마크 푸터, 큰 글자에서 행 높이.
- 회귀 검사: 언어 변경이 검색 공급자 선택에 반영되는 테스트. 설정 저장도 미확정 잠금을 따르는 테스트.

### 5.3 내비게이션 최종 연결

- 현재: 홈 단일 화면 + 시트.
- 목표: 구조 A(홈 + 액션 바 → 히스토리·설정은 push, 뒤로 가기 시 선택 날짜 유지) 또는 B(3탭, 탭 전환 시 홈 선택 날짜 유지). 히스토리 날짜 선택 → 홈 pop + `select(day)`.
- 변경 파일: `Renewal/RenewalRootView.swift`(신규), `RenewalPrototypeFactory.swift`.
- 데이터 의존성: 없음. 선택 날짜는 프로세스 내 상태.
- 시각 확인: 시안 권장안 흐름과 동일하게 히스토리 → 날짜 → 홈이 1탭.
- 회귀 검사: 히스토리에서 돌아온 뒤 미확정 배너·잠금이 유지되는지 테스트(VM 단일 인스턴스 보장).

### 5.4 출시 전 검증 (플래그 제거 전)

- 현재: 새 흐름은 플래그 뒤. 2026-10-05 iOS 26.5 시뮬레이터 iPhone SE 3세대·iPhone 17에서 홈·시트·AX3·시스템 다크 시나리오를 통과([증거](evidence/2026-10-05-iphone-ui/README.md)). 이전 Duo 결과는 근거로 쓰지 않는다.
- 목표: 다음을 실행하고 `docs/evidence/<날짜>-ui-release-check/`에 남긴다. 통과 전에는 Release 기본 활성화를 하지 않는다.
  - 한국어·영어 × 기본·AX3 글자 × 라이트·(다크 지원 시) 다크에서 홈·추가·미확정·목표·히스토리·설정·복구 캡처.
  - VoiceOver로 날짜 띠(날짜 전체 읽기), ＋(날짜 포함 라벨), 진행 막대(퍼센트), 잠긴 필드(비활성 안내) 확인.
  - 색 대비를 실제 렌더 캡처에서 측정(계산값 6.45/6.39/5.71 등을 측정으로 대체).
  - 작은 화면(iPhone SE 3세대) 키보드 열린 상태 — 2026-10-05 추가·수정·총량 시트에서 확인. 영어 AX3·한국어 다크·실기기는 남음.
  - 기존 사용자 이관 시나리오 A/B/C/S 전체 재실행, 실기기 1대 이상.
- 변경 파일: 없음(문서·증거만). 통과 후 별도 결정으로 `RenewalLaunchPolicy` 기본값 변경.
- 데이터 의존성: 합성 fixture + 실제 배포 데이터 파일 1건(로드맵 미검증 항목).
- 시각 확인: 위 캡처 전부.
- 회귀 검사: 세 패키지 테스트 전체 + 시뮬레이터 증거 재생성. 실패가 하나라도 있으면 플래그 제거 금지.

---

## 단계 밖으로 둔 것

- Android·AI 입력·결제·광고: 계획 §4 제외.
- 프로젝트 최소 OS 13 → 15 변경: 별도 결정.
- 기존 UIKit 화면 삭제: 새 흐름 기본 활성화 이후.
- `FileRecordRepository` 등 미사용 코드 정리: 리뷰에서 남긴 항목, UI 단계와 무관.
