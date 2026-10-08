# PR 9 영어 카탈로그 검증 수정

2026-10-08. 표본 네 건만으로 전체 로컬 파일을 USDA SR Legacy의 100g 기준 데이터라고 단정했던 검토 문제를 수정한다.

## 공식 원본과 대조 방법

[USDA 다운로드 페이지](https://fdc.nal.usda.gov/download-datasets/)의 [SR Legacy 2018 CSV ZIP](https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_csv_2018-04.zip)을 사용했다. [SR Legacy 공식 정의](https://www.ars.usda.gov/ARSUserFiles/80400525/Data/SR-Legacy/SR-Legacy_Doc.pdf)의 Nutrient Data는 100g 가식부 기준이다.

ZIP SHA256: `b80817294b8850530aaedf2e515c02593b1824f763a0ff356e5c2081643e6fd0`.

`food.csv`의 sr_legacy_food description과 기존 Food가 완전히 같고, `food_nutrient.csv`의 nutrient_id 1003 값과 기존 Protein이 Decimal로 정확히 같은 유일한 항목만 인정한다. `nutrient.csv`에서 1003이 Protein/G인지도 검사한다. 대소문자·괄호·이름을 정규화하거나 근사값·반올림으로 맞추지 않는다.

| 결과 | 행 수 | 앱 동작 |
| --- | --- | --- |
| 이름과 단백질 값 정확 일치 | 2,196 | VerifiedFDCID를 부여하고 USDA 출처와 100g 기준량 표시. 0g 항목은 기존대로 선택 불가 |
| 같은 이름의 단백질 값 불일치 | 34 | 기존 값 유지, 출처 미확인 표시, 자동 추가 차단 |
| 같은 이름 없음 | 102 | 기존 값 유지, 출처 미확인 표시, 자동 추가 차단 |

예: cheddar는 로컬 23.3g, 공식 22.87g이며 whole milk는 로컬 3.28g, 공식 3.15g이다. 이 차이를 임의로 수정하지 않았다. 원문 이름·수치·순서 2,332행은 모두 보존했다. 저장된 사용자 기록·즐겨찾기는 변경하지 않는다. 미확인 행에서는 이름만 직접 입력으로 가져올 수 있다.

## 재현

저장소 루트에서 공식 ZIP을 내려받아 다음을 실행한다. 인증키는 필요 없다.

```sh
python3 scripts/verify_english_catalog.py /path/to/FoodData_Central_sr_legacy_food_csv_2018-04.zip
```

스크립트는 archive SHA, 전 행 검증 메타데이터, [행별 보고서](catalog-verification.json)를 대조하고 다르면 실패한다. `--write`는 같은 규칙으로 검증 메타데이터와 보고서를 생성한다. ZIP은 저장소에 포함하지 않는다.

카탈로그 버전 `protein-en.2332.2`, 새 SHA256 `d6a04da54c50f21d9a14d65af4f53f9e0a8048ab24f33fe59b87f9fbdba92d0e`. 테스트는 SHA와 일치·미일치 개수를 고정하고, 검증 메타데이터 없는 행에 기준량·USDA 출처가 부여되지 않음을 검사한다. 파일은 빌드에 내장되며 검증 ID는 네트워크 조회에 사용되지 않는다.

## 검증 결과

전체 대조 스크립트 통과. 기존 HEAD 대비 이름·단백질 값·행 순서 동일 검증 통과. iPhone SE / iOS 26.5 시뮬레이터 앱 테스트 **114개 통과, 0 실패**. 로그 `/private/tmp/hp-pr9-fix-tests.log`. 기존 Core 69개는 리뷰 단계에서 통과했고 이번 변경은 Core를 수정하지 않았다. 실기기 빌드·설치는 병합 후 Som(iPhone 17)을 대상으로 진행한다.
