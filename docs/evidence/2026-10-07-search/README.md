# 2026-10-07 검색 연결(B단계) 실행 증거

[음식 검색 연결 구현 계획](../../search-implementation-plan.md)의 구현 결과다. 브랜치 `feat/renewal-search-b`(main `6d61319` 기준). 공급자 근거는 [B0 공급자 검증](../2026-10-07-search-provider/README.md)에 따로 있다. 실제로 실행한 것만 적고, 실행하지 않은 것은 미검증으로 남긴다. 실행은 2026-10-07 19:55 KST에 시작해 2026-10-08 오전까지 이어졌다(캡처의 ‘October 8’은 그 때문이다).

## 완료 범위 (정직한 요약)

| 항목 | 상태 |
| --- | --- |
| 영어 검색(내장 USDA SR Legacy 카탈로그) | 후속 수정: 공식 원본과 정확 일치한 2,196행만 기준량 검증됨. 나머지 136행은 자동 추가 차단. [수정 기록](../2026-10-08-search-correction/README.md). |
| 한국어 검색 | **미구현(사용 불가 상태만 연결).** 레거시 식약처 `I2790`이 종료돼(ERROR-310) 네트워크 호출 없이 ‘지금은 검색을 사용할 수 없어요’와 영어 전환 안내만 보여준다. 후속 공급자(공공데이터포털 15127578)는 계정·키·계약 확인이 필요한 사용자 결정 사항. |
| 최근 검색 | 구현·검증. 실행한 검색어를 앞으로 이동(trim 후 정확히 같은 항목 재사용), 0..재번호, ID로 삭제(확인 알림), 빈 레거시 항목은 ‘(빈 검색어)’로 표시·선택 불가. |
| 검색 언어 저장 | 구현·검증. raw `Korean(한글)`/`English(영어)` 저장, 같은 확정 언어면 쓰기 없음, 선택이 있으면 버리기 확인, 확정 후에만 결과·선택 초기화. |
| 미확정 저장 처리 | 구현·검증. 이력 저장 미확정 중에도 조회 1회는 진행, 결과 열람 가능·조작 잠금, 재확인 후 재검색·재저장 없음. 4가지 작업 종류(searchBatch→닫기, searchHistory/Delete/Language→머묾). |
| 홈·편집 화면 기준량 표시 | 구현·검증. 홈 행 “100 g 기준”(VoiceOver 포함), 기록 편집 시트에 “100 g당 …” 각주. |
| 다음 페이지 | 세션·DTO에는 `nextPage`/`loadMore`가 있으나 영어 공급자는 한 페이지만 반환하므로 UI는 미검증. |
| 수량 편집 UI, 즐겨찾기 배수 | 미구현(계획대로 후속). |

## 환경

- macOS, Xcode 26.5(`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`), iOS 26.5 시뮬레이터 런타임.
- 기기: `HelloProtein iPhone SE`(375×667 @2x, `AF20D47C-…`), `HelloProtein iPhone 17`(402×874 @3x, `8C3433BA-…`). 이전 PR들의 합성 fixture 상태 그대로 사용: 이관 검색 이력 `legacy:search:…` “egg”(position 0), “milk”(position 1); 설정 `searchLanguage` raw `Korean(한글)`. 실행이 끝난 뒤 언어는 `English(영어)`로, 이력은 실행 검색어가 앞에 더해진 상태로 남는다.
- 앱: Debug 빌드 `/private/tmp/hp-search-build/Build/Products/Debug-iphonesimulator/ProteinTracker.app`(리뷰 반영 후 최종 코드).
- 하네스: `ui-harness/`(Smoke.swift 테스트 39–45 추가, `run-test.sh`). 원본 `/private/tmp/hp-iphone-ui/`. 검색 결과 행은 `LazyVStack`이라 화면 밖 행은 계층에 없다. 하네스는 `showResult`로 스크롤해 찾는다.

## 자동 검사 (최종 코드)

