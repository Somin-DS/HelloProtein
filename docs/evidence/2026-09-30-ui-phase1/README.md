# 기록 홈 Phase 1 구현·검증

> 2026-10-05: 이 기록의 실행 증거는 iPhone Duo 런타임에서 얻은 것이며 일반 iPhone 검증을 대체하지 않는다. 일반 iPhone(SE 3세대·iPhone 17) 보정과 검증은 [2026-10-05-iphone-ui](../2026-10-05-iphone-ui/README.md)를 본다. Duo 동시 대응은 연기됐다.

작업 시작 2026-09-30, 재개·검증 2026-10-01 (Asia/Seoul). 브랜치 `feat/renewal-home-phase1`, 기준 main `d6ad3dd0f42643bc53c4814cdd037ea65d5c59dd`.

## 구현 범위

- Renewal 전용 크림 배경·민트 보조색·진한 녹색 주요 동작, 라이트 테마. 기존 UIKit 전역 자산/appearance는 변경하지 않음.
- 날짜 줄, 섭취 요약, 음식 행, 레거시 합계 disclosure를 표시 전용 컴포넌트로 추출. 작은 폭·큰 글자에서는 날짜 가로 스크롤, 음식 행 세로 배치 가능.
- 기존 `@StateObject`, 편집 대상 날짜·record ID·입력·pending 수명 및 저장/재확인 경로 유지. `RecordHomeViewModel`, 코어, 이관 소스 변경 없음.
- 목표가 있는 날짜에만 진행률/달성/초과 표시. 진행률은 0~1로 제한하고 실제 합계·초과량은 정수로 유지.
- 가져온 원본, 음식 합계, signed 보정, 현재 합계 구분. 음수 보정을 정상 값으로 표시. 원본 정보가 없는 데이터에 ‘가져온 원본’ 라벨을 붙이지 않음.
- 기존 음식/총량 편집 화면 스타일 정리. 미확정 중 초안 미보존 안내 상시 표시. 홈/시트 공통 미반영 문구를 초안 보존을 약속하지 않는 중립 안내로 수정.
- Figma 원본 재접속이나 최종 A/B 승인 없이 기존 검토·권장안에 따라 구현. 사용자의 직접 작업 위임을 적용했으며 최종 내비게이션·다크 지원·Phase 1B 확인창·출시 활성화는 제외.

## 실행 환경과 데이터

- Xcode: `/Users/somin/Downloads/Xcode.app`, SDK/런타임 iOS 27.1.
- 전용 기기: `HelloProtein Phase1`, UDID `7C8B0A11-773C-456A-A50E-B51824EB6D63`, iPhone Duo. 유일하게 생성 가능한 설치 런타임의 기기였음. iPhone SE/16e/18 Pro 생성은 incompatible device로 실패.
- 이 기기의 합성 데이터만 사용. `-HelloProteinRenewalFlow YES -HelloProteinSeedLegacyFixture YES`로 최초 1회 준비. 추가 설치·재실행은 기존 컨테이너 유지. 사용자 실데이터·원본 앱 설치는 조작하지 않음.
- 시드: 2026-09-23 음식 10+35g, 보정10g, 원본55g; 09-20 합계70g; 09-21 합계0g; 09-22 합계15g. 즐겨찾기2, 검색이력2. 목표120g의 실제 이관 시작일은09-30.
- 작업 중 날짜가 바뀌었음. before는09-30 선택, after는10-01 선택이며 모두 상세 없는0g/목표120g 상태. 날짜까지 고정한 픽셀 비교라고 주장하지 않음.
- PostScript name을 TTF name table에서 확인: `Binggrae-Bold`.

## 빌드와 자동 테스트

| 검사 | 결과 | 증거 |
| --- | --- | --- |
| 변경 전 앱 빌드 | 통과, exit0 | `/private/tmp/helloprotein-ui-phase1-before.log` |
| 변경 후 및 마지막 표시 보완 빌드 | 통과, exit0 | 아래 명령, 기존 SearchViewController의 optional→Any 경고 잔존 |
| HelloProteinCore | 45개 통과, exit0 | 실제 2026-10-01 실행 |
| MigrationCore | 64개 통과, exit0 | 실제 2026-10-01 실행 |
| 앱 통합/VM/표시 계산 | 32개 통과, 실패0/스킵0, exit0 | `/private/tmp/helloprotein-ui-phase1-tests.xcresult` |
| 프로젝트/한영 strings 구문 | plutil 통과 | 3개 파일 검사 |
| diff 공백 검사 | 통과 | `git diff --check` |

