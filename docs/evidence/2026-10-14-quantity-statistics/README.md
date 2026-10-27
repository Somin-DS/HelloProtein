# 섭취량과 통계 구현 증거

2026-10-14 시작. 계획: [검색 음식 섭취량과 통계 구현 계획](../../quantity-statistics-implementation-plan.md). 세 단계(Q1 → Q2 → S1) 중 **Q1·Q2를 완료**했고, S1 통계와 통합 검증은 미착수다. 이 문서는 이번 업데이트 전체의 완료 증거가 아니다. 실기기 빌드·설치·데이터 초기화는 하지 않았다.

## Q1 계산과 저장 계약 (브랜치 `feat/renewal-quantity-q1`)

### 구현

| 위치 | 내용 |
| --- | --- |
| `HelloProteinCore/.../PortionCalculation.swift` (신규) | `PortionDecimal`(정준 십진 문자열), `PortionInput.parseQuantity`(9/3자리, 허용 구분자 1개는 항상 소수점), `PortionCalculation.centigrams`(10진 자릿수 배열 곱셈·`UInt64` 나눗셈, 밀리그램 몫의 마지막 자리로 half-up 1회), `DigitArithmetic`. `Double`·`Decimal`·epsilon 없음 |
| `RecordDomain.swift` | `CalculationBasis`(proteinGramsText·referenceQuantity 모두 정준 문자열, origin·provider, 유효숫자 18·소수 9자리 제한), `FoodRecord.calculationBasis`와 불변식(quantity 존재·`source.search`·단위 일치·입력 범위·protein == 계산값), `init(id:day:name:quantity:basis:)`, `withQuantity`, `withDirectProtein`(userDefined 전환). `withChanges`는 basis 기록의 단백질 변경을 `proteinLockedByBasis`로 거부해 basis를 조용히 바꾸지 않음(명시적 전환은 `withDirectProtein`만). decode 시 schema 2 reader에서는 basis 키 존재를 손상으로 보고 |
| `AppState.swift`, `AppStateStore.swift` | `currentSchemaVersion = 3`, `promotableSchemaVersion = 2`, `decodeSchema2`(전체 불변식 검사 후 메모리에서 schema 3), `StoreInspection.legacySchema2`, `load()`는 schema 2를 열지 않음 |
| `SearchRecordBatch.swift` | `SearchSelection.basis`, 기록 생성 시 basis 재검증, `SearchBatchError.basisMismatch` |
| `MigrationCoordinator.swift` | `promoteSchema2`: 원본 바이트 재읽기·동일성 확인 → 기존 승격 증거 대조(불일치면 백업도 쓰지 않고 정지) → `schema2-app-state.json` 백업(기존 백업은 SHA-256 대조, 덮어쓰지 않음) → `store.commit` → reload 비교 → `schema-promotion.json`(fromSchema·toSchema·backupSHA256·byteCount·promotedAt·`schema-promotion-<UUID>` operationID). `.ready` 파일 옆에 마커가 없고 백업이 현재 파일 내용과 정확히 같은 schema 2 문서로 decode될 때만 마커 복원(promotedAt은 복원 시각). 저장 파일 없음 + 승격 증거/백업 → `storeLost`. `RecoveryKind.schemaBackupFailed`·`schemaBackupMismatch` |
| 앱 | 복구 문구 2종(ko/en), `RecordHomeViewModel`의 `basisMismatch` → `selectionChanged` 매핑. 화면 변경 없음 |

기존 기록은 모두 basis nil로 보존되고, 이름·단백질 직접 편집은 기존대로 basis 없이 유지된다. 계산 fixture는 Android 공유용 [portion-calculation.json](fixtures/portion-calculation.json)이며 Core 테스트가 같은 파일을 읽는다.

### 자동 테스트와 빌드 (2026-10-14)

| 대상 | 결과 | 로그 |
| --- | --- | --- |
| `swift test` HelloProteinCore | **87개 통과, 0 실패** (신규 `PortionCalculationTests` 17개, `AppStateStoreTests` schema 3/2 갱신 2개; 검토 반영 후 재실행) | `/private/tmp/hp-quantity-core` |
| `swift test` MigrationCore | **82개 통과, 0 실패** (신규 `SchemaPromotionTests` 18개; 검토 반영 후 재실행) | `/private/tmp/hp-quantity-migration` |
| `xcodebuild test` Debug, iPhone 17 / iOS 26.5 시뮬레이터 | **123개 통과, 0 실패** (기존 앱 테스트 회귀; 검토 반영 후 재실행) | `/private/tmp/hp-quantity-app-tests-2.log` |
| `xcodebuild build` Release, generic iOS Simulator | BUILD SUCCEEDED (검토 반영 후 재실행) | `/private/tmp/hp-quantity-release-2.log` |