| 검사 | 결과 |
| --- | --- |
| `HelloProteinCore` `swift test` | 69 tests, 0 failures (`SearchHistoryCollectionTests` 9개, `SearchRecordBatchTests` 4개 추가) |
| `MigrationCore` `swift test` | 64 tests, 0 failures |
| 앱 유닛 테스트(`xcodebuild test`, iPhone 17) | 113 tests, 0 failures (`/private/tmp/hp-search-tests3.log`) — `EnglishCatalogProviderTests` 8개, `SearchSessionModelTests` 9개, VM 검색 테스트 7개, `AddSheetPolicyTests` 검색 케이스 추가 |
| Debug 빌드 | 성공 |
| Release 빌드 | 성공 (`/private/tmp/hp-search-release.log`). `strings -a`에서 DEBUG 주입 문자열(`HelloProteinSearchFailOnce`, `simulated search failure`, `FailingOnceSearchProvider`, `HelloProteinFailAfterReplaceOnce`, `HelloProteinSaveOutcomeOnce`) 0건, 대조 `renewal.search.addSelected`·`renewal_search_add_count`·`usda-sr-legacy-local` 2건씩 |
| `git diff --check` | 공백 오류 없음 |
| 문자열 키 | en/ko 키 집합 동일, 코드가 쓰는 `renewal_*` 키 모두 존재(스크립트 대조) |

### 테스트가 고정하는 계약

- Core: 최근 검색은 trim 후 정확히 같은 값만 재사용(소문자화 없음, position 낮은 것), 새 항목·재사용 모두 앞으로 이동 후 0..재번호, 빈 검색어는 저장하지 않음, 중복 ID 거부, 삭제는 ID로만, `setSearchHistory` 검증 실패 시 롤백; `ProteinGramsText`는 평문 10진수만, 3번째 소수 자리 half-up(`1.005→101`, `0.004→0`), 음수·지수·overflow 구분 오류; batch는 빈 선택·중복 항목·중복 record ID·0 이하·합계 overflow에 전체 실패, `FoodRecord(source: .search, quantity: 100 g)`.
- 공급자: `Protein-En.json` SHA·행 수·버전 고정(파일 교체 시 테스트가 실패해 버전 올림을 강제), 숫자 텍스트 유지, 전 행이 양수/0으로만 변환됨(변환 오류 0건), 필터는 trim·대소문자·발음부호 무시·파일 순서, 빈 검색어 0건, 리소스 누락·잘린 JSON·문자열 Protein은 `localData` 실패, 취소된 요청은 결과 미전달, 한국어는 요청 없이 `notConfigured`.
- 세션: 이력 저장 후 조회 1회, 늦은 이력 callback 무시, A→B 역순 응답에서 최신 세대만 반영·이전 요청 취소, 모든 실패(타임아웃·로컬·notConfigured·공급자 취소)가 로딩 종료, retry는 조회만, 선택 순서 유지·record ID 세대별 고정·선택 불가 행 무시, 페이지 중복 제거·내용 바뀐 선택 해제 보고, 언어 변경은 호출 시에만 적용·공급자 교체, invalidate 후 응답 무시.
- VM: `searchHistory`/`searchLanguage` 미러링, 이력 기록·삭제·언어 변경·batch가 각각 `PendingSave.kind`를 가짐, notApplied 재시도, 실제 replace 실패 중 차단, 같은 확정 언어는 쓰기 없음.
- 시트 정책(pure): 검색 탭 dirty는 선택만, 새 검색/최근/언어는 선택 있을 때만 확인, 언어 선택은 fallback이거나 다른 언어일 때만 쓰기, 이름 복사는 이름만(단백질 공란·즐겨찾기 OFF), afterConfirmed(batch 닫기, 나머지 머묾).

## UI 시나리오 (최종 빌드)

run label `search5`(SE, 전체), `search4`(17, 전체; 캡처는 라벨 충돌로 `out/search5/HelloProtein-iPhone-17/`에 저장됨), 개별 재실행은 아래에 표기. 결과 번들 `/private/tmp/hp-iphone-ui/results/`.

| # | 시나리오 | SE | 17 |
| --- | --- | --- | --- |
| 39 | 영어 “cheese, bri” → brick(23.24)·brie(20.75) 2개 선택 → “2개 선택 · 43.99 g” → 한 번에 추가 → 홈 행 +1, 행에 “100 g 기준”, 편집 시트에 기준량 각주와 20.75 | 통과 | 통과 |
| 40 | 최근 검색: 직전 검색어가 맨 앞, “egg” 탭 재검색, “milk” 검색 후 지우기(×)로 최근 목록 복귀(“milk” 맨 앞), 삭제 취소 유지 → 삭제 확인 후 제거, “egg”·“cheese, bri” 유지 | 통과 | 통과 |
| 41 | 0 g 행(Vitamin D as ingredient) 선택 불가·안내, ‘이름으로 직접 입력’ → 직접 입력 탭에 이름만, 복사된 이름은 dirty(탭 전환 확인), 선택 중 새 검색 → 버리기 확인(취소 시 선택 유지), 확인 후 새 결과, 지우기로 최근 복귀, 한국어 전환 → 사용 불가 카드(무한 로딩 없음) | 통과 | 통과 |
| 42 | `-HelloProteinSearchFailOnce network`: 실패 카드 + 재시도 → 결과(조회만 반복) | 통과 | 통과 |
| 43 | 실제 afterReplace 실패가 **이력 저장**(한 실행의 첫 쓰기)에 걸림: 미확인 알림 → 결과는 도착하되 행·검색·탭 잠금 → 시트의 재확인 → 머묾·결과 유지(재검색 없음) → 선택·추가 성공 → 홈 +1, 최근 맨 앞에 검색어 | 통과(`search8`) | 통과(`search9`) |
| 44 | `-HelloProteinSaveOutcomeOnce notApplied`가 이력 저장에 걸림: 미확인 → 결과 열람 가능·잠금 → 재확인 → ‘저장되지 않음’ → 결과 유지·해제 → 선택·추가 성공, 최근 목록에 해당 검색어 없음 | 통과 | 통과 |
| 45 | 한국어 UI·AX-XL: 언어·검색창·결과·선택바(세로 배치)·닫기 버리기 확인 | 통과 | 통과 |

