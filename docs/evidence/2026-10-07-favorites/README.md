# 2026-10-07 즐겨찾기 연결(A단계) 실행 증거

[즐겨찾기·검색 계획](../../favorites-search-implementation-plan.md)의 A단계 구현 결과다. 브랜치 `feat/renewal-favorites-a`(main `c4ab644` 기준). B단계(검색 탭·공급자·최근 검색·검색 언어)는 구현하지 않았다. 아래는 실제로 실행한 것만 적고, 실행하지 않은 것은 미검증으로 남긴다.

## 환경

- macOS, Xcode 26.5(`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`), iOS 26.5 시뮬레이터 런타임.
- 기기: `HelloProtein iPhone SE`(375×667 @2x, `AF20D47C-C440-470E-91D6-6380CEA5F9CB`), `HelloProtein iPhone 17`(402×874 @3x, `8C3433BA-B9F6-4283-A7EE-DCCCF74A4982`). 이전 PR들에서 누적된 합성 fixture 상태 그대로 사용. 이관 즐겨찾기: `legacy:favorite:…400a` 닭가슴살 23 g(position 0), `…400b` 그릭요거트 9 g(position 1). 이번 실행으로 오늘(2026-10-07)에 기록이 누적됐다(SE 14행 등).
- 앱: Debug 빌드 `/private/tmp/hp-iphone-build/Build/Products/Debug-iphonesimulator/ProteinTracker.app`(최종 코드). 코드 리뷰 반영 전 빌드로 돌린 17 1차 배치는 아래에 따로 적는다.
- 하네스: `ui-harness/`(Smoke.swift 테스트 31–38 추가, `run-test.sh`, `favorites-fixture-run.sh`). 설치된 앱에 bundle id로 attach하는 XCTest UI 테스트. 원본 `/private/tmp/hp-iphone-ui/`.

## 자동 검사 (최종 코드)

| 검사 | 결과 |
| --- | --- |
| `HelloProteinCore` `swift test` | 56 tests, 0 failures (`FavoriteCollectionTests` 11개 추가) |
| `MigrationCore` `swift test` | 64 tests, 0 failures |
| 앱 유닛 테스트(`xcodebuild test`, SE) | 84 tests, 0 failures (`/private/tmp/hp-fav-tests-155623.log`) — VM 즐겨찾기 테스트 7개, `AddSheetPolicyTests` 9개 추가 |
| Debug 빌드 | 성공 (`/private/tmp/hp-fav-build3.log`) |
| Release 빌드 | 성공 (`/private/tmp/hp-fav-release.log`). `strings -a`에서 DEBUG 주입 문자열 5종 0건, 대조 `renewal.favorite.addSelected`·`renewal_favorite_add_count` 2건씩 |
| `git diff --check` | 공백 오류 없음 |

유닛 테스트 첫 실행의 실패 1건은 기존 테스트가 `PendingSave`를 `kind` 없이 만들던 기대값 문제였다(`.unknown` 기본값 vs 실제 `.record`). 테스트 기대값을 고쳤다.

### 테스트가 고정하는 계약

- Core: position 오름차순 표시, 추가는 checked max+1(overflow일 때만 순서 보존 재번호), 정확히 같은 trim 이름·양만 재사용(대소문자·공백 내부 미정규화, position 낮은 것), 편집은 ID·position·legacySourceID 보존, 삭제는 해당 ID만, 0·음수 값은 기록 양 없음, batch는 빈 선택·중복·변경·삭제·음수·합계 overflow에 전체 실패, `setFavorites` 검증 실패 시 롤백.
- VM: 기록+즐겨찾기 한 `modify`(`modifyCalls == 1`), 즐겨찾기 쪽 실패(ID 충돌) 시 기록도 미반영, 미확정→notApplied→같은 ID 재시도 시 기록 1·즐겨찾기 1, 중복은 `.alreadyExisted`로 기록만 저장, 편집·삭제는 일일 로그 불변, 다중 추가는 시트의 고정 날짜에 한 commit, 선택 이후 바뀐 항목·음수는 `.selectionChanged`로 0행, 미확정 재시도 시 record ID 동일, `PendingSave.kind`가 record/favoriteBatch/favoriteEdit/favoriteDelete를 구분, 실제 afterReplace 실패 중에는 즐겨찾기 관리도 차단되고 읽기 성공 후 해제.
- 시트 정책(pure): 같은 탭 no-op, busy/pending 차단, dirty일 때만 확인, 즐겨찾기 toggle도 dirty, 선택이 있을 때만 편집 전 확인, 추가 버튼은 선택·잠금·합계 조건, 양수만 선택 가능, record ID 세션 고정, 확정 후처리(record/batch 닫기, edit 목록 복귀, delete 머묾).