### 코드 검토 반영 (2026-10-14)

별도 검토 패스(code-reviewer)의 지적과 반영: (1) `withChanges(protein:)`가 basis 기록의 단백질 변경을 조용히 userDefined로 바꾸던 것을 `proteinLockedByBasis` 오류로 변경, (2) 공개 `PortionCalculation.centigrams`에 19~20자리 기준량을 넘기면 긴 나눗셈 precondition으로 크래시하던 것을 `invalidValue`로 보고(테스트 추가), (3) 승격 증거 불일치 정지 경로에서 백업을 먼저 쓰던 순서를 바꿔 아무것도 쓰지 않음(테스트가 증거 디렉터리 불변을 확인), (4) `.ready` 옆 마커 복원은 백업이 현재 내용과 같은 문서일 때만, (5) basis의 referenceQuantity도 정준 문자열로 저장, (6) U+2212 마이너스는 `negative`로 보고. 경합에서만 도달하는 `schemaBackupFailed`/`schemaBackupMismatch` 구분 오류와 입력의 앞뒤 0 제거 후 자릿수 계산(값 기준 9/3자리)은 변경하지 않았다.

신규 테스트가 덮는 계획의 검증 표 항목: 계산(필수 수치 4종·half-up 경계·0.004g 거부·반복 재편집·Int64 경계·overflow), 입력(점·쉼표 locale·붙여넣기 형태·공백·0·음수·NaN·exponent·그룹 구분자·자릿수 상한·단위 불일치·옛 긴 quantity decode 유지), basis(raw 1.005 보존·계산 protein 검증·직접수정 전환·이름 수정·기존 nil 기록 무변경·손상 basis 오류), 승격(schema 2 정상·nil lastOperationID·백업 지문 불일치·손상·읽기 실패·쓰기 실패·모든 중단 지점과 재실행·마커 누락·완료 증거+대상 없음·higher schema·schema 2 안의 basis 거부·schema 1/Realm/fresh 경로·schema 1+Realm 충돌 유지), 보존(ID·날짜·단백질·quantity·signed 보정·원문·목표·favorites/searchHistory·migration 동일·구버전 reader의 schema 3 거부).

### 시뮬레이터의 실제 schema 2 파일 승격

두 시뮬레이터에는 이전 세션의 합성 fixture로 만든 **schema 2** 저장 파일이 있었다. Debug 빌드를 설치하고 `-HelloProteinRenewalFlow YES`로 실행했다. 전체 저장 파일은 증거에 복사하지 않았고 [promote.sh](promotion/promote.sh)·[collect.sh](promotion/collect.sh)가 만든 요약만 남겼다.

| 기기 | 시나리오 | 결과 |
| --- | --- | --- |
| HelloProtein iPhone SE (iOS 26.5) | 정상 승격 | [summary](promotion/se-normal/summary.json): 46개 기록·9일·즐겨찾기 4·최근 검색 7·목표 2, `lastOperationID`·`migration` 동일, schemaVersion 외 내용 동일(`contentIdenticalExceptSchemaVersion: true`), basis 키 0개, 백업 바이트가 원본과 동일(`backupIdenticalToBefore: true`, SHA `bf5a4b5d…`), [승격 증거](promotion/se-normal/schema-promotion.json). [홈 화면](screenshots/01-se-home-after-promotion.png)에 전날 검색 기록 12.18g/100g 유지 |
| HelloProtein iPhone 17 (iOS 26.5) | `-HelloProteinInterruptAt afterReplace`로 교체 직후 프로세스 종료 → 재실행 | 중단 직후: 파일은 schema 3, `schema2-app-state.json` 존재, `schema-promotion.json` 없음([디렉터리](promotion/17-interrupt-after-replace/migration-dir-after.txt)는 재실행 후). 재실행: 홈 정상 진입, 승격 증거가 백업 SHA `7a336ff9…`로 작성됨, 41개 기록·내용 동일([summary](promotion/17-interrupt-after-replace/summary.json)). [중단 직후](screenshots/02-17-after-crash-at-afterReplace.png), [재실행 홈](screenshots/03-17-home-after-resume.png) |

