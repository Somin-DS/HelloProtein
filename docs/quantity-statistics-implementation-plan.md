# 검색 음식 섭취량과 통계 구현 계획

작성일: 2026-10-14. 상태: **Q1 구현 완료(PR 검토 대기), Q2·S1 미착수**. 진행 기록은 문서 끝의 [진행 상태](#진행-상태)를 본다. 대상: 다음 구현을 맡는 개발 에이전트. 기준: PR #10 병합 main `3c37bcd5d3c097b62ade242aed3a3b9e46da0fbc`. 본사 기획·디자인·개발·QA·마케팅·그로스·프롬프트 엔지니어의 [공동 검토](reviews/2026-10-14-quantity-statistics-team-review.md)를 반영한다.

이번 업데이트는 검색한 음식의 **실제 먹은 양 입력·재편집**과 **최근 7일·30일 기록 통계**를 함께 완성한다. 예를 들어 100g당 단백질 12.18g인 식품을 150g 먹었다고 입력하면 18.27g을 기록하고, 해당 날짜의 합계와 통계에 반영한다. 기존 사용자 기록과 목표 이력을 보존하는 것이 완료 조건이다.

이 요청의 산출은 plan과 검토 기록뿐이다. 구현·빌드·PR·머지·실기기 설치는 실행하지 않는다. 아래 순서는 후속 구현자의 실행 계획이다.

## 범위와 구현 순서

두 기능은 하나의 업데이트 범위다. 공통 데이터 계약을 먼저 고정한 다음 순서대로 구현한다. 리뷰 가능한 PR은 세 개로 나누되 세 단계 완료 전에는 이번 업데이트 전체가 끝났다고 보고하지 않는다.

| 단계 | 결과 | 의존성 |
| --- | --- | --- |
| Q1 계산과 저장 계약 | 정확한 비례 계산, 계산 기준 저장, schema 3 승격과 복구 | 최신 main |
| Q2 섭취량 화면 | 검색 다중 선택의 개별 수량 편집, 저장 후 재편집, 기존 편집·pending 회귀 | Q1 |
| S1 통계와 통합 검증 | 기간별 집계·차트·날짜별 목록·홈 연결, 두 기능 통합 검증 | Q1·Q2; 순수 집계 구현은 Q2와 독립 진행 가능 |

포함: 기존 무료 검색과 즐겨찾기 유지, 한영 UI, 일반 iPhone, 현재 iOS 15 이상 renewal 경로, 과거 날짜 기록, 통계에서 기록 날짜로 이동, schema 1·2 및 Realm 사용자 이관 회귀.

제외: g↔oz·g↔mL 환산, 밀도·개수·인분 추정, 즐겨찾기 수량 모델 확장, 영양 권장량 계산, 칼로리·탄수화물·지방, 월간 달력·연속 달성·주간 비교, AI 해설·입력·결제·광고·분석 SDK, Android 구현, 전체 탭바 재설계, Duo·iPad, 다크 모드 신규 지원, 최소 OS 변경, renewal 기본 활성화, 배포. Android를 위해 숫자·날짜 fixture는 플랫폼 독립 JSON으로 남긴다.

## 현재 구현과 이번 변경의 경계

| 현재 코드 | 계획에 주는 제약 |
| --- | --- |
| `SearchResultItem.rawProtein`, reference, providerID/dataVersion/itemID | 원천 소수와 기준량이 검색 중에는 존재한다. 저장할 계산 기준의 재료다. |
| `SearchSelection`, `SearchRecordBatch` | 현재는 표시된 기준량과 반올림된 centigrams를 N개 원자적으로 저장한다. 실제 수량·불변 계산 기준을 함께 전달해야 한다. |
| `FoodRecord.quantity`, protein, source | quantity가 원래 검색 기준량이고 protein은 이후 수동 편집됐을 수 있다. 과거 기록을 일괄적으로 실제 섭취량이나 공급자 원본으로 재해석할 수 없다. |
| `FoodRecord.withChanges`, `RecordHomeViewModel.updateRecord` | 현재 이름·단백질만 변경하고 quantity/source를 유지한다. 새 기록의 수량 변경을 검증하는 별도 명령과 편집 모드가 필요하다. |
| `AppState.currentSchemaVersion == 2` | 영속 계산 기준을 추가하므로 명시적인 schema 3 승격이 필요하다. schema 2에 필드만 끼워 넣으면 이전 writer가 이를 유실할 수 있다. |
| `DailyLog.totalProteinCentigrams()` | 상세 합계와 signed legacy adjustment를 더한 값이 정본이다. 통계도 이 값을 사용한다. |
| `GoalHistory.goal(on:)` | 날짜별 목표를 조회한다. 현재 목표를 과거 날짜에 소급하지 않는다. |
| `RecordHomeViewModel`의 private state와 refresh | 통계는 확정 상태의 읽기 전용 snapshot을 받아야 한다. 별도 파일 reader/writer를 만드는 구조가 아니다. |
| 기존 `StatsViewController` | Realm·요일 문자열·Double·현재 주에 의존한다. 새 통계의 집계나 저장 경로로 재사용하지 않는다. |

PR #10까지의 검증은 [한국어 검색 증거](evidence/2026-10-14-korean-search/README.md)에 있다. 앱 테스트 123개와 실 API UI 테스트 3개는 **이전 기능의 기준선**이며 새 기능의 통과 결과가 아니다. Figma 원본은 이번 검토에서 다시 열지 않았고, 기존 UI를 확장하는 범위로 계획했다.

## 섭취량 계산 계약

### 불변 기준과 실제 수량

신규 `FoodRecord`에 optional `calculationBasis`를 추가한다. 이름은 바꿔도 다음 의미를 보존한다.

| 값 | 의미 |
| --- | --- |
| `proteinGramsText` | 기준량의 단백질을 표현하는 검증된 십진 문자열. 계산 전에 0.01g로 반올림하지 않는다. |
| `referenceQuantity` | 단백질의 분모인 양과 단위. 예: 100 gram. |
| `origin` | `providerSnapshot` 또는 `userDefined`. 건강·정확성 인증 표지가 아니다. |
| 공급자 식별자 | providerSnapshot인 경우 providerID/dataVersion/itemID. 원문 요청 URL·인증키는 금지한다. |
| `FoodRecord.quantity` | basis가 있는 신규 기록에서는 사용자가 최종 적용한 실제 양이다. |
| `FoodRecord.protein` | 기준으로 계산한 최종 단백질 centigrams. UI 표시·통계는 이 저장값을 사용한다. |

계산 기준은 공급자 재조회로 갱신하지 않는다. 수량을 몇 번 변경해도 같은 기준에서 다시 계산한다. source는 `.search`, 기록 id/day/legacySourceID는 변경하지 않는다. providerSnapshot 저장은 해당 시점의 스냅샷을 뜻하며 이후 최신 데이터와의 일치를 약속하지 않는다.

공식은 `proteinGramsText × 실제 수량 ÷ referenceQuantity.value`이고, **최종 결과만 소수점 셋째 자리에서 양수 half-up 반올림하여 소수점 둘째 자리(0.01g)까지 표현하고 centigrams로 변환**한다. 기준과 실제 수량은 같은 단위여야 한다. 합계는 각 행의 최종 centigrams를 checked sum한다. 행별 반올림 합계와 원시값 전체 합산 후 반올림을 섞지 않는다.

| 입력 | 기대 결과 |
| --- | --- |
| 12.18g / 100g → 150g | 18.27g |
| 1.005g / 100g → 200g | 2.01g; 1.01 × 2 = 2.02로 계산하면 실패 |
| 10g / 3g → 1g → 2g → 3g | 각각 3.33g, 6.67g, 10g; 이전 저장값을 연쇄로 곱하지 않음 |
| 4g / 100mL → 250mL | 10g, 양의 단위는 mL 유지 |
| 최종 0.004g | 0.00g이므로 적용·추가 불가, 이유 표시 |
| 같은 수량·이름·기준으로 다시 저장 | 변화가 없으면 쓰기 없는 no-op |

`Double`을 저장·비례 계산에 사용하지 않는다. 정확한 십진 정수/분수와 몫·나머지로 최종 반올림을 결정하는 순수 helper를 권장한다. Decimal을 선택할 경우 중간 계산의 정밀도 손실을 무시하지 않고 위 분수 예제와 경계를 정확히 통과해야 한다. 검증되지 않은 임의 epsilon이나 Int64 wraparound는 금지한다.

### 입력 허용 범위

새 수량 입력은 양수, 정수부 최대 9자리·소수부 최대 3자리로 제한한다(최대 999999999.999). UI는 locale 소수 구분자와 점 입력을 정규화한다. 허용 구분자 한 개는 항상 소수점으로만 해석한다(쉼표 locale에서도 `1.234`는 1.234, 1234가 아님). 점과 locale 구분자를 섞거나 반복한 입력, 공백·아포스트로피 등의 그룹 표기·지수·NaN·무한대·음수·0·빈 값은 거부한다. 그룹 구분자를 추측해 제거하지 않는다. 범위를 넘으면 자동 자르기나 임의 반올림 대신 수정 안내를 한다. 숫자 키보드 외 붙여넣기도 검사한다.

새 basis의 단백질·기준량은 유효숫자 18자리·소수부 9자리 이하의 양의 십진수로 제한한다. 긴 기존 `FoodQuantity`를 읽는 decoder에는 새 제한을 소급 적용하지 않는다. 수량 편집을 제공하려면 기본 referenceQuantity 자체도 수량 입력의 9자리 정수부·3자리 소수부 범위에 들어야 한다. 예를 들어 기준량 0.0001g 또는 1234567890g은 수량 편집 대상이 아니다. 새 기준을 만들 수 없거나 기본량을 편집기에 그대로 표현할 수 없는 검색 행도 이전의 기준량 추가가 유효하면 그대로 추가할 수 있으며, 이 경우 수량 변경은 비활성화하고 basis 없는 기록으로 저장한다. 계산 불가 이유와 이름만 직접 입력 경로를 제공한다. provider가 기존에 선택 불가로 판정한 0·음수·기준 불명 행을 큰 수량 입력으로 우회하지 않는다.

입력 범위 내라도 최종 Int64·개별 단백질·일일 합계·batch 합계 overflow는 별도 오류다. 잘못된 입력을 0으로 바꾸거나 일부 음식만 저장하지 않는다.

## 저장된 기록의 편집과 호환성

1. **기존 basis 없는 기록:** 원래 수량·단백질·source를 그대로 보존한다. 기존 이름·단백질 직접 편집은 유지한다. 자동 수량 편집 버튼은 제공하지 않고 수량 문구는 ‘저장된 기준량 / Saved reference amount’로 유지한다. 기존 search source라는 이유로 공급자 기준을 복원하지 않는다. 기존 기록을 새 기준으로 전환하는 추가 기능은 후속이다.
2. **basis 있는 기록:** 이름과 실제 수량을 수정하며 단백질은 계산 결과로 표시한다. 기존 양으로 돌아오면 원래 기준에서 재계산한다. 이름만 바꾸면 basis를 보존한다.
3. **신규 기록의 단백질 직접 수정:** 명시적인 ‘단백질 직접 수정’ 전환을 제공한다. 전환 자체는 저장하지 않는다. 현재 적용된 수량은 고정해 보이고 단백질을 입력한다. 이 모드에서는 기존 ProteinInput 검사에 더해 userDefined basis의 유효숫자 18자리 제한을 저장 전에 검사하고 범위 초과 오류와 함께 저장을 막는다. 기존 basis 없는 기록의 직접 입력 범위에는 이 새 제한을 적용하지 않는다. 저장하면 그 수량과 입력한 단백질을 새 `userDefined` 기준으로 함께 저장한다. 공급자 식별자를 새 기준에서 제거하고 ‘직접 입력한 값 기준’으로 표시한다. 이후 수량 편집은 이 새 기준을 사용한다. 취소는 원래 기준·양·값을 복원한다.
4. **즐겨찾기에도 저장:** 현 모델은 이름·단백질만 저장한다. 수량·basis를 붙인 것처럼 표시하지 않는다. 옵션 옆 ‘현재 단백질 값만 즐겨찾기에 저장’ 안내를 넣고 기존 원자적 저장 계약을 유지한다. 즐겨찾기에서 다시 추가한 기록은 기존처럼 quantity/basis가 없다.

새 basis가 있는 기록은 decode와 저장 검증 모두에서 quantity 존재, source.search, 기준·실제량 단위 일치, 최종 protein 일치를 확인한다. providerSnapshot은 providerID/dataVersion/itemID가 모두 비어 있지 않아야 하고 userDefined에는 공급자 식별자가 없어야 한다. 불일치를 로드하면서 자동 수정하지 않는다. 기존 legacy 값·보정값·원문을 바꾸지 않는다. invalid basis를 조용히 nil로 바꿔 파일 손상을 숨기지 않는다.

## Schema 3 승격과 복구

Q1에서 가장 먼저 저장 계약을 구현한다. 기존 Realm 이관 자료와 schema 승격 백업은 분리해 보존한다.

- schema 2 전용 읽기 DTO/상태를 두고 유효한 전체 문서를 검사한다. 단순히 JSON의 숫자 2를 3으로 치환하지 않는다.
- 원본 schema 2 바이트의 불변 백업과 SHA-256을 확보하고 읽기 검증한 뒤에만 새 파일을 commit한다. 기존 백업이 있으면 지문·원본 대응을 확인하고 덮어쓰지 않는다. 백업 누락·손상·읽기 실패는 구분해 복구 상태로 멈춘다.
- 기존 기록의 basis는 모두 nil이다. logs/favorites/searchHistory/settings/goals/migration/legacy 원문·ID·날짜·signed 합계와 기존 lastOperationID 의미를 보존한다. 승격 증거의 operation ID는 사용자 저장 ID와 혼용하지 않는다.
- 기존 `migration`의 최초 이관 원점과 완료 시각을 새 사용자 이관처럼 덮어쓰지 않는다. schema 승격 증거는 별도 파일에 남긴다. 최초 Realm 백업·완료 마커의 형식과 목적도 유지한다.
- `FileAppStateStore`의 임시 쓰기 → 검증 → 원자 교체 → 재읽기 계약을 사용한다. 교체 전 실패는 schema 2 그대로 재시도, 교체 후 미확정은 현재 파일을 읽어 확인한다. 새 파일을 구버전 백업으로 자동 덮어쓰지 않는다.
- 재실행 시 검증된 schema 3는 그대로 열고 중복 승격하지 않는다. schema 3 정상/승격 마커 누락은 정상 파일을 우선하며, schema 2/백업만 존재는 대응 관계를 검증한 뒤 승격을 재개한다. 대상 없음/승격 완료 증거 있음은 빈 설치로 만들지 않는다.
- schema 1 → 현행, Realm/UserDefaults → 현행, 신규 설치 → 현행 경로를 모두 갱신한다. schema 1·Realm 동시 존재 충돌 등 기존 보호 규칙을 유지한다. 필요하면 메모리에서 1→2→3 변환하되 디스크의 중간 변환을 여러 번 성공한 것으로 처리하지 않는다.
- 지원보다 높은 schema, 잘못된 basis, 읽기 불가 파일은 기존 복구 화면에서 멈춘다. 구 앱은 schema 3를 지원하지 않는 상태로 거부해야 하며 legacy UI로 돌아가 쓰면 안 된다. schema 3를 쓴 뒤 이전 바이너리로 자동 rollback하는 절차를 제공하지 않는다.
- 스키마 승격 증거 역시 missing/valid/corrupt/unreadable/unsupported로 검사한다. 신설 경로·실패 지점을 문서와 테스트에 명시한다. 기존 백업 존재 여부만으로 복구 가능하다고 안내하지 않는다.

원본 실사용 데이터 검증은 출시 전 별도 조건으로 남긴다. 이번 개발 검증은 합성 schema 1·2·Realm fixture와 실패 주입으로 수행하며, 사용자가 지정하지 않은 실기기에 설치하거나 데이터 초기화를 하지 않는다.

## 섭취량 화면과 세션

```text
기록 홈 → 추가 → 검색 → 결과 선택
                       ├─ 기본 기준량으로 선택 유지
                       └─ 선택 행의 섭취량 변경
                           음식명 / 영양 기준 / 먹은 양 / 계산 결과
                           취소 또는 적용 → 검색 선택 목록
                       → N개 추가 → 고정 날짜 홈
기록 홈 → 신규 계산 기록 수정
           이름 / 먹은 양 / 계산 결과
           단백질 직접 수정 전환 / 저장 / 취소
```

현재 검색 체크 동작과 다중 선택을 유지한다. 선택한 행에 독립 44pt ‘섭취량 변경’ 버튼을 두고, `AddSheet` 내부 편집 화면으로 이동한다. 중첩 sheet를 쌓거나 모든 검색 행에 TextField를 넣지 않는다. 기본 입력값은 그 행의 검증된 기준량이다.

편집 화면은 ‘100g당 단백질 12.18g’, ‘먹은 양 150g’, ‘기록될 단백질 18.27g’을 분리한다. 수량 편집의 기준 단백질은 원시 소수 정밀도를 보존해 표시한다(예: 100g당 1.005g). 계산 결과만 0.01g로 표시하며 검색 행의 기존 반올림 안내와 일치시킨다. 단위는 고정 표시하고 키보드에 가리지 않게 한다. ‘적용’은 세션 초안만 변경하고 최종 N개 추가 전까지 음식 기록 쓰기는 0회다. 잘못된 값이면 계산 결과를 숨기거나 —로 표시하고 적용을 막는다. 이전 정상 계산값을 현재 입력 결과처럼 보여주지 않는다.

- 임시 입력 문자열까지 dirty로 판단한다. 취소·뒤로·스와이프 시 변경이 있으면 버리기 확인 후 마지막 적용값으로 돌아온다. 최종 추가 시트 취소는 선택·수량을 함께 버리는 기존 확인 정책을 사용한다.
- 항목의 수량 변경은 record ID·선택 순서를 바꾸지 않는다. 선택 해제는 해당 수량 초안을 폐기하고 재선택은 기본량으로 시작하되 같은 세션 record ID 재사용 정책은 유지한다.
- 검색어 입력만 바뀌면 결과·수량을 유지한다. 새 검색·최근 검색·언어 변경·탭 이동 때 선택 버리기 확인에 수량 초안도 포함한다. 언어 저장 실패·미확정이면 기존 스냅샷과 수량을 유지한다.
- 수량 편집 중 해당 ID의 공급자 스냅샷이 바뀌면 이전 선택·수량 적용을 무효화한다. 편집 완료 시 item key뿐 아니라 기준 fingerprint/세션 세대를 대조하고 재선택을 안내한다. 같은 ID라고 새 기준에 옛 수량을 조용히 적용하지 않는다.
- 최종 저장 때 진행 중 페이지를 취소하고 선택 스냅샷을 고정한다. N개를 같은 modify에서 모두 추가하거나 0개다. 대상 날짜는 시트를 연 때의 날짜로 고정하며 자정·과거 날짜에도 바꾸지 않는다.
- busy/pending 동안 수량·이름·단백질·기준 모드 변경도 잠근다. confirmed applied는 닫기, notApplied는 같은 ID·수량·기준을 유지한 재시도, readFailure는 잠금 유지다. 세션을 닫은 뒤 재확인했다고 시트나 요청을 재생성하지 않는다.

## 통계의 기간과 집계 의미

### 기간

홈에서 ‘통계 보기’로 진입한다. 전체 탭바를 교체하지 않고 상단 달력 옆 차트 버튼과 단일 push 화면을 사용한다. 기존 NavigationView의 단일 칼럼 동작을 유지한다.

초기 끝 날짜는 `min(홈 선택 날짜, 오늘)`이고, 이를 끝으로 최근 7일을 보여준다. 7일/30일 전환은 끝 날짜를 유지한다. 이전/다음은 현재 기간 길이만큼 이동하고 다음은 오늘까지만 이동한다. ‘최근 기간’은 끝 날짜를 오늘로 되돌린다. 달력상의 이번 주·이번 달이라는 이름을 사용하지 않는다. 실제 시작·끝 날짜를 항상 표시한다.

날짜 연산은 `CalendarDay.adding(days:)`를 사용한다. 86400초 곱셈, 요일 문자열 파싱, 시스템 달력의 주 경계로 기간을 추정하지 않는다. 지원 날짜 하한에서 잘리면 실제 기간 일수 M을 분모로 쓴다. 오늘은 현지 시간대로 정하되 저장된 날짜를 시간대 변경으로 이동시키지 않는다. 화면이 열린 동안 끝 날짜는 고정하고 foreground/자정에는 오늘 상태·미래 제한만 갱신한다. ‘최근 기간’을 눌렀을 때 새 오늘로 이동한다.

### 기록과 요약

| 상태 | 차트·목록 | 합계와 평균 |
| --- | --- | --- |
| log 없음 또는 records 비어 있고 adjustment nil | 기록 없음, 값 — | 기록일 분모 제외 |
| 상세 기록 있음 | 날짜의 최종 합계 | 포함 |
| legacy adjustment 존재, 합계 0 | 기록된 0g, 과거 합계 표시 | 기록일 포함 |
| legacy 합계만 있음 또는 상세와 함께 있음 | ‘과거 합계 포함’ 표시 | `totalProteinCentigrams()` 그대로 포함, 상세만 재합산 금지 |
| 음수 legacy 합계 | signed 값과 ‘과거 보정값을 확인해 주세요’ | signed 값 그대로 포함, 기간에 경고 표시 |
| 미래 날짜 | 기간에서 제외 | 제외 |
| 집계 overflow/무결성 실패 | 집계할 수 없음, 사용 가능한 날짜 목록과 오류 안내 | 해당 요약을 —로 표시; 0이나 부분 합계로 대체 금지 |

요약은 **기록 합계**, **기록이 있는 날 평균**, **기록한 날 N/M일**이다. 기록 합계는 관측된 날짜의 signed 일일 합계의 checked sum, 평균은 그 합계를 기록일수 N으로 나눈 값이다. 음수 원본을 평균에서만 제외하면 홈과 통계의 관계가 달라지므로 이번 계획에서는 보존·포함한다. 이 경우 ‘과거 음수 보정값 포함’ 안내를 합계/평균 옆에 표시하고 날짜별 원문 확인으로 연결한다. 이는 실제 섭취량의 완전한 측정값이 아니라 사용자가 저장한 기록의 요약이다.

평균은 표시할 때만 소수점 둘째 자리로 반올림한다. signed 절반은 0에서 먼 방향으로 반올림하고, 합계가 Int64.min인 경우 abs overflow를 일으키지 않는다. 기록일 0이면 합계·평균은 —, 기록한 날은 0/M, 빈 상태 안내를 보인다. 실제 0g 기록이 있으면 합계·평균을 0g으로 보인다.

목표는 **각 날짜에 유효한 목표**만 표시한다. 목표 표시는 기존 `RecordHomeViewModel.goalState(for:in:)`의 우선순위와 맞춘다. 유효한 날짜별 목표가 있으면 그것을 표시한다. 목표 배열이 비어 있고 goalNeedsReview이면 ‘목표 확인 필요’, 목표가 전혀 없으면 ‘목표 미설정’, 목표 이력이 있으나 해당 날짜를 덮지 않으면 ‘목표 이력 없음’이다. 전역 검토 flag만으로 정상적인 날짜별 목표를 가리지 않는다. 목표가 있는 비음수 기록일만 날짜별 비교를 제공하고 오늘에는 ‘기록 중’을 덧붙인다. 음수·무기록은 달성/미달 판정을 하지 않는다. 첫 버전은 기간 달성률·연속 달성 KPI를 넣지 않는다. 차트의 목표 표시는 날짜별 값이며 오늘 목표의 수평선을 전 기간에 그리지 않는다.

### 집계 예시

7일 중 일일 합계가 20g·40g·60g·과거 0g·과거 -10g이고 두 날은 무기록이면 기록일수는 5/7, 기록 합계 110g, 기록일 평균 22g이다. 음수 보정 포함 안내와 해당 날짜 -10g을 표시한다. 기록 없는 두 날을 0g으로 만들어 평균 분모를 7로 바꾸지 않는다.

목표가 10월 10일 100g에서 10월 12일 120g으로 바뀌었다면 11일 기록은 100g, 12일 기록은 120g과 비교한다. 10일 이전 목표가 없으면 현재 목표로 채우지 않는다. 저장된 기록을 수정·삭제하거나 과거 합계를 바꾸면 같은 기간의 숫자가 바로 다시 계산된다.

## 통계 화면과 상태 연결

```text
통계
  실제 기간 / 7일·30일 / 이전·다음 / 최근 기간
  저장 결과 확인 필요 안내 또는 집계 오류
  기록 합계 / 기록일 평균 / 기록한 날 N/M
  날짜별 막대와 목표 표시
  날짜별 목록: 날짜·기록량·목표·기록 상태
    날짜 선택 → 통계 닫기 → 홈의 해당 날짜
```

7일은 날짜별 막대, 30일은 제한된 축 레이블과 별도 날짜별 목록을 제공한다. 막대가 작아도 목록의 44pt 행으로 모든 날짜에 접근할 수 있어야 한다. 음수는 0선 아래에 그리며 클램프하지 않는다. 극단값으로 읽기 어려울 때 수치 목록이 정본이고, 잘린 축을 쓴다면 생략을 명시한다. 기록 없음과 0g은 색 외에 빈 표시·문구로 구분한다.

최소 지원 경로에서 동작하는 SwiftUI 구성으로 구현한다. 새로운 차트 API나 패키지가 필요하면 설치된 SDK와 deployment target에서 먼저 검증하며, 통계 하나 때문에 최소 OS를 올리거나 기존 UIKit Charts 의존을 새 저장 경로에 끌어오지 않는다. 그래프 좌표만 Double로 바꿀 수 있고 통계 계산은 정수/정확한 소수로 한다.

통계 계산기는 `AppState`의 확정 snapshot과 기간을 입력받는 순수 Core 타입이다. `RecordHomeViewModel.refresh()`가 snapshot/revision을 publish하고 통계 화면은 이를 읽는다. 상태 복사본에 빈 DailyLog를 추가하거나 캐시를 파일에 저장하지 않는다. 조회·기간 변경·날짜 선택의 저장 호출은 0회다.

저장 결과 미확정이면 마지막으로 확인된 통계를 표시하고 ‘저장 결과 확인이 필요해요’ 배너와 ‘저장 결과 확인’ 액션을 제공한다. 액션은 기존 VM의 reconfirm을 호출하고 실제 확인 작업 중에만 ‘확인 중’으로 표시한다. 별도 load로 미확정 파일을 우회해 표시하지 않는다. 기존 VM의 reconfirm이 applied/notApplied를 확정한 후 새 snapshot으로 재집계한다. 읽기 실패는 이전 통계·잠금을 유지한다. 통계에서 날짜별 홈으로 이동해도 전역 쓰기 잠금은 유지한다.

통계에서 날짜를 골라 홈으로 돌아올 때 기존 날짜 선택 메서드를 호출한다. 다시 통계를 열면 마지막 7/30일 선택은 세션 메모리로 유지하되 끝 날짜는 홈 선택 날짜로 맞춘다. 별도 사용자 설정·영속 내비게이션 상태를 추가하지 않는다.

## 문구와 접근성

| 용도 | 한국어 | English |
| --- | --- | --- |
| 수량 편집 | 섭취량 변경 | Edit amount |
| 입력 | 먹은 양 (g) | Amount eaten (g) |
| 미리보기 | 기록될 단백질 18.27g | Protein to log: 18.27 g |
| 기준 | 100g당 단백질 12.18g | 12.18 g protein per 100 g |
| 새 기록 양 | 먹은 양 150g | Amount eaten: 150 g |
| 사용자 기준 | 직접 입력한 값 기준 | Based on your entered values |
| 입력 오류 | 0보다 큰 양을 입력해 주세요 | Enter an amount greater than zero. |
| 통계 합계 | 기록된 단백질 | Logged protein |
| 평균 | 기록이 있는 날 평균 | Average on logged days |
| 분모 | 기록한 날 3/7일 | Days logged: 3 of 7 |
| 빈 날짜 | 기록 없음 | No entry |
| 과거 목표 누락 | 목표 이력 없음 | No goal history |
| 음수 안내 | 과거 음수 보정값이 포함되어 있어요 | Includes a negative adjustment from past records. |

한영 각각 완성된 format 문자열을 쓴다. locale별 숫자 소수 구분자와 단위 간격을 유지한다. ‘권장량’, ‘완벽한 정확성’, 건강 개선이나 AI 기능을 주장하지 않는다.

iPhone SE 375pt와 큰 일반 iPhone에서 긴 음식명·영어·최대 접근성 글자·키보드·safe area를 검사한다. 필요한 경우 요약 카드를 세로로 쌓고 수량 편집 Apply/취소를 고정한다. VoiceOver는 음식명·기준·입력 단위·계산 결과·검증 오류를 구분해 읽으며 키 입력마다 전체 화면을 반복 안내하지 않는다. 차트 장식과 날짜 목록의 중복 낭독을 피하고 목록에는 모든 수치를 제공한다. 포커스는 편집 진입/복귀/오류 시 적절한 컨트롤로 이동한다.

## 파일과 책임

| 위치 | 책임 |
| --- | --- |
| `HelloProteinCore/.../RecordDomain.swift` | optional basis, 새 기록 불변식, 이름/수량/직접 단백질 편집의 검증된 복사 |
| 신규 `PortionCalculation.swift` | 십진 입력·정확한 비례 계산·최종 반올림·경계 오류 |
| `SearchRecordBatch.swift` | 실제 수량·basis를 갖는 스냅샷과 원자적 N행 변환 |
| `AppState.swift`, `AppStateStore.swift` | schema 3 decode/validate 및 구버전 판정 |
| `MigrationCore/.../MigrationCoordinator.swift` 및 증거 저장소 | schema 2 백업·승격·중단·재확인, schema 1/Realm/new 설치 회귀 |
| 신규 Core `StatisticsSummary.swift` | 기간·기록 유무·signed 합계·평균·날짜별 목표 DTO |
| `SearchSessionModel.swift`, `SearchTab.swift` | 기준/수량 스냅샷, 선택 변경과 기준 변경 감지, 수량 편집 진입 |
| 신규 `PortionEditorView.swift` | 입력·미리보기·Apply/취소; 저장소·네트워크 의존 없음 |
| `AddSheet.swift`, `AddSheetPolicy.swift` | 편집 route·dirty·고정 날짜·pending 잠금; 기존 파일에 계산 로직 누적 금지 |
| `RecordHomeViewModel.swift` | 단일 쓰기 소유, quantity 변경 명령, 확정 상태 snapshot publish |
| `RecordHomePrototypeView.swift`, `Components/FoodRow.swift` | 기록 편집과 basis 유무에 맞는 수량 표시, 통계 진입 |
| 신규 `StatisticsView.swift` | 읽기 전용 통계 UI, 기간·목록·홈 날짜 연결 |
| ko/en strings, Xcode project, Core/Migration/app tests | 로컬라이징·타깃 연결·실행 검증 |

타입명은 조정 가능하나 Core는 SwiftUI·UIKit·Realm·네트워크에 의존하지 않는다. 데이터 로직을 거대한 View에 추가하거나 통계 VM에 별도 writer를 만들지 않는다.

## 검증과 인계 기준

| 영역 | 필수 검증 |
| --- | --- |
| 계산 | 위 수치 4종, 동일 기준으로 반복 재편집·앱 재실행, half-up 경계, 0.004g 거부, signed 통계 평균 경계, Int64 및 중간 계산 overflow |
| 입력 | 한영 locale, 소수점·붙여넣기·공백·0·음수·NaN·exponent·그룹 구분자·자릿수 상한, 단위 불일치, 옛 긴 quantity decode 유지 |
| basis | raw1.005 정밀도 저장, 계산 protein 검증, 사용자 직접수정 전환·취소·이름수정, provider 재조회 없이 편집, 기존 nil기록 무변경 |
| 승격 | schema2 정상 및 nil lastOperationID, 백업 지문/불일치/손상/읽기실패, 교체 직전/직후 중단·재실행, 마커 누락, 완료증거+대상없음, higher schema 거부, schema1/Realm/fresh 경로 |
| 보존 | 각 기존 ID·날짜·단백질·quantity·signed보정·원문·목표·favorites/searchHistory·migration 동일; 구버전 writer로 schema3 쓰기 거부 |
| 검색 세션 | 여러 음식 서로 다른 수량, 선택 순서·recordID, 해제/재선택, dirty취소, 기준 바뀐 페이지·늦은 callback·언어저장 실패·새검색, 일괄저장 overflow 0행 |
| 저장 | 확정 실패·실제 afterReplace·대역 notApplied/readFailure, 수량초안/ID 보존, 중복 추가0, 모든 편집잠금, 과거날짜·자정·즐겨찾기 total-only 안내 |
| 통계 | 무기록/명시0/empty log/legacy합계/혼합상세/음수, 기록일분모, 목표 변경일·목표누락·검토필요, 7/30일·윤년·DST·시간대·날짜하한·미래, period overflow를0으로대체않음 |
| 상태 연결 | 조회 write0, 저장·수정·삭제·총량편집·목표수정 후 재집계, pending 이전확정표시, applied/notApplied/readFailure, 날짜탭홈선택 |
| 화면 | 일반iPhone작은/큰폭·한영·큰글씨·키보드·44pt·VoiceOver 실제탐색, 30일축/목록·긴값·signed축·빈상태·접근성 오류읽기 |
| 회귀 | 기존 직접입력·기록CRUD·목표·즐겨찾기CRUD/다중추가·검색언어/최근검색·한국어페이지·이관복구 |

통합 UI 시나리오: 실제 검색으로 12.18g/100g 표본 확인 → 150g 적용 → 18.27g 추가 → 홈과 통계에서 같은 날짜 값 확인 → 재실행 → 200g으로 수정해 24.36g 확인 → 통계 갱신 → 삭제 후 무기록 처리 확인. 영문·mL·반올림 경계·통계 복합 fixture는 결정론적 대역으로도 검사한다. 실제 공급자 표본이 바뀌면 최신 원문과 기대값을 재확인하고 하드코딩한 음식 ID만 맞추려고 결과를 조작하지 않는다.

Core·MigrationCore·앱 테스트와 Debug/Release 빌드, UI 하네스를 각 단계 변경에 맞춰 실행한다. 기존 임시 simulator UDID를 복사하지 말고 현재 기기 목록에서 확인한다. 로그는 키·원시 요청 URL·실사용 전체 저장 파일을 포함하지 않는다. API 키는 ignored Secrets.xcconfig를 유지한다. 실기기 빌드는 이번 범위 밖이다.

```sh
swift test --package-path HelloProteinCore --scratch-path /private/tmp/hp-quantity-core
swift test --package-path MigrationCore --scratch-path /private/tmp/hp-quantity-migration
# 설치된 Xcode와 시뮬레이터를 확인한 후 실제 값을 사용한다.
xcodebuild -project ProteinTracker/ProteinTracker.xcodeproj -scheme ProteinTracker \
  -configuration Debug -destination 'platform=iOS Simulator,id=<확인한 UDID>' \
  -derivedDataPath /private/tmp/hp-quantity-app \
  -onlyUsePackageVersionsFromResolvedFile test CODE_SIGNING_ALLOWED=NO
xcodebuild -project ProteinTracker/ProteinTracker.xcodeproj -scheme ProteinTracker \
  -configuration Release -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/hp-quantity-release \
  -onlyUsePackageVersionsFromResolvedFile build CODE_SIGNING_ALLOWED=NO
```

증거는 `docs/evidence/<실행일>-quantity-statistics/`에 계산 fixture, 승격 전후 비교(합성 데이터), UI 캡처, 테스트 수·실패·미검증을 남긴다. 테스트 개수를 미리 성공 결과로 적지 않는다. 기획·디자인은 적용/저장 구분과 통계 분모를, 개발·QA는 수치·복구·pending을, 마케팅·그로스는 무료 기능 유지·오해 없는 설명을 확인한다. 프롬프트 엔지니어 관점에서는 결정론적 데이터 계약과 인계 재현성을 확인하며 AI를 추가하지 않는다.

## 완료 조건

- [ ] schema 3 승격이 기존 데이터를 보존하고 실패·재실행 때 중복 이관·자동 초기화를 하지 않는다.
- [ ] 검색 수량 변경과 저장 후 재편집에서 원래 기준과 원시 소수 정밀도를 보존하고 최종 한 번만 반올림한다.
- [ ] basis 없는 기존 기록의 의미·값·수동 편집은 유지된다.
- [ ] 다중 추가와 재시도가 원자적이며 수량·기준·record ID·대상 날짜를 유지한다.
- [ ] 최근 7/30일 통계가 기록 없음·0·음수·과거합계·날짜별 목표를 정의대로 보여준다.
- [ ] 통계 조회에 쓰기가 없고 저장 확정 후 홈과 통계가 같은 상태를 표시한다.
- [ ] 일반 iPhone·한영·접근성과 두 기능 통합 UI 증거가 있다. 미검증 항목은 명시한다.
- [ ] Q1만 혹은 Q2까지만 완료한 상태를 이번 업데이트 전체 완료로 보고하지 않는다.

다음 구현자는 이 계획과 공동 검토 기록, AGENTS.md, 최신 main을 확인한 뒤 Q1부터 진행한다. 무관한 `.DS_Store`·`agents/`·사용자의 AGENTS.md 변경을 삭제하거나 일괄 stage하지 않는다. API 공급자·유료계약·배포·기본 활성화 등 범위 밖 선택이 새로 필요할 때만 근거와 구체안을 제시한다.

## 진행 상태

| 단계 | 상태 | 근거 |
| --- | --- | --- |
| Q1 계산과 저장 계약 | 구현·검증 완료, 브랜치 `feat/renewal-quantity-q1` | [Q1 증거](evidence/2026-10-14-quantity-statistics/README.md): Core 87·MigrationCore 82·앱 123 테스트 통과, Debug/Release 빌드, 시뮬레이터 2대의 실제 schema 2 파일 승격(정상·교체 직후 중단 재개) |
| Q2 섭취량 화면 | 미착수 | Q1 병합 후 같은 증거 폴더에 이어서 기록 |
| S1 통계와 통합 검증 | 미착수 | Q2 뒤 진행 |

Q1에서 확정한 계약: `FoodRecord.calculationBasis`(proteinGramsText·referenceQuantity·origin·provider), `PortionCalculation`(정수 자릿수 연산, 최종 1회 half-up), `PortionInput.parseQuantity`(9/3자리, 허용 구분자 1개는 소수점), `AppState.currentSchemaVersion = 3`과 schema 2 전용 reader `decodeSchema2`, `StoreInspection.legacySchema2`, `MigrationCoordinator.promoteSchema2`와 증거 파일 `schema2-app-state.json`·`schema-promotion.json`, 복구 종류 `schemaBackupFailed`·`schemaBackupMismatch`. 이번 업데이트 전체(Q1+Q2+S1)는 아직 완료가 아니다.

