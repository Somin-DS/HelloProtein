# PR #7 수정·검증 (2026-10-07)

기준 앱 소스: `7adc73f`. 제품 코드 변경 없이 목표 검증 하네스의 두 리뷰 지적을 수정했다.

- `goal-fixture-run.sh`: 첫 테스트 실패 코드를 보존하고 나머지 검사·원본 복원 후 해당 코드로 종료. 준비/파일 작업 오류는 중단하며 EXIT/INT/TERM에서 복원한다. 실행별 백업 파일을 유지한다. SIGKILL·전원 차단은 trap 대상이 아니다.
- `Smoke.swift/test25GoalDateChanged`: 날짜 갱신 후에는 과거 홈에 목표 진입점이 없어야 한다. 과거 목표 보존, 오늘 이동 후 새 목표 142g와 적용일을 재확인하도록 수정했다. 앱 진입 전에 테스트 시계가 넘어갈 가능성을 줄이기 위해 clock 전환은 실행 30초 후, 입력 후 대기는 31초로 설정했다.

## 이번에 실행한 검증

- `python3 docs/evidence/2026-10-06-goal-settings/ui-harness/test-goal-fixture-run.py`: 3개 테스트 통과. 전체 성공·각 단계 실패·복수 실패·TERM 중단·백업 실패의 7개 경우와 원본 바이트 보존을 검사했다. 실제 시뮬레이터 대신 임시 파일/명령 대역을 사용했다.
- `zsh -n`과 `git diff --check` 통과.
- 현재 앱 Debug 빌드 성공: `/private/tmp/hp-pr7-review-build.log`.
- Xcode `/Applications/Xcode.app`, iOS 26.5. 두 기기에 최신 Debug 앱 설치 후 기존 합성 fixture만 변경했다.

| 기기 | 목표 없음(23) | 이관 검토 원문(24) | 자정·명시 갱신·과거 보존(25) | 원본 복원 SHA-256 앞부분 |
| --- | --- | --- | --- | --- |
| SE 3세대 | 통과 | 통과 | 통과 | `11fdec5932c9810f` |
| iPhone 17 | 통과 | 통과 | 통과 | `efb4f076220c8b1d` |

각 경우는 1개 테스트/실패 0/스킵 0이다. 실행별 xcresult는 `/private/tmp/hp-iphone-ui/results/`의 `pr7-review-se-143351`, `pr7-review-se-143432`, `pr7-review-se-143455`, `pr7-review-17-143621`, `pr7-review-17-143652`, `pr7-review-17-143715`다. 스크립트 종료 후 두 기기의 app-state.json이 실행 전 백업과 `cmp`로 일치했다. 실행 명령은 수정한 `goal-fixture-run.sh se pr7-review`, `goal-fixture-run.sh 17 pr7-review`다.

## 캡처와 남은 한계

기기별 8개 캡처는 `iphone-se/`, `iphone-17/`에 있다. 절대 경로: `/Users/somin/orca/HelloProtein/docs/evidence/2026-10-07-pr7-review/`.

이 검증으로 이전 증거의 목표 없음·이관 검토·자정 미검증 3건을 해소했다. 이전 iPhone 17의 시나리오 21·29 재실행, iOS 15·실기기·VoiceOver·다크 모드 검증은 수행하지 않았다. 제품 코드가 바뀌지 않아 기존 앱 68/Core 45/Migration 64 테스트와 Release 빌드는 재실행하지 않았다. 이번 UI 6개와 기존 테스트 결과를 구분한다. 기본 활성화나 출시는 하지 않았다.
