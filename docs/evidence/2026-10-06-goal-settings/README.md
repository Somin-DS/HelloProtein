# 2026-10-06 목표 설정·목표 이력 실행 증거

[목표 설정 계획](../../goal-settings-implementation-plan.md)의 구현 결과다. 브랜치 `feat/renewal-goal-settings`(main `e6acbed` 기준). 아래는 실제로 실행한 것만 적고, 실행하지 않은 것은 미검증으로 남긴다. 사용자 지시로 시뮬레이터 실행은 아래 범위에서 중단했다.

## 환경

- macOS, Xcode 26.5(`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`), iOS 26.5 시뮬레이터 런타임.
- 기기: `HelloProtein iPhone SE`(375×667 @2x, `AF20D47C-C440-470E-91D6-6380CEA5F9CB`), `HelloProtein iPhone 17`(402×874 @3x, `8C3433BA-B9F6-4283-A7EE-DCCCF74A4982`). Phase 1B 이후 누적된 합성 fixture 상태 그대로 사용(이전 목표: `legacy:goal:targetProtein` 2026-10-05 120 g).
- 앱: Debug 빌드 `/private/tmp/hp-iphone-build/Build/Products/Debug-iphonesimulator/ProteinTracker.app`(최종 코드, 17:08 빌드). 코드 리뷰 반영 전 빌드로 돌린 1차 배치 결과는 아래 “1차 배치”에 따로 적는다.
- 하네스: `ui-harness/`(Smoke.swift 테스트 21–30 추가, `run-test.sh`, `goal-fixture-run.sh`, `recovery-run.sh`, `test-recovery-run.py`). 설치된 앱에 bundle id로 attach하는 XCTest UI 테스트. 원본은 `/private/tmp/hp-iphone-ui/`.

## 자동 검사 (최종 코드 기준)

| 검사 | 결과 |
| --- | --- |
| `HelloProteinCore` `swift test` | 45 tests, 0 failures |
| `MigrationCore` `swift test` | 64 tests, 0 failures |
| 앱 유닛 테스트(`xcodebuild test`, SE 시뮬레이터) | 68 tests, 0 failures (`/private/tmp/hp-goal-tests-170857.log`) — 목표 VM 테스트 8개 포함 |
| Debug 빌드 | 성공 (`/private/tmp/hp-goal-build3.log`) |
| Release 빌드 | 성공 (`/private/tmp/hp-goal-release3.log`). Release 바이너리 `strings -a`에서 `HelloProteinSaveOutcomeOnce`·`HelloProteinSaveDelaySeconds`·`HelloProteinAdvanceDayAfterSeconds`·`SaveOutcomeInjectingStore`·`HelloProteinFailAfterReplaceOnce` 모두 0건, 대조 문자열 `renewal.goal.entry`·`renewal_goal_update_date`는 2건씩 존재 |
| `git diff --check` | 공백 오류 없음 |

유닛 테스트에서 처음 실패 1건은 테스트 기대값 오류였다(`"-5"`는 `ProteinInput.parse` 설계상 `.notANumber`이지 `.notPositive`가 아님). 코드가 아니라 테스트를 고쳤다.

### 새 VM 테스트가 고정하는 계약

- 첫 목표는 오늘부터 적용되고 이전 날짜는 이력 없음 그대로.
- 같은 날 두 번 저장 → 그날 항목 하나 교체, 다음 날은 이전 목표 유지(`replaceGoal`, 날짜당 1개).
- 저장과 `goalNeedsReview=false`가 같은 `modify`(commit)에서 이뤄지고 `legacyTargetRaw`는 보존.
- 같은 값은 쓰기 없는 no-op, 단 검토 flag가 남아 있으면 저장 허용.
- 날짜가 바뀐 세션의 저장은 쓰기 없이 `.goalDateChanged`로 거부, 명시적 갱신 후 성공.
- 입력 오류·쓰기 전 실패는 `modifyCalls == 0`.
- 미확정 저장 중 거부, `notApplied` 후 1회 재시도.
- 실제 `afterReplace` 실패 후 재확인은 원래 날짜로 적용(자정 넘어도).

## UI 시나리오 (최종 빌드)

run label `goal-final`. 결과 번들 `/private/tmp/hp-iphone-ui/results/goal-final-*.xcresult`.

| # | 시나리오 | 기대 | SE | 17 |
| --- | --- | --- | --- | --- |
| 21 | 오늘 목표 변경(131.5)→홈 반영, 어제 선택 시 진입 없음·목표 유지, 같은 날 125로 재저장 시 이력에 오늘 항목 1개(“현재 적용 중”) | 통과 | 통과(재실행 `goal-final-se-171334`) | 미검증(아래 참고) |
| 22 | 초안 버리기 확인, 입력 오류(“abc”) 알림, 쓰기 없음 | 통과 | 통과 | 통과 |
| 26 | `-HelloProteinFailAfterReplaceOnce`(실제 afterReplace 실패) → 미확정 → 재확인 → 적용 확인 | 통과 | 통과 | 통과 |
| 27 | `-HelloProteinSaveOutcomeOnce notApplied`(DEBUG 대역) → 미적용 안내, 재시도 | 통과 | 통과 | 통과 |
| 28 | `-HelloProteinSaveOutcomeOnce readFailure`(DEBUG 대역) → 재확인 실패 중립 문구 → 재시도 시 복구 | 통과 | 통과 | 통과 |
| 29 | `-HelloProteinSaveDelaySeconds 8`(DEBUG 대역) → 처리 중 취소·저장·입력 비활성, 스와이프 차단, 완료 후 닫힘 | 통과 | 통과 | 미검증(signal term으로 중단, 재실행은 사용자 지시로 중단) |
| 30 | 한국어 + AX-XL 목표 시트 열기·이력·버리기 | 통과 | 통과 | 통과 |
| 13 | 기존 기록 시트의 재확인 읽기 실패 → `.reconfirmFailed` 중립 문구 | 통과 | 통과 | 통과 |

