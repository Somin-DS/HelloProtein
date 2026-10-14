# 섭취량과 통계 구현 증거

2026-10-14 시작. 계획: [검색 음식 섭취량과 통계 구현 계획](../../quantity-statistics-implementation-plan.md). 세 단계(Q1 → Q2 → S1) 중 **Q1만 완료**했고, Q2 섭취량 화면과 S1 통계는 미착수다. 이 문서는 이번 업데이트 전체의 완료 증거가 아니다. 실기기 빌드·설치·데이터 초기화는 하지 않았다.

## Q1 계산과 저장 계약 (브랜치 `feat/renewal-quantity-q1`)

### 구현

| 위치 | 내용 |
| --- | --- |
| `HelloProteinCore/.../PortionCalculation.swift` (신규) | `PortionDecimal`(정준 십진 문자열), `PortionInput.parseQuantity`(9/3자리, 허용 구분자 1개는 항상 소수점), `PortionCalculation.centigrams`(10진 자릿수 배열 곱셈·`UInt64` 나눗셈, 밀리그램 몫의 마지막 자리로 half-up 1회), `DigitArithmetic`. `Double`·`Decimal`·epsilon 없음 |
| `RecordDomain.swift` | `CalculationBasis`(proteinGramsText·referenceQuantity·origin·provider, 유효숫자 18·소수 9자리 제한), `FoodRecord.calculationBasis`와 불변식(quantity 존재·`source.search`·단위 일치·입력 범위·protein == 계산값), `init(id:day:name:quantity:basis:)`, `withQuantity`, `withDirectProtein`(userDefined 전환), `withChanges`는 basis 기록의 단백질 변경을 userDefined로 라우팅. decode 시 schema 2 reader에서는 basis 키 존재를 손상으로 보고 |
| `AppState.swift`, `AppStateStore.swift` | `currentSchemaVersion = 3`, `promotableSchemaVersion = 2`, `decodeSchema2`(전체 불변식 검사 후 메모리에서 schema 3), `StoreInspection.legacySchema2`, `load()`는 schema 2를 열지 않음 |
| `SearchRecordBatch.swift` | `SearchSelection.basis`, 기록 생성 시 basis 재검증, `SearchBatchError.basisMismatch` |
| `MigrationCoordinator.swift` | `promoteSchema2`: 원본 바이트 재읽기·동일성 확인 → `schema2-app-state.json` 백업(기존 백업은 SHA-256 대조, 덮어쓰지 않음) → 기존 승격 증거 대조 → `store.commit` → reload 비교 → `schema-promotion.json`(fromSchema·toSchema·backupSHA256·byteCount·promotedAt·`schema-promotion-<UUID>` operationID). `.ready` 파일 옆에 유효한 백업만 있고 마커가 없으면 마커 복원. 저장 파일 없음 + 승격 증거/백업 → `storeLost`. `RecoveryKind.schemaBackupFailed`·`schemaBackupMismatch` |
| 앱 | 복구 문구 2종(ko/en), `RecordHomeViewModel`의 `basisMismatch` → `selectionChanged` 매핑. 화면 변경 없음 |

기존 기록은 모두 basis nil로 보존되고, 이름·단백질 직접 편집은 기존대로 basis 없이 유지된다. 계산 fixture는 Android 공유용 [portion-calculation.json](fixtures/portion-calculation.json)이며 Core 테스트가 같은 파일을 읽는다.

### 자동 테스트와 빌드 (2026-10-14)

| 대상 | 결과 | 로그 |
| --- | --- | --- |
| `swift test` HelloProteinCore | **87개 통과, 0 실패** (신규 `PortionCalculationTests` 17개, `AppStateStoreTests` schema 3/2 갱신 2개) | `/private/tmp/hp-quantity-core` |
| `swift test` MigrationCore | **82개 통과, 0 실패** (신규 `SchemaPromotionTests` 18개) | `/private/tmp/hp-quantity-migration` |
| `xcodebuild test` Debug, iPhone 17 / iOS 26.5 시뮬레이터 | **123개 통과, 0 실패** (기존 앱 테스트 회귀) | `/private/tmp/hp-quantity-app-tests.log` |
| `xcodebuild build` Release, generic iOS Simulator | BUILD SUCCEEDED | `/private/tmp/hp-quantity-release.log` |

