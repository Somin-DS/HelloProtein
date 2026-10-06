# Phase 1B 편집 확인·미확정 닫기·복구 안내 실행 증거

실행일: 2026-10-06. 브랜치: `feat/renewal-phase1b-editing`(기준 main `64b9688`). 계획: [Phase 1B 계획](../../ui-phase1b-editing-recovery-plan.md).

캡처 절대 경로: `/Users/somin/orca/HelloProtein/docs/evidence/2026-10-06-phase1b/iphone-se/`, `/Users/somin/orca/HelloProtein/docs/evidence/2026-10-06-phase1b/iphone-17/`. 모든 PNG는 XCTest 하네스가 저장한 원본이며 가공하지 않았다.

## 환경

| 항목 | 값 |
| --- | --- |
| Xcode | 26.5 (`/Applications/Xcode.app`, 명령별 `DEVELOPER_DIR`) |
| 런타임 | iOS 26.5 시뮬레이터 |
| 기기 | iPhone SE 3세대 `AF20D47C-C440-470E-91D6-6380CEA5F9CB` (375×667 @2x), iPhone 17 `8C3433BA-B9F6-4283-A7EE-DCCCF74A4982` (402×874 @3x) |
| 데이터 | `-HelloProteinSeedLegacyFixture YES`로 2026-10-05에 심은 합성 픽스처. 이전 실행의 기록이 누적돼 있어 각 시나리오는 실행 시각 접미사가 붙은 고유 이름으로 행을 만들고 그 행만 검사한다. 실제 사용자 데이터·Duo 기기는 건드리지 않았다 |
| 실행 경로 | `-HelloProteinRenewalFlow YES` (기본값은 그대로 꺼짐) |

## 자동 검사

| 검사 | 결과 | 근거 |
| --- | --- | --- |
| 앱 Debug 빌드 (iPhone 17) | exit 0, 새 경고 없음(기존 SearchViewController 경고만) | `/private/tmp/hp-phase1b-build.log` |
| 앱 테스트 타깃 (iPhone 17) | 60개 통과, 실패 0, 스킵 0 | `/private/tmp/hp-phase1b-tests-140822.xcresult` |
| HelloProteinCore / MigrationCore `swift test` | 45개 / 64개 통과, 실패 0 | 콘솔 출력 |
| 앱 Release 빌드 | exit 0 | `/private/tmp/hp-phase1b-release.log` |
| Release 바이너리 문자열 | `HelloProteinSaveOutcomeOnce`, `HelloProteinFailAfterReplaceOnce`, `HelloProteinSeedLegacyFixture`, `SaveOutcomeInjectingStore`, `simulated reconfirm read failure` 모두 0회. 대조로 `renewal_delete_confirm_target` 2회, `recovery.retry` 4회 | `strings -a` |
| `git diff --check`, `plutil -lint` (en/ko strings, pbxproj) | 통과 | — |

새 단위 테스트:

- `EditorDismissPolicyTests`: 변경 감지(신규 빈 입력, 기존 기록·총량, 공백·형식 변경, 잘못된 숫자, 원래 문자열 복귀), 닫기 우선순위(busy > pending > dirty > clean), 확인 버튼 시점 재검사, 삭제 1회 보장, 삭제 대상 문구(이름/직접 입력·날짜·저장된 양), 한영 키 존재와 미확정 닫기 문구의 확정 표현 금지.
- `SheetDismissAdapterTests`: 시트 delegate 인수·SwiftUI delegate 전달·두 판단 결합·재부착 무루프·해제 시 원래 delegate 복원.
- `RecoveryViewControllerTests`: 원본 보존/백업 문장 플래그 조건, 재시도 안내·버튼은 `canRetry && retry`일 때만, 연속 탭 1회 실행, unsupportedOS, Release 상세 숨김, 큰 글씨 줄바꿈.
- `RecordHomeViewModelTests` 추가 4개: 확인된 삭제는 쓰기 1회, 미반영 대역에서 삭제 후 재확인 시 행 유지·재삭제 가능, 읽기 실패 대역에서 pending 유지 후 다음 읽기로 한 번만 반영, 대역은 첫 쓰기에만 작용.

## UI 시나리오 (XCTest 하네스, 두 기기)

하네스: [`ui-harness/Smoke.swift`](ui-harness/Smoke.swift). 실행: `run-test.sh <se|17> phase1b <tests…>`, 복구는 `recovery-run.sh <se|17> phase1b`.