## UI 시나리오 (최종 빌드)

run label `fav-final`. 결과 번들 `/private/tmp/hp-iphone-ui/results/fav-final-*.xcresult`.

| # | 시나리오 | SE | 17 |
| --- | --- | --- | --- |
| 31 | 이관 즐겨찾기 position 순 표시, 2개 선택(해제·재선택 포함) → “2개 선택 · 32 g” → 한 번에 추가, 홈 행 +1씩 | 통과 | 통과 |
| 32 | 직접 입력 + ‘즐겨찾기에도 저장’ → 즐겨찾기 생성; 같은 이름·양 재입력 → 기록 저장 + ‘이미 즐겨찾기에 있어요’ 알림, 즐겨찾기 1개 유지 | 통과 | 통과 |
| 33 | dirty 탭 전환 확인(머무르기 → 입력 유지, 버리고 이동 → 초안만 삭제), 선택 후 전환 시 선택 삭제, 즐겨찾기 삭제 확인(저장된 이름·양 표시) 후 시트 유지·기록 유지 | 통과 | 통과 |
| 34 | fixture 변형(빈 이름 −5 g, zero 0 g, Edit me): 원문 그대로 표시·선택 불가·안내, 편집으로 “Fixed 5 g” 수정 후 선택 가능, 선택 중 편집 진입 시 선택 버리기 확인 | 통과(`favorites-fixture-run.sh`, 원본 바이트 복원 확인) | 통과(동일) |
| 35 | `-HelloProteinFailAfterReplaceOnce`(실제 afterReplace 실패) 다중 추가 → 미확정, 탭·입력 잠금 → 재확인 → 시트 닫힘, 홈 행 +1 | 통과 | 통과 |
| 36 | `-HelloProteinSaveOutcomeOnce readFailure`(DEBUG 대역) 즐겨찾기 편집 → 미확정 → 재확인 실패 중립 문구 → 재확인 성공 → 목록 복귀, 시트 유지 | 통과 | 통과 |
| 37 | `-HelloProteinSaveOutcomeOnce notApplied`(DEBUG 대역) 즐겨찾기 삭제 → 미확정 → 미적용 → 행 유지·시트 유지 → 재삭제 성공, 기록 유지 | 통과(재실행 `fav-final-se-160833`) | 통과 |
| 38 | 한국어 + AX-XL 즐겨찾기 탭·선택·버리기 확인 | 통과 | 통과 |

- 17 1차 배치(리뷰 반영 전 빌드, label `fav`): 5/7. 35·37은 홈 행 개수를 세는 하네스가 `LazyVStack` 아래쪽(화면 밖) 행을 못 세던 문제였고, 디스크 상태(app-state.json)에서는 두 경우 모두 기대대로였다(배치 기록 존재, 삭제 후 기록 유지). 하네스에 스크롤 후 집계(`homeRowCount`)를 넣었다. SE 최종 배치에서도 37이 같은 이유로 1회 실패(5회 스크롤 조기 종료) → 10회 스크롤로 고친 뒤 단독 재실행 통과.
- 기존 추가 시트 회귀 subset(label `fav-regress`, 1·2·4·7·9·10·11·12·17·18): 두 기기 모두 8/10. 2는 누적된 날의 합계를 전제한 옛 문구 기대값, 4는 Phase 1B 이전의 닫기 흐름(미확정 닫기 확인 없이 닫힘)을 전제한 옛 테스트로, 코드 회귀가 아니라 하네스 전제의 문제였다. 두 테스트를 현재 동작(합계 문구 대신 새 행 확인, 미확정 닫기 확인 → 닫기 → 홈 재확인, 삭제 확인 알림)에 맞게 고치고 식품명에 실행별 접미사를 붙인 뒤(같은 날에 남은 이전 실행의 행이 `CONTAINS` 집계에 섞이는 문제) 재실행: 2·4 모두 SE·17 통과(`fav-regress2-*` 4 통과, `fav-regress3-*` 2 통과). 중간 재실행의 실패 2건(행 2개 집계, 삭제 확인 미처리)은 모두 시뮬레이터 상태 파일에서 이전 실행 잔여 행으로 확인했다.

### 실행하지 않음 (미검증)