새 테스트 2개는 초과량/진행률, 음수와 Int64 경계값의 표시 계산을 검증한다. 마지막 비활성 색상·라벨 보완은 계산/VM 계약을 바꾸지 않으며 빌드와 UI 테스트로 확인한다.

```sh
swift test --package-path HelloProteinCore --scratch-path /private/tmp/helloprotein-ui-phase1-core
swift test --package-path MigrationCore --scratch-path /private/tmp/helloprotein-ui-phase1-migration
xcodebuild -project ProteinTracker/ProteinTracker.xcodeproj -scheme ProteinTracker \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/helloprotein-ui-phase1-baseline \
  -onlyUsePackageVersionsFromResolvedFile -disableAutomaticPackageResolution \
  build CODE_SIGNING_ALLOWED=NO IPHONEOS_DEPLOYMENT_TARGET=15.0 -quiet
xcodebuild -project ProteinTracker/ProteinTracker.xcodeproj -scheme ProteinTracker \
  -configuration Debug -destination 'platform=iOS Simulator,id=7C8B0A11-773C-456A-A50E-B51824EB6D63' \
  -derivedDataPath /private/tmp/helloprotein-ui-phase1-baseline \
  -resultBundlePath /private/tmp/helloprotein-ui-phase1-tests.xcresult \
  -onlyUsePackageVersionsFromResolvedFile -disableAutomaticPackageResolution \
  test CODE_SIGNING_ALLOWED=NO IPHONEOS_DEPLOYMENT_TARGET=15.0
```

명령의 iOS15 override는 빌드 환경용이며 프로젝트 최소 OS 변경이 아니다. 앱 통합 테스트는 UI 터치 테스트와 별개다.

## 화면 증거

- [변경 전 영어 홈](before-en.png), [변경 후 영어 홈](after-en.png).
- [한국어·시스템 다크에서 라이트 홈](after-ko-system-dark.png).
- [한국어 접근성 글자 AX3](after-ko-ax3.png): 날짜 가로 스크롤, 본문 세로 스크롤, 고정 추가 버튼. 작은 iPhone에서의 별도 검증은 아님.
- [과거 상세/보정](past-before-edit.png), [레거시 펼침](legacy-expanded.png), [총량 편집](total-editor.png), [키보드 입력](entry-keyboard.png).
- [미확정 시트](pending-sheet.png), [닫은 뒤 홈](pending-home.png), [재확인 뒤 기록](pending-confirmed.png).

미확정 최초 캡처에서 잠긴 버튼/필드의 시각적 차이가 약한 점을 발견했다. 루트 강제 글자색을 제거하고 잠금 opacity를 추가했다. UI의 `.isEnabled` 검사는 이 수정 전에도 잠금으로 통과했으며, 마지막 수정은 시각 구별을 보강한다. 저장된 pending PNG는 보완 후 재검증 캡처로 교체했다.

## UI 시나리오와 도구 제한

Orca emulator는 `SimulatorKit.framework` 부재로 연결 실패했고, 현재 Xcode에는 Simulator.app도 없어 데스크톱 창 검증이 불가능했다. 대체로 설치된 앱을 XCTest가 직접 조작하는 별도 임시 프로젝트 `/private/tmp/HPPhase1UITests/Smoke.xcodeproj`를 만들었다. 제품 target에 디버그 메뉴/오류 상태 분기를 추가하지 않았다. 기존 교체 후 오류 주입 인자만 사용했다.

초기 UI 시나리오 `/private/tmp/helloprotein-ui-smoke.xcresult`는 2개 중 미확정 흐름은 통과, 과거 편집 흐름은 실패했다. 첫 재검증에서도 실패했다. 접근성 트리의 행이 하단 고정 추가 버튼에 걸친 상태에서 tap이 추가 동작으로 전달됐고, 저장소에는 기존18g 행과 이름 없는20g 신규 행이 함께 있었다. 편집 화면 진입을 확인하지 않은 하네스 문제였다. 행을 충분히 스크롤하고 `Edit entry` 제목·20g 입력·커밋된 행을 확인한 뒤 종료하도록 수정한 최종 시나리오는 통과했다. 제품 저장 코드는 이 실패 때문에 변경하지 않았다.