### Q1 미검증·범위 밖

- Q2 섭취량 편집 화면, Q2의 검색 세션·pending 회귀, S1 통계 전부. 통합 UI 시나리오(12.18g/100g → 150g → 18.27g → 통계 → 200g → 24.36g → 삭제)는 Q2·S1 뒤에 실행한다.
- 사용자 실사용 파일의 승격은 출시 전 별도 조건이다. 위 시뮬레이터 파일은 합성 fixture다.
- 실기기(Som, iPhone 17) 설치는 하지 않았다.

## Q2 섭취량 화면과 세션 (브랜치 `feat/renewal-quantity-q2`, Q1 위에 쌓음)

### 구현

| 위치 | 내용 |
| --- | --- |
| `Renewal/PortionEditorView.swift` (신규, 앱·테스트 타깃에 등록) | `PortionEditorPolicy`(locale 구분자 파싱 → basis 계산 미리보기 `PortionPreview.valid/input/calculation`, 정확 문자열 dirty, apply 가능 조건), `SearchResultItem.calculationBasis`(기준량이 9/3자리 범위이고 정확 계산이 공급자 검증값을 재현할 때만 basis; 아니면 basis 없이 기존 방식 추가), `PortionText`, 공용 `PortionAmountEditor`(기준 문구·단위 고정 입력·결과 또는 오류, 이전 정상값 미표시), `SearchAmountEditorView` |
| `Search/SearchSessionModel.swift` | 행별 `amountDrafts`(선택 해제·새 검색·언어 변경·전체 해제 시 폐기), `AmountEditTarget`(행 스냅샷·basis·record ID·시작 수량·세대), `applyAmount`는 같은 선택·같은 스냅샷·같은 세대·같은 record ID일 때만 적용(아니면 `selectionChanged`), `selections`는 basis 행에 적용 수량과 계산 단백질을 싣고 선택 순서·record ID 유지 |
| `Search/SearchTab.swift` | 선택된 basis 행에 독립 44pt ‘섭취량 변경’ 버튼(`renewal.search.editAmount.<id>`)과 ‘먹은 양 150 g · 기록될 단백질 18.27 g’ 표시, basis 없는 선택 행은 사유 안내 |
| `AddSheet.swift`, `AddSheetPolicy.swift` | 시트 내부 편집 route(탭·선택 바 대신 편집 화면과 하단 취소/적용 바), 적용은 세션 초안만 변경(쓰기 0회), 변경 중 취소·뒤로·풀다운은 `.discardAmountEdit` 확인 후 마지막 적용값으로 복귀, `isSearchDirty(selectionCount:amountDraftCount:)`, `canEditAmount`(busy/pending 잠금) |
| `RecordHomeViewModel.swift` | `updateRecordAmount`(basis에서 재계산, 이름 동시 변경, 즐겨찾기 half 동일 commit), `updateRecordDirectProtein`(명시적 userDefined 전환, 18 유효숫자 초과는 overflow; 저장된 단백질과 같은 값은 basis를 바꾸지 않는 이름 편집), 세 편집 경로 모두 결과가 저장된 기록과 같고 즐겨찾기 요청이 없으면 commit 없는 no-op, `ActionError.amount/.calculation`, `RecordDomainError.portion` 매핑. 기존 `updateRecord`는 basis 기록의 단백질 변경을 integrity 오류로 거부 |
| `RecordHomePrototypeView.swift`, `Components/FoodRow.swift` | basis 기록 편집기: 이름 + 먹은 양 입력 + 계산 결과, ‘단백질 직접 수정’ 토글(저장된 양 고정 표시, 토글 자체는 저장 안 함, 끄면 원래 값 복원), ‘현재 단백질 값만 즐겨찾기에 저장’ 안내; basis 없는 기록은 ‘저장된 기준량’ 문구로 기존 편집 유지. 홈 행은 basis 기록에 ‘먹은 양 150 g’, 옛 기록에 ‘100 g 기준’ |
| ko/en strings | `renewal_amount_*`, `renewal_edit_direct_protein*`, `renewal_edit_saved_reference`, `renewal_favorite_protein_only`, `renewal_error_amount_title` |