신규 테스트가 덮는 계획의 검증 표 항목: 계산(필수 수치 4종·half-up 경계·0.004g 거부·반복 재편집·Int64 경계·overflow), 입력(점·쉼표 locale·붙여넣기 형태·공백·0·음수·NaN·exponent·그룹 구분자·자릿수 상한·단위 불일치·옛 긴 quantity decode 유지), basis(raw 1.005 보존·계산 protein 검증·직접수정 전환·이름 수정·기존 nil 기록 무변경·손상 basis 오류), 승격(schema 2 정상·nil lastOperationID·백업 지문 불일치·손상·읽기 실패·쓰기 실패·모든 중단 지점과 재실행·마커 누락·완료 증거+대상 없음·higher schema·schema 2 안의 basis 거부·schema 1/Realm/fresh 경로·schema 1+Realm 충돌 유지), 보존(ID·날짜·단백질·quantity·signed 보정·원문·목표·favorites/searchHistory·migration 동일·구버전 reader의 schema 3 거부).

### 시뮬레이터의 실제 schema 2 파일 승격

두 시뮬레이터에는 이전 세션의 합성 fixture로 만든 **schema 2** 저장 파일이 있었다. Debug 빌드를 설치하고 `-HelloProteinRenewalFlow YES`로 실행했다. 전체 저장 파일은 증거에 복사하지 않았고 [promote.sh](promotion/promote.sh)·[collect.sh](promotion/collect.sh)가 만든 요약만 남겼다.

| 기기 | 시나리오 | 결과 |
| --- | --- | --- |
| HelloProtein iPhone SE (iOS 26.5) | 정상 승격 | [summary](promotion/se-normal/summary.json): 46개 기록·9일·즐겨찾기 4·최근 검색 7·목표 2, `lastOperationID`·`migration` 동일, schemaVersion 외 내용 동일(`contentIdenticalExceptSchemaVersion: true`), basis 키 0개, 백업 바이트가 원본과 동일(`backupIdenticalToBefore: true`, SHA `bf5a4b5d…`), [승격 증거](promotion/se-normal/schema-promotion.json). [홈 화면](screenshots/01-se-home-after-promotion.png)에 전날 검색 기록 12.18g/100g 유지 |
| HelloProtein iPhone 17 (iOS 26.5) | `-HelloProteinInterruptAt afterReplace`로 교체 직후 프로세스 종료 → 재실행 | 중단 직후: 파일은 schema 3, `schema2-app-state.json` 존재, `schema-promotion.json` 없음([디렉터리](promotion/17-interrupt-after-replace/migration-dir-after.txt)는 재실행 후). 재실행: 홈 정상 진입, 승격 증거가 백업 SHA `7a336ff9…`로 작성됨, 41개 기록·내용 동일([summary](promotion/17-interrupt-after-replace/summary.json)). [중단 직후](screenshots/02-17-after-crash-at-afterReplace.png), [재실행 홈](screenshots/03-17-home-after-resume.png) |

### 미검증·범위 밖

- Q2 섭취량 편집 화면, Q2의 검색 세션·pending 회귀, S1 통계 전부. 통합 UI 시나리오(12.18g/100g → 150g → 18.27g → 통계 → 200g → 24.36g → 삭제)는 Q2·S1 뒤에 실행한다.
- 사용자 실사용 파일의 승격은 출시 전 별도 조건이다. 위 시뮬레이터 파일은 합성 fixture다.
- 실기기(Som, iPhone 17) 설치는 하지 않았다.