| 시나리오 | 준비 | 기대값 | SE | 17 |
| --- | --- | --- | --- | --- |
| test7 음식 기록 버리기 | 오늘, 추가 시트 | 빈 시트는 취소·스와이프 모두 확인 없이 닫힘, 스와이프로 닫은 뒤 다시 열림. 입력 후 취소·스와이프는 "Discard changes?", 계속 입력은 입력 유지, 버리기는 행 0개, 다시 열면 초안 없음 | 통과 | 통과 |
| test8 하루 총량 버리기 | 09-23 보정 펼침 → 총량 편집 | 빈 닫기 무확인, 한 글자 입력 후 지우면 다시 clean, 입력 후 취소·스와이프 확인, 버리기 후 총량 원래 값 | 통과 | 통과(1차 실행은 러너가 signal term으로 종료, 단독 재실행 통과) |
| test9 삭제 확인 | 12.5 g 행 추가 → 편집에서 양을 99로 바꾼 뒤 삭제 | 확인창에 `이름 · 날짜 · 12.5 g`(입력란 99가 아닌 저장값), 취소는 시트·입력 유지·행 1개, 확인은 행 0개이고 추가 확인창 없이 닫힘 | 통과 | 통과 |
| test10 미확정 닫기(실제 afterReplace) | `-HelloProteinFailAfterReplaceOnce YES` | 저장 후 미확정, 취소는 미확정 닫기 확인(버리기 문구 아님), 머무르기는 시트·입력 유지, 스와이프도 같은 확인, 닫기 후 홈 배너·추가 잠금, 홈 재확인으로 행 1개 | 통과 | 통과 |
| test11 미반영(시트) | `-HelloProteinSaveOutcomeOnce notApplied` (DEBUG 대역) | 시트 재확인 → "Not saved", 잠금 해제·입력 유지, 다시 저장 시 같은 record ID로 행 1개 | 통과(1차는 시뮬레이터 재실행 불안정, 단독 재실행 통과) | 통과 |
| test12 미반영(홈) | 같은 대역, 시트 닫은 뒤 홈에서 재확인 | 중립 미반영 안내, 추가 잠금 해제, 행 0개, 시트를 다시 열어도 초안 복원 없음 | 통과 | 통과 |
| test13 재확인 읽기 실패 | `-HelloProteinSaveOutcomeOnce readFailure` (DEBUG 대역, 실제 쓰기는 됨) | 첫 재확인 실패 경고, 입력·잠금·미확정 유지, 닫기는 미확정 확인, 두 번째 재확인에서 시트가 스스로 닫히고 행 1개 | 통과(1차는 앱 실행 시간 초과, 단독 재실행 통과) | 통과 |
| test17 한국어 AX3 확인창 | 한국어, `UICTContentSizeCategoryAccessibilityXL` | 버리기·삭제 확인창 선택지가 탭 가능하고 실제 탭 결과 확인 | 통과(1차는 재실행 인자 미적용으로 영어 홈, 단독 재실행 통과) | 통과 |
| test18 한국어 미확정 닫기 | 한국어, 실제 afterReplace | 미확정 닫기 확인 → 닫기 → 홈 배너 → 재확인 행 1개 | 통과 | 통과 |
| test14/19 복구 재시도 가능 (영어, 한국어 AX3) | `app-state.json`을 잘린 JSON으로 덮어씀 → `storeCorrupt`, `canRetry` true | 제목 "Unable to open your entries", 원본 보존·백업 문장, 재시도 안내와 44 pt 이상 버튼, 탭하면 시작 판정 재실행 후 새 복구 화면 | 통과 | 통과 |
| test15/20 복구 재시도 불가 (영어, 한국어 AX3) | `schemaVersion` 99 → `storeUnsupportedSchema`, `canRetry` false | 재시도 버튼·안내 없음, 홈 없음 | 통과 | 통과 |
| test16 복구 후 정상 | 원래 파일 바이트 복원(`cmp` 일치) | 홈 정상 진입 | 통과 | 통과 |

복구 시나리오는 시뮬레이터 컨테이너 안 합성 픽스처의 `app-state.json`만 바꿨다. 실행 전 바이트를 복사해 두고 끝에 되돌렸으며 SHA-256 앞자리는 SE `feb4160fe00e769b`, iPhone 17 `34b99cc015e320e4`로 각각 실행 전후 같았다. iPhone 17 첫 복구 실행은 시뮬레이터가 꺼져 있어 컨테이너를 찾지 못했고 아무 파일도 바꾸지 않은 채 실패했다. 스크립트에 부팅과 컨테이너 확인을 넣은 뒤 재실행해 통과했다. 이관 증거·원본 Realm·백업은 건드리지 않았다.

## 캡처