### 자동 테스트와 빌드 (2026-10-14)

| 대상 | 결과 | 로그 |
| --- | --- | --- |
| `xcodebuild test` Debug, iPhone 17 / iOS 26.5 | **131 통과, 0 실패** | `/private/tmp/hp-q2-app-tests.log` |
| `xcodebuild build` Release, generic iOS Simulator | BUILD SUCCEEDED | `/private/tmp/hp-q2-release.log` |
| `swift test` HelloProteinCore·MigrationCore | Q2는 Core를 바꾸지 않음(Q1 결과 87/82 유지) | — |

신규 테스트: `PortionEditorPolicyTests` 3개(미리보기·오류 종류·dirty/apply·문자열·행의 basis 부여 조건), `SearchSessionAmountTests` 3개(여러 음식 서로 다른 수량, 선택 순서·recordID, 해제/재선택, 새 검색 초기화, 바뀐 페이지·해제·세대 변경 후 stale 적용 거부, 최종 저장 시 늦은 페이지에 대한 고정), `RecordHomeViewModelTests` 2개(basis 행 일괄 저장 또는 0행, 수량 편집 재계산·150g 복귀 동일성·직접 단백질 전환·오류 종류·즐겨찾기·재로드), `AddSheetPolicyTests` 갱신.

### UI 하네스 (영어 카탈로그, 결정론적)

하네스: [ui-harness/Smoke.swift](ui-harness/Smoke.swift) 테스트 46–49, `run-test.sh`. 값: Cheese, brie 20.75 g/100 g → 150 g = 31.125 → **31.13**(반올림 안내), 200 g = **41.5**; Butter, salted 0.85 → 50 g = 0.425 → **0.43**; Butter oil, anhydrous 0.28 → 10 g = **0.03**.

| 기기 | 실행 | 앱 설치본 | 46 적용·추가·기록 편집·직접 전환 | 47 한국어 AX-XL 편집기 | 48 busy 잠금(지연 8초) | 49 pending 잠금 → notApplied | 결과 번들 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| iPhone SE / iOS 26.5 | `s1-se-193600` (최종, S1 50·52와 한 배치) | 19:24 빌드(Q2 검토 반영 + S1 전부) | 통과 | 통과 | 통과 | 통과 | `/private/tmp/hp-iphone-ui/results/s1-se-193600.xcresult` |
| iPhone 17 / iOS 26.5 | `s1-17-192510` (최종, S1 50·51과 한 배치) | 19:24 빌드(Q2 검토 반영 + S1 전부) | 통과 | 통과 | 통과 | 통과 | `/private/tmp/hp-iphone-ui/results/s1-17-192510.xcresult` |
| iPhone SE / iOS 26.5 | `q2-se-183255` | 18:13 빌드(검토 반영 **전**) | 통과 | 통과 | 실패(하네스 행 세기) | 통과 | `/private/tmp/hp-iphone-ui/results/q2-se-183255.xcresult` |
| iPhone SE / iOS 26.5 | `q2-se-184001` (48만) | 18:13 빌드(검토 반영 **전**) | — | — | 통과 | — | `/private/tmp/hp-iphone-ui/results/q2-se-184001.xcresult` |
| iPhone 17 / iOS 26.5 | `q2-17-183113` | 18:13 빌드(검토 반영 **전**) | 통과 | 통과 | 실패(하네스 행 세기) | 통과 | `/private/tmp/hp-iphone-ui/results/q2-17-183113.xcresult` |
| iPhone 17 / iOS 26.5 | `q2-17-184555` (48만) | 18:13 빌드(검토 반영 **전**) | — | — | 통과 | — | `/private/tmp/hp-iphone-ui/results/q2-17-184555.xcresult` |