캡처: `iphone-se/`, `iphone-17/`(각 `search-*.png`).

### 검색 batch pending

검색 batch 자체의 실제 afterReplace 실패 → 재확인 → 닫기는 UI로 **재현하지 못했다**. 한 실행의 첫 사용자 쓰기는 항상 이력 저장이라 `-HelloProteinFailAfterReplaceOnce`가 거기에 걸린다. batch의 `kind`·`afterConfirmed(.searchBatch) == .close`·notApplied 재시도는 유닛 테스트(`RecordHomeViewModelTests`, `AddSheetPolicyTests`)로 고정했고, 동일한 재확인 경로는 즐겨찾기 batch(테스트 35)에서 UI로 확인됐다.

## 실행 중 발견·수정

- 실패 카드의 컨테이너에 `accessibilityIdentifier("renewal.search.failed")`를 붙여 자식 ‘다시 시도’ 버튼의 식별자가 덮였다(SwiftUI 컨테이너 식별자 상속). 식별자를 문구 Text로 옮겼다(실패·사용 불가·0건 카드 모두). 테스트 42가 이를 잡았다.
- 코드 리뷰(별도 lane, Opus) 반영: 공급자가 현재 요청을 취소하면 `.failed(.cancelled)`로 로딩 종료(이전엔 영원히 검색 중), 시트 `onDisappear`에서 검색 세션 무효화, ‘선택 변경’ 오류 문구를 즐겨찾기 전용에서 중립 문구로, 음수·범위 초과를 `invalidProtein`과 구분(`negativeProtein`/`proteinOutOfRange`), 검색 지우기(×) 버튼으로 최근 목록 복귀(쓰기·요청 없음, 선택 있으면 확인), fallback 설정에서 같은 언어를 고를 때는 결과를 지운다는 안내 없이 쓰기만, VoiceOver 값에 출처·반올림·‘표시된 양을 추가’ 포함.
- 하네스: 시뮬레이터 3대 + 유닛 테스트 동시 실행 중 “Timed out while synthesizing event”·스크린샷 타임아웃이 발생해 17 1차 재실행이 5개 실패했다(앱 문제 아님, 재실행 통과). `renewal.reconfirm.sheet`가 스크롤 내용 맨 아래라 긴 결과 목록에서는 재확인 후 첫 행이 화면 밖으로 나간다 → 테스트 43은 한 행짜리 검색어(“butter, salted”)를 쓴다.
- 하네스 상태 의존: 테스트 40은 처음 작성에서 fixture의 “milk”를 삭제해 재실행이 깨졌다 → “milk”를 테스트 안에서 다시 검색해 만든 뒤 삭제하도록 바꿨다.

## 미검증·남은 조건

- 한국어 공급자: 서비스 계약을 읽을 수 없어 요청·인코딩·페이지·오류코드 처리와 계약 테스트가 없다. `API_KEY` 빌드 설정의 빈 값/치환 안 됨 처리도 공급자 구현 때 추가한다.
- 다음 페이지(`loadMore`)·페이지 실패 카드는 세션 테스트만 있고 UI 미검증.
- 검색 batch의 실제 afterReplace 실패 UI(위 참조), 이력 삭제·언어 변경의 readFailure UI.
- 실기기, 다크 모드, VoiceOver 실제 낭독.
- 영어 파일 값의 소수 2자리 정확 일치(SR-Legacy 원본 배포본 대조). FDC API는 1자리만 제공한다(B0 README).