| 파일 | 내용 |
| --- | --- |
| `discard-entry.png`, `discard-entry-swipe.png` | 음식 시트 입력 후 취소·스와이프의 버리기 확인 (같은 확인창이라 화면이 같다) |
| `discard-entry-home.png` | 버린 뒤 홈, 행 없음 |
| `discard-total.png` | 하루 총량 시트의 버리기 확인 |
| `delete-confirm.png`, `delete-done.png` | 저장값으로 설명한 삭제 확인, 삭제 후 홈 |
| `pending-close.png`, `pending-close-swipe.png` | 실제 afterReplace 미확정에서 취소·스와이프의 미확정 닫기 확인 |
| `pending-home.png`, `pending-confirmed.png` | 닫은 뒤 홈 배너, 재확인 후 행 1개 |
| `not-applied-sheet.png`, `not-applied-saved.png` | 대역 미반영 시트 안내, 재저장 후 행 1개 |
| `not-applied-home.png` | 대역 미반영 홈 안내 |
| `reconfirm-read-failed.png`, `reconfirm-read-recovered.png` | 대역 읽기 실패 경고와 미확정 유지, 다음 재확인 후 행 1개 |
| `discard-entry-ko-ax3.png`, `delete-confirm-ko-ax3.png` | 한국어 AX3 확인창 |
| `pending-close-ko.png`, `pending-home-ko.png` | 한국어 미확정 닫기와 홈 배너 |
| `recovery-retry.png`, `recovery-retry-ko-ax3.png` | 재시도 가능 복구 화면 (Debug라 하단에 원시 상세가 보임, Release는 종류 코드만) |
| `recovery-no-retry.png`, `recovery-no-retry-ko-ax3.png` | 재시도 불가 복구 화면 |
| `recovery-restored-home.png` | 파일 복원 후 정상 홈 |

## 미반영·읽기 실패 검증의 구분

- `-HelloProteinFailAfterReplaceOnce`는 실제 파일 교체 뒤 실패를 만든다. 재확인은 실제 파일을 읽어 반영됨을 확인한다(test10, test18).
- `-HelloProteinSaveOutcomeOnce notApplied|readFailure`는 DEBUG 전용 저장소 대역이다. UI 상태 계약 검증용이며 디스크 내구성 검증이 아니다. `notApplied`는 파일에 쓰지 않고 미확정을 보고하고, `readFailure`는 실제로 쓴 뒤 미확정을 보고하고 다음 읽기를 한 번 실패시킨다. 이관 commit에는 쓰이지 않으며 Release에는 없다.

## 리뷰

작성자와 분리한 코드 리뷰 에이전트가 diff를 검토했다. 차단 의견은 없었다. 반영한 것은 다음과 같다.

- 삭제 확인 직후 삭제를 다음 런루프로 미뤄 확인창 닫힘과 겹치지 않게 했다.
- 스와이프 판단에 SwiftUI 자체 판단을 결합했다.
- `adaptivePresentationStyle` 재정의를 제거했다.
- 전달 대상 delegate를 부착 중 강하게 보관해 해제 경합을 막았다.
- 부착 실패 시 DEBUG 로그를 남긴다.
- adapter 단위 테스트를 추가했다.

반영하지 않은 것은 다음과 같다.

- 확인창이 닫히는 동안 제목이 잠깐 빈 문자열이 될 수 있다(외관상 LOW).
- unsupportedOS 화면도 새 제목을 쓴다. 본문은 기존 지원 OS 안내를 유지한다.

## 미검증·한계

- iOS 15 런타임, 실기기, VoiceOver 초점·발화(확인창 뒤 편집 필드·홈 진입 버튼으로의 초점 복귀 포함). 320 pt 폭.
- 처리 중(busy) 취소·스와이프·삭제 차단은 정책·단위 테스트와 기존 `interactiveDismissDisabled`로만 확인했다. 저장이 매우 빨라 UI에서 busy 구간을 잡지 못했다.
- 재확인 읽기 실패 경고는 기존 저장 오류 문구("Your input and existing entries are unchanged")를 그대로 쓴다. 읽기 실패 상황에 맞는 별도 문구는 후속이다.
- 영어 AX3 확인창, 다크 모드의 새 확인창 캡처.
- 프로세스 종료 후 재실행은 기존 test2·VM 테스트 범위만 확인했다. pending과 초안은 메모리 상태이며 재실행 시 복원을 약속하지 않는다.

필수 미검증이 남아 있으므로 "전체 QA 완료"가 아니다.

## PR #6 리뷰 후 하네스 수정

복구 테스트의 앞 단계 실패가 마지막 홈 테스트 성공으로 가려지던 문제를 수정했다. 첫 실패 코드를 보존하고 나머지 검증과 파일 복원을 수행한 뒤 해당 코드로 종료한다. 준비·파일 작업 실패는 즉시 중단하며, EXIT/INT/TERM 정리에서 원본 복원을 시도한다. 백업은 실행마다 별도 파일에 보관하고 복원 실패 시 경로를 출력한다.

`python3 docs/evidence/2026-10-06-phase1b/ui-harness/test-recovery-run.py`로 실제 시뮬레이터 대신 임시 JSON·명령 대역을 사용했다. 전체 성공, 각 3단계 실패, 복수 실패, TERM 중단, 백업 실패의 7개 경우를 담은 3개 테스트가 통과했다. 모든 경우 원본 바이트 보존도 검사했다. `zsh -n`과 `git diff --check` 통과. 이번 수정은 하네스에 한정돼 앱 빌드·UI 시나리오는 재실행하지 않았다. SIGKILL·전원 차단에는 trap이 실행되지 않으므로 남은 백업으로 수동 복원해야 한다.
