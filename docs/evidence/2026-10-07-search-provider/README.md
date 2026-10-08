# 2026-10-07 검색 공급자 검증(B0) 증거

[검색 계획](../../search-implementation-plan.md)의 B0 항목이다. 확인일은 모두 2026-10-07(UTC 10:37–10:56)이며, 아래에 적지 않은 것은 확인하지 않은 것이다. 인증키는 어디에도 쓰지 않았다. USDA 호출은 공개 `DEMO_KEY`로만 했고, 식약처 호출은 공개 `sample` 경로로만 했다.

## 요약

| 공급자 | 결론 |
| --- | --- |
| 영어 로컬 카탈로그 `Assets/Protein-En.json` | **후속 전체 대조로 정정.** 2,196행은 공식 SR Legacy CSV와 이름·단백질 값이 정확히 일치. 34행 값 불일치, 102행 이름 미대응. 정확히 일치한 행만 100 g 기준을 부여하며 나머지는 자동 추가 불가. [전체 대조](../2026-10-08-search-correction/README.md). |
| 한국어 식약처 `I2790`(레거시 코드가 쓰던 서비스) | **사용 불가.** 공개 샘플 호출이 `ERROR-310 해당하는 서비스를 찾을 수 없습니다`를 돌려준다. 정보 페이지 자체가 `식품영양성분DB(~2023)`로 종료 표기. 게다가 단백질 필드는 100 g이 아니라 **1회제공량당**이었다. |
| 한국어 후속 후보 공공데이터포털 15127578 | **미검증.** 이 환경에서 `www.data.go.kr`가 연결 시간 초과(40 s)로 열리지 않아 공식 계약(파라미터·필드·페이지·오류코드)을 읽지 못했다. 계정·키 발급이 필요하므로 사용자 결정 사항이다. |

따라서 이번 PR은 영어 검색만 자동 기록을 허용하고, 한국어는 네트워크 호출 없이 `공급자 사용 불가` 상태를 보여준다(`UnconfiguredSearchProvider`, provider ID `mfds-korean`). ATS 완화나 임의 서비스 교체는 하지 않았다. 이름만 복사하는 fallback을 한국어 완료로 치지 않는다.

## 영어: USDA SR Legacy

### 출처와 이용 조건

| 항목 | 근거 | 확인일 |
| --- | --- | --- |
| 데이터 식별 | `Protein-En.json` 2,332행 `{Food, Protein}`. 이름이 유일하고 0 값 144행. SHA-256 `cd856775ea108b0a450d7d317427495692b0c57fbe6467f8ec0a2901a4f863b4`. | 2026-10-07 |
| 원본 데이터셋 | FoodData Central **SR Legacy** 데이터 타입. 공식 문서 페이지 `https://fdc.nal.usda.gov/data-documentation/`: “Historic data on food components including nutrients derived from analyses, calculations, and published literature”, “Final release April 2018”. | 2026-10-07 |
| 기준량 | SR-Legacy 문서 PDF `https://www.ars.usda.gov/ARSUserFiles/80400525/Data/SR-Legacy/SR-Legacy_Doc.pdf` Nutrient Data 파일 정의: `Nutr_Val N 10.3 N Amount in 100 g, edible portion`. 7,793 품목, SR28(2015) 기반 최종판(“This is the last release of the database in its current format”). | 2026-10-07 |
| 이용·재배포 | API 가이드 `https://fdc.nal.usda.gov/api-guide/`: 데이터는 “CC0 1.0 Universal (CC0 1.0)”, “in the public domain and they are not copyrighted”. | 2026-10-07 |
| 출처 표기 | API 가이드 제안 인용 “U.S. Department of Agriculture, Agricultural Research Service. FoodData Central, 2019. fdc.nal.usda.gov.” SR-Legacy PDF 제안 인용 “US Department of Agriculture (USDA), Agricultural Research Service, Nutrient Data Laboratory. USDA National Nutrient Database for Standard Reference, Legacy. Version Current: April 2018.” 앱 결과 행에는 `renewal_search_source_usda`(“USDA FoodData Central, SR Legacy”)를 표시. | 2026-10-07 |
| 식별자 | 파일에는 NDB 번호·fdcId가 없다. 로컬 항목 ID는 `usda-sr-legacy-local|protein-en.2332.2|<행 위치>`로 만든다(`EnglishCatalogProvider.catalogVersion`). 파일 교체 시 버전을 올려야 하며 `EnglishCatalogProviderTests`가 SHA·행 수·버전을 고정한다. 이름만으로 다른 데이터셋과 합치지 않는다. | 2026-10-07 |

### 행 대응 대조 (API `DEMO_KEY`, `https://api.nal.usda.gov/fdc/v1/foods/search?dataType=SR%20Legacy`)