**정정(2026-10-14 저녁)**: PR #12를 올릴 때 이 표의 183xxx·184xxx 실행을 ‘검토 반영 후’로 적었으나 사실이 아니다. 하네스는 앱을 빌드하지 않고 시뮬레이터에 설치된 앱에 붙는데, 그 시점 설치본은 18:13에 다른 빌드 폴더에서 설치한 것이었고 Q2 검토 반영(18:30 전후, 커밋 `aad3c8a`에 포함)은 들어 있지 않았다. 검토 반영 코드에 대한 46–49 실행은 위 ‘최종’ 두 행(19:09 빌드, S1 작업까지 포함한 현재 작업 트리)이며, 이전 실행은 반영 전 코드의 참고 기록으로만 남긴다. 최종 실행에 쓴 하네스(테스트 50–52와 행 식별자 세기 포함)는 S1 브랜치의 `ui-harness/`에 있다. 반영한 Q2 수정(동일 값 저장 생략, 같은 단백질 직접 수정 시 basis 유지, 자릿수 초과 매핑, 선택 변경 거부, 포커스)은 앱 단위 테스트 123개(`/private/tmp/hp-quantity-app-tests-2.log`)로 먼저 검증했고, 화면 흐름은 최종 실행으로 확인했다.

48의 첫 실패는 앱이 아니라 하네스의 `homeRowCount`가 원인이다(홈 목록이 LazyVStack이라 화면 밖 행은 접근성 트리에 없고, 반복 실행으로 길어진 오늘 목록을 고정 10회 스와이프로 끝까지 보지 못해 ‘추가 전’ 수를 적게 셈). 하네스를 화면 서명이 더 바뀌지 않을 때까지 스와이프하도록 고쳤으나, 같은 음식·같은 양의 행은 라벨이 같아 SE에서 한 화면을 넘기면 ‘보이는 수의 최댓값’으로는 셀 수 없었다(최종 전 실행 `s1-se-191253`·`s1-se-192507`에서 48만 행 세기로 실패, 저장 파일 확인 결과 기록은 정확히 1건 추가됨). 그래서 S1에서 홈 기록 행에 `renewal.record.<id>` 식별자를 붙이고 하네스가 스크롤 동안 식별자 집합을 모으며, 추가 시트가 완전히 닫힌 뒤에만 세도록 했다(닫히는 중에는 시트의 결과 행이 +1, 반쯤 가려진 홈 목록이 −1로 섞였다). 그 외 앱 코드는 바꾸지 않았다. 검토 반영 이전 실행(`q2-17-182245` 46·47·49 통과, SE 첫 실행은 결과 번들 마무리 단계에서 중단)은 참고용이다.

| 캡처 | 내용 |
| --- | --- |
| `q2-search-selected` | 선택 행의 ‘섭취량 변경’ 버튼(44pt) |
| `q2-amount-editor-default` / `-zero` / `-150` | 기준량 100 g 시작, 0 입력 시 오류만 표시, 150 g → 31.13 g(반올림 안내) |
| `q2-search-applied` | 행에 ‘먹은 양 150 g · 기록될 단백질 31.13 g’ |
| `q2-amount-discard-prompt` | 변경 후 취소 시 확인 |
| `q2-home-added` / `q2-home-200` | 홈 행 ‘먹은 양 150 g’ 31.13 g → 200 g 수정 후 41.5 g |
| `q2-record-edit` / `q2-record-direct` / `q2-record-user-basis` | 기록 편집기(먹은 양·계산 결과), 직접 수정 전환(양 고정), 사용자 기준으로 재계산 |
| `q2-ko-ax3-selected` / `-editor` / `-applied` | 한국어 AX-XL |
| `q2-search-busy` / `q2-home-busy-done` | 저장 중 모든 조작 잠금, 완료 후 0.43 g 행 |
| `q2-search-pending` / `q2-home-not-applied-added` | 이력 쓰기 미확정 시 잠금 → 확인 후 notApplied → 수량 적용·추가 |

스크린샷: [screenshots/q2/iphone-se](screenshots/q2/iphone-se/), [screenshots/q2/iphone-17](screenshots/q2/iphone-17/).

### 코드 검토 반영 (2026-10-14)

Q2 작업 트리를 별도 검토 pass로 살펴 다음을 고쳤다. 검토 후 앱 테스트·Release 빌드·UI 하네스는 다시 실행했다(위 표는 재실행 결과).