| 최종 UI 시나리오 | 실제 확인 | 결과 번들 |
| --- | --- | --- |
| 과거 편집 | 09-23 선택 → 원본/보정 펼침 → 총량60 저장 →18g 추가 →20g 수정 → 앱 종료/재실행 →20g 확인 → 삭제 | `/private/tmp/helloprotein-ui-smoke-final.xcresult`, 1개 통과, exit0 |
| 목표·합계 전용 | 오늘31.5g에100.5g 추가 →132g/목표120g/초과12g 표시, 09-20 합계70g/목표 이력 없음 | `/private/tmp/helloprotein-ui-smoke-states.xcresult`, 아래와 함께2개 통과, exit0 |
| 미확정 | 교체 후 오류 주입 → 알림 → 필드 잠금 → 취소 → 홈 추가 잠금 → 읽기 재확인 → 신규 행 표시·잠금 해제 | 같은 states 번들, 실패0/스킵0 |

[목표 초과](goal-132-over-120.png), [합계 전용70g](aggregate-only-70.png), [수정 후 커밋](entry-edit-committed.png), [삭제 후](past-after-delete.png)와 최종 pending 캡처를 보관한다. 실제 VoiceOver 대신 XCTest의 접근성 쿼리와 탭·입력으로 수행했다. 총32개 앱 테스트와 별도로 UI 시나리오3개가 통과한 것이며 초기 실패를 통과로 덮어쓰지 않는다.

하네스는 [ui-harness](ui-harness/Smoke.swift)에 증거로 보존했다. 제품 타깃에는 포함되지 않는다. 전용 합성 시뮬레이터에 앱을 설치한 뒤 사용하는 일회성 재현 자료다. 기존 검사 후 데이터가 누적되므로 그대로 재실행해 목표132g 같은 기대값을 가정하면 안 된다. 날짜09-23/09-20도 고정이며 today10-01 기준으로 주 이동을 사용한다. 새 실행은 고립된 fixture와 날짜를 맞춰야 한다.

```sh
xcodebuild -project /private/tmp/HPPhase1UITests/Smoke.xcodeproj -scheme Smoke \
  -destination 'platform=iOS Simulator,id=7C8B0A11-773C-456A-A50E-B51824EB6D63' \
  -derivedDataPath /private/tmp/HPPhase1UITests/build \
  -resultBundlePath /private/tmp/helloprotein-ui-smoke-final.xcresult \
  -only-testing:Smoke/Smoke/testPastEntryAndLegacyTotal test -quiet
# 별도 states 번들에서 나머지 두 메서드를 -only-testing으로 실행.
```

UI 실행 뒤 디스크 파일을 직접 검사했다([검산 결과](data-check.json)). 09-23 원본55g은 유지됐고, 상세121g·보정-61g으로 현재60g이다. 테스트에서 삭제한 `Phase1 UI verified` 행은 없고, 마지막 미확정 저장 `Pending UI final`은 정확히1행이며 전체 record ID에 중복이 없다. 합계 전용70g·즐겨찾기2·검색이력2도 유지됐다.

### 미검증 및 후속 조건

- 실제 VoiceOver 초점 이동·발화. XCTest의 접근성 조회는 VoiceOver 사용성 검증이 아님.
- 일반 소형 iPhone, iOS15 런타임, 실기기에서의 전 상태 확인.
- 미반영(notApplied)/재확인 읽기 실패의 **UI 주입**. VM 자동 테스트 통과와 구분. 홈 미반영 문구는 한영 소스에서 확인.
- 모든 fixture의 한영×큰 글자×키보드 전체 조합, UIKit 기존 화면의 전후 캡처, 실제 사용자 데이터 이관.
- 최종 시각 승인·Phase 1B 닫기 확인 정책·기존 기능 연결·출시 전 검증이 남아 있음. 배포/기본 활성화/머지하지 않음.

필수 미검증이 있으므로 ‘Phase 1 전체 QA 완료’ 또는 ‘출시 준비 완료’로 보고하지 않는다.