| 행 | 파일 이름·값(g) | FDC 검색 결과 | 비고 |
| --- | --- | --- | --- |
| 5 | Cheese, brie 20.75 | fdcId 172177(NDB 01006) protein 20.8 g | 상세 엔드포인트(`/food/172177?format=abridged&nutrients=203`, 2026-10-08 01:25Z)도 20.8 g. FDC는 SR Legacy 단백질을 소수 1자리로 제공한다. [fixtures/usda-fdc-172177-abridged.json](fixtures/usda-fdc-172177-abridged.json) |
| 941 | Celeriac, raw 1.5 | fdcId 170400(NDB 11141) protein 1.5 g | 일치 |
| 1458 | Veal, leg (top round), separable lean and fat, cooked, braised 36.16 | fdcId 173818(NDB 17095) protein 36.2 g | 상세 엔드포인트(01:25Z)도 36.2 g |
| 4 | Cheese, brick 23.24 | fdcId 172176(NDB 01005) protein 23.2 g | 상세 엔드포인트(01:25Z)도 23.2 g. NDB 01001–01005 → fdcId 173410, 173411, 173412, 172175, 172176(리서치 에이전트 확인) |
| 318 | Toddler formula, MEAD JOHNSON, ENFAGROW … 13 | 검색 0건 | 상표 포함 긴 이름은 검색 API에서 못 찾음. 파일 행은 그대로 둔다(값은 미대조). |
| 421, 1199 | Turkey …, Beverages, carbonated, cola, regular | HTTP 400 | 쿼리 특수문자로 검색 실패. 미대조. |

파일의 소수 2자리 값(20.75, 36.16, 23.24)은 SR-Legacy ASCII 형식(`Nutr_Val N 10.3`)의 정밀도와 맞고, FDC API(검색·상세 모두)는 같은 품목을 소수 1자리(20.8, 36.2, 23.2)로 제공한다. 대조한 4건 모두 반올림하면 일치했지만, 2자리 수준의 정확 일치는 SR-Legacy 원본 ASCII/CSV 배포본(ARS 사이트)으로 대조해야 하며 이번에는 하지 않았다. 이번 PR은 파일 값을 **원문 그대로** 손실 없이 변환해 저장하며(`ProteinGramsText`, `Double*100` 금지), 전 행이 변환 오류 없이 양수/0으로 나뉘는 것을 테스트로 확인했다.

### 앱 처리 규칙(구현 반영)

- 숫자는 텍스트로 유지해 Decimal 자리수로 변환(`CatalogJSON`, `ProteinGramsText`). 3번째 소수 자리에서 half-up: `1.005 → 101 cg`(반올림 안내 표시), `0.004 → 0`(선택 불가).
- 0 g 144행은 보이되 선택 불가(`zeroProtein`), 지수·음수·숫자 아님은 `invalidProtein`로 구분 표시. 후속 수정에서 원본 대조에 실패한 136행은 `unknownReference`로 자동 추가를 차단한다.
- 저장 시 `FoodRecord(source: .search, quantity: FoodQuantity("100", .gram))`. 공급자 ID는 `legacySourceID`에 넣지 않는다.
- 필터: trim 후 대소문자·발음부호 무시 부분 일치, 파일 순서 유지, 빈 검색어는 결과 없음(최근 검색 표시). 페이지 없음(`nextPage == nil`).

## 한국어: 식약처 I2790

| 항목 | 근거 | 확인일 |
| --- | --- | --- |
| 공식 정보 페이지 | `https://www.foodsafetykorea.go.kr/api/openApiInfo.do?menu_grp=MENU_GRP31&menu_no=661&show_cnt=10&start_idx=1&svc_no=I2790&svc_type_cd=API_TYPE06` — 서비스명 **식품영양성분DB(~2023)**, 최종수정일 2021-08-30, API호출제한 2000. URL 형식 `http://openapi.foodsafetykorea.go.kr/api/인증키/서비스명/요청파일타입/요청시작위치/요청종료위치/변수명=값`(문서상 http). | 2026-10-07 |
| 필드 정의 | `DESC_KOR 식품이름`, `SERVING_SIZE 총내용량`, `SERVING_UNIT 총내용량단위`, `NUTR_CONT3 단백질(g)(**1회제공량당**)`. 레거시 코드(`ProteinModel.swift`)가 이 값을 100 g 기준처럼 다뤘던 것은 근거가 없었다. | 2026-10-07 |
| 샘플 호출 | `https://openapi.foodsafetykorea.go.kr/api/sample/I2790/json/1/5/DESC_KOR=계란` → HTTP 200, 본문 `{"I2790":{"total_count":"0","RESULT":{"MSG":"해당하는 서비스를 찾을 수 없습니다. 요청인자 중 SERVICE를 확인하십시오.","CODE":"ERROR-310"}}}`. 평문 http도 동일. [fixtures/i2790-sample-error-310.json](fixtures/i2790-sample-error-310.json) | 2026-10-07 10:37Z |
| 대조 호출 | 같은 샘플 경로의 다른 서비스 `I0030`는 200과 45,840건 응답(샘플 경로 자체는 정상). [fixtures/i0030-sample-envelope.json](fixtures/i0030-sample-envelope.json)(행 내용 생략) | 2026-10-07 10:37Z |
| 결론 | 서비스 ID가 더 이상 라우팅되지 않으므로(ERROR-310) 인증키가 있어도 같은 결과일 가능성이 높다. 발급 키로 재검증하지 않았다. 이 서비스로 자동 기록을 허용하지 않는다. | — |