| 지적 | 반영 |
| --- | --- |
| ‘단백질 직접 수정’을 켜고 단백질을 바꾸지 않은 채 저장하면 공급자 basis가 반올림된 값의 userDefined basis로 조용히 교체됨 | `updateRecordDirectProtein`은 파싱한 단백질이 저장값과 같으면 `withChanges(name:)`로 처리해 basis·출처를 유지. 테스트 추가 |
| 같은 수량·이름으로 다시 저장해도 commit이 일어나고 operation ID가 소비됨(계획의 no-op 행 위반) | 세 편집 경로 모두 로드된 상태에서 결과가 저장된 기록과 같고 즐겨찾기 요청이 없으면 commit 없이 성공 반환. `modifyCalls` 불변 테스트 추가 |
| 편집 화면이 열린 채로 늦은 페이지가 유일한 선택 행을 떨어뜨리면 풀다운이 시트를 통째로 닫을 수 있음 | `shouldDismiss`에 `!isEditingAmount`를 더해 편집 중 풀다운은 항상 `cancelAmountEdit()`로 감 |
| `selections`가 행을 조용히 빠뜨리면 ‘N개 추가’의 N과 어긋남(현재는 도달 불가) | `addSearchSelected`에서 `batch.count == selected.count`가 아니면 `selectionChanged`로 중단 |
| `invalidBasis` 전부를 overflow로 보고 | 파싱한 단백질 문자열이 18 유효숫자를 넘는 경우만 overflow, 나머지는 integrity |
| basis 없는 선택 행 안내가 ‘기준량을 표시할 수 없다’로 사유를 좁게 말함(정확 계산이 공급자 값을 재현하지 못하는 경우도 포함) | 문구를 ‘여기서 섭취량을 다시 계산할 수 없어 표시된 양 그대로 추가’로 일반화 |
| 직접 수정 토글이 입력 중인 수량을 조용히 되돌림 | 안내 문구에 ‘스위치를 바꾸면 두 칸 모두 저장된 값으로 돌아간다’를 명시 |
| 포커스 이동 미구현 | 편집 진입 시 수량 필드에 `@FocusState` 포커스, 적용·취소·버리기 후 해당 행의 ‘섭취량 변경’ 버튼으로 `@AccessibilityFocusState` 복귀 |
| `addSearchSelected` 주석이 옛 동작을 설명 | 갱신 |

반영하지 않은 지적: AddSheet의 route 로직(버리기 확인·풀다운)과 편집기 토글 복원은 View 내부 상태라 단위 테스트 대신 UI 하네스 46·48·49로 확인한다. basis 없는 선택 행에 ‘이름만 사용’ 경로를 추가하는 것은 계획의 ‘선택 불가 행’ 범위와 달라 이번 PR에 넣지 않았다.

### Q2 미검증·범위 밖

- S1 통계 전부와 통합 UI 시나리오(실제 MFDS 검색 12.18 g/100 g → 150 g → 18.27 g → 통계 → 재실행 → 200 g → 24.36 g → 삭제)는 S1에서 실행한다. Q2 UI 증거는 번들 영어 카탈로그로 수행했고 한국어 API는 호출하지 않았다.
- 실기기 설치 없음.

## PR 11 시작 경로 리뷰 수정 (2026-10-27)

`app-state.json`과 기존 완료 마커가 없고 schema 2 백업 또는 승격 마커만 남은 상태에서도 앱이 renewal 경로로 진입하도록 `RenewalPaths.newStoreEvidenceExists()`를 수정했다. 손상 여부는 MigrationCoordinator가 검사한다. 기본 플래그가 꺼져 있어도 기존 UIKit/Realm 경로로 돌아가지 않고, 지원하지 않는 OS는 기존 unsupported 안내로 진입한다. 일반 legacy 캡처 디렉터리만 있는 경우의 기존 판정은 유지했다.

`RenewalLaunchPolicyTests.testPromotionEvidenceAloneBlocksLegacyWithoutOptIn`에서 두 증거 파일 각각의 실제 경로 일치, 손상된 내용, store/완료 마커 부재, 플래그 없음/명시 NO, 지원 OS/미지원 OS를 검증했다. 별도 임시 디렉터리만 사용하며 실사용 데이터는 변경하지 않는다.

수정 후 Debug 앱 테스트: iPhone SE / iOS 26.5 시뮬레이터 **124개 통과, 0 실패**, `TEST SUCCEEDED`. 로그 `/private/tmp/hp-pr11-fix-app-tests.log`. 리뷰 시 Q1 원본 Core 87개·MigrationCore 82개 통과를 확인했고 이번 수정은 해당 모듈을 변경하지 않았다. 이번 후속 수정에서 Release 빌드·수동 UI·실기기 검증은 추가로 실행하지 않았다.