SE 최종 배치(`goal-final-se-170936`)는 8개 중 7개 통과, 21번은 하네스 기대값 오류(어제 기준값을 오늘 문구와 비교)로 실패 → 하네스 수정 후 단독 재실행 통과. 17 최종 배치(`goal-final-17-171109`)는 8개 중 6개 통과: 21번은 같은 하네스 오류, 29번은 signal term. 수정된 하네스로 17 재실행을 시작했으나 사용자 지시로 중단했다.

### 실행하지 않음 (미검증)

- 23 목표 없음(빈 goals), 24 이관 검토(`goalNeedsReview=true`, 원문 “120 grams”), 25 자정 경과(`-HelloProteinAdvanceDayAfterSeconds`): `goal-fixture-run.sh`는 작성했지만 두 기기 모두 실행하지 않았다. 해당 경로는 VM 테스트로만 확인됐다(검토 flag 정리, 자정 거부·갱신 후 저장).
- iOS 15 실기기, 실기기 전반, VoiceOver 실제 탐색, 다크 모드.
- 시트 자체 로직(`prefill`, `isUnchangedValue`, `isStale`)의 단위 테스트 없음(리뷰 L4).

### 1차 배치 (리뷰 반영 전 빌드, label `goal`)

- SE: 5/8 통과. 21번 — DisclosureGroup에 둔 `accessibilityIdentifier`가 모든 행으로 전파돼 날짜별 행 식별자가 가려짐(앱 수정: 식별자를 라벨로 이동). 29번 — 4초 지연이 부하 상태 SE에서 스와이프 전에 끝남(하네스: 8초). 30번 — SE+AX-XL에서 진입 버튼이 하단 추가 버튼(`safeAreaInset`) 뒤에 있어 탭이 추가 시트를 열었음(하네스: 추가 버튼 위로 드래그 후 탭). 사용자는 스크롤로 접근 가능하므로 앱은 바꾸지 않았다.
- 17: 6/8 통과(21·29 동일 원인, 30 통과).

## 캡처

`iphone-se/`(19장), `iphone-17/`(16장; `goal-busy`·`goal-history-replaced`·`past-goal-preserved` 없음 — 21·29 미통과). 원본 `/private/tmp/hp-iphone-ui/out/goal-final/HelloProtein-iPhone-{SE,17}/`.

| 파일 | 내용 |
| --- | --- |
| goal-existing | 시트 초기: 현재 목표·적용일·프리필, 같은 값이라 저장 비활성 |
| goal-history | 이력 펼침(내림차순, 현재 적용 중 표시) |
| goal-keyboard | 131.5 입력, 저장 활성 |
| goal-changed-home | 홈 “목표 131.5g” |
| past-goal-preserved | 어제 선택: 진입 없음, 이전 목표 그대로 |
| goal-history-replaced | 같은 날 125로 재저장 후 이력에 오늘 항목 1개 |
| goal-input-error | “abc” 입력 오류 알림 |
| goal-discard | 초안 버리기 확인 |
| goal-pending / goal-pending-confirmed | 실제 afterReplace 실패 → 미확정 → 재확인 후 적용 |
| goal-not-applied | DEBUG `notApplied` 대역 → 미적용 안내 |
| goal-read-failure | DEBUG `readFailure` 대역 → 재확인 실패 중립 문구 |
| goal-busy | DEBUG 지연 대역 → 처리 중 잠금 |
| goal-ko-ax3(-history/-keyboard/-discard) | 한국어 AX-XL |
| reconfirm-read-failed / -recovered | 기록 시트 재확인 읽기 실패·복구(13) |

## 코드 리뷰 반영

`oh-my-claudecode:code-reviewer`(opus) 리뷰: 차단 결함 없음. 반영한 항목 — M1 `try?`가 내부 옵셔널을 평탄화해 이력 읽기 오류가 “아직 목표 없음”으로 보이던 문제(`Result`로 교체), M2 오류 문구의 빈 괄호, L2 검토 대기 중에는 홈 진입 라벨을 “목표 설정”으로, L5 로드맵 모순 문구. 남긴 항목 — L1 반복되는 재확인 읽기 실패에 상세 노출, L3 시트 내 자정 감지는 저장·전면 복귀 시점(계획 허용), L4 시트 로직 단위 테스트.

## 저장 계약

schema·commit 경로·이관 판정·`legacyTargetRaw`·플래그 기본값·최소 OS 변경 없음(`HelloProteinCore`·`MigrationCore` diff 없음). 새 DEBUG 인자 3개와 `SaveOutcomeInjectingStore`는 `#if DEBUG` 안에만 있고 Release 바이너리에 문자열이 없음(위 표).