### 후속 후보와 선택지

| 선택지 | 범위·비용 | 데이터 차이 | 상태 |
| --- | --- | --- | --- |
| 공공데이터포털 15127578 “식품의약품안전처_식품영양성분DB정보”(리서치 에이전트가 I2790 후속으로 지목) | data.go.kr 계정·활용신청·인증키 필요(무료, 2차 출처상 KOGL 제1유형). 키는 기존 `API_KEY` 빌드 설정(`Config.xcconfig` + ignored `Secrets.xcconfig`)으로만 주입 가능. | JSON/XML 제공으로 알려졌으나 파라미터·필드명·기준량(100 g vs 1회제공량)·페이지·오류코드·HTTPS 여부를 **공식 문서로 읽지 못함**(`https://www.data.go.kr/data/15127578/openapi.do` 연결 시간 초과). | 사용자 결정: 계정·키 발급 후 계약을 읽고 B0 표를 채운 다음 구현. |
| 한국어 로컬 카탈로그(공개 데이터 파일 내장) | 데이터 다운로드·라이선스 확인·파일 버전 관리. | 식약처 영양성분 공개 파일은 1회제공량·100 g 양쪽 컬럼이 있는 판본이 있어 100 g 컬럼을 쓰면 영어와 같은 정책 적용 가능. | 미검토(파일·라이선스 미확인). |
| 유료/상용 영양 API | 계정·요금·SDK. | — | 계획상 금지(새 SDK·구독 없음). |

## 앱 인증 설정

- 로컬에 `Secrets.xcconfig`가 없다. `API_KEY`는 빈 값으로 빌드되고 Info.plist의 `API_KEY = ${API_KEY}`는 빈 문자열이 된다. 이번 PR의 한국어 공급자는 키 유무와 무관하게 호출하지 않으므로 키 누락·빈 문자열·치환 안 된 `$(API_KEY)` 처리 코드는 이번에 추가하지 않았다(후속 공급자 구현 시 `notConfigured` 분기로 들어간다).
- 키·URL을 로그·오류 문구·fixture·캡처에 쓰지 않는다. `SearchProviderError.network(String)`에는 URL을 넣지 않는다(영어 공급자는 네트워크를 쓰지 않음).
- `NSAllowsArbitraryLoads`(레거시 ATS 완화)는 손대지 않았다.

## 표본 응답

| 종류 | 파일 |
| --- | --- |
| 영어 정상 행(0·소수 2자리·마지막 행 포함) | [fixtures/protein-en-sample-rows.json](fixtures/protein-en-sample-rows.json) — 행 0, 1, 2, 4, 5, 941, 1458, 2331 |
| 영어 0건 | 빈 결과는 필터 결과이므로 파일 없음(`EnglishCatalogProviderTests` “zzzz-no-such-food”) |
| 영어 로드 실패 | 테스트가 임시 파일로 생성(잘린 JSON, 문자열 Protein) |
| 한국어 오류 | [fixtures/i2790-sample-error-310.json](fixtures/i2790-sample-error-310.json) |
| 한국어 정상·0건·페이지 끝 | **없음** — 서비스 응답을 받을 수 없어 계약 테스트를 만들지 않았다. |

## 후속 정정

2026-10-08 공식 CSV 전체 대조로 위 표본 검증의 한계를 해결했다. 기존 파일 전체를 SR Legacy 부분집합이라고 단정한 결론은 철회한다. 원문은 유지하고 정확 일치 2,196행에만 VerifiedFDCID를 추가했다. 기존 SHA는 메타데이터 추가 전 파일의 값이다. 최신 SHA·재현 절차·불일치 목록은 [수정 증거](../2026-10-08-search-correction/README.md)와 보고서를 따른다.

## 미해결

- 원본 대조 결과 136행의 현재 값 또는 출처는 여전히 미확인이다. 기존 값은 보존하고 자동 기록은 차단한다.
- 한국어 후속 공급자 계약: 위 선택지 표 참조. 결정 전까지 한국어 검색은 ‘사용 불가’ 상태다.