- iOS 15 실기기, 실기기 전반, VoiceOver 실제 탐색, 다크 모드.
- 즐겨찾기 position overflow·합계 overflow는 유닛 테스트로만 확인했다.
- 작성자와 분리된 사람 QA는 없었다(코드 리뷰 에이전트와 하네스 실행만).
- B단계 전체(검색·최근 검색·검색 언어).

## 캡처

`iphone-se/`(19장), `iphone-17/`(19장). 원본 `/private/tmp/hp-iphone-ui/out/fav-final/HelloProtein-iPhone-{SE,17}/`(SE의 `favorite-invalid/edit/edited`는 동시 실행된 다른 label 때문에 `out/fav-regress/HelloProtein-iPhone-SE/`에 기록됨).

| 파일 | 내용 |
| --- | --- |
| favorites-list / favorites-selected / favorites-added-home | 목록, 2개 선택 요약, 추가 후 홈 |
| favorite-created / favorite-exists | 직접 입력에서 생성된 즐겨찾기, 중복 알림 |
| tab-switch-prompt / favorite-delete-prompt / favorite-deleted | 탭 전환 확인, 삭제 확인(저장값), 삭제 후 목록 |
| favorite-invalid / favorite-edit / favorite-edited | 빈 이름·음수·0 표시와 선택 불가, 편집 모드, 수정 후 |
| favorites-pending / favorites-pending-confirmed | 실제 afterReplace 실패 미확정, 재확인 후 홈 |
| favorite-edit-read-failed / favorite-edit-pending-confirmed | DEBUG readFailure 대역, 재확인 성공 후 목록 복귀 |
| favorite-delete-not-applied | DEBUG notApplied 대역 후 행 유지 |
| favorites-ko-ax3(-selected/-discard) | 한국어 AX-XL |

## 코드 리뷰 반영

`oh-my-claudecode:code-reviewer`(opus): 차단 결함 없음. 반영 — 즐겨찾기 쪽 실패 시 기록 미반영·미확정 재시도 테스트 추가, 확정 후처리를 `AddSheetPolicy.afterConfirmed`로 분리해 테스트, 중복 알림 OK의 dismiss를 alert 종료 후로 지연, 편집 취소를 미확정 중 잠금, 삭제 확정 후 선택에서 제거, `%ld` 포맷·미사용 키 정리, 문서 주석. 남긴 항목 — `updateFavorite`가 이름을 항상 trim(새 기록과 같은 검증 규칙), 변경 없는 편집 저장도 쓰기, `pruneStaleSelections`가 마지막 확정 상태 기준(아래 PR #8 후속 수정에서 해결).

## 저장 계약

schema·commit 경로·이관 판정·`legacySourceID`·플래그 기본값·최소 OS 변경 없음(`MigrationCore` diff 없음, `HelloProteinCore`는 순수 helper와 `AppState.setFavorites`만 추가). 무료 즐겨찾기 개수 제한 없음. DEBUG 인자는 기존 것만 사용했고 Release 바이너리에 문자열 없음(위 표).

## PR #8 리뷰 후속 수정

- 선택한 즐겨찾기가 저장소에서 수정·삭제되어 배치가 거부되면, 최신 상태를 다시 읽고 VM을 갱신한 뒤 `.selectionChanged`를 전달한다. 시트의 선택 정리와 재선택이 최신 값으로 동작한다. 실패한 배치나 갱신은 쓰기를 수행하지 않는다.
- 갱신 읽기 실패는 저장소 오류로 전달하고 기존 화면·초안·선택을 유지한다. 미확정 저장으로 취급하지 않으며, 재시도에서 읽기가 회복되면 재선택할 수 있다.
- 회귀 테스트 2개 추가: 별도 저장소 writer의 수정/삭제 후 실패 콜백 이전 목록 갱신 및 동일 record ID 재선택 성공; 읽기 실패 후 상태 보존·쓰기 없음·재시도 성공.
- 검증: iPhone SE / iOS 26.5 시뮬레이터 앱 테스트 **86개 통과, 0 실패**, Debug 빌드 성공. 로그 `/private/tmp/hp-pr8-fix-tests.log`, 결과 `/private/tmp/hp-iphone-build/Logs/Test/Test-ProteinTracker-2026.10.07_19-12-07-+0900.xcresult`. 앞선 리뷰에서 Core 56개 통과. 이번 후속 수정에서는 UI 하네스·Release 빌드를 다시 실행하지 않았다.
