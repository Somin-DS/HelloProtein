# 한국어 검색 공급자 연결

2026-10-14. 브랜치 `feat/renewal-korean-search`. 실기기 빌드와 설치는 하지 않는다.

## 공식 계약

[공공데이터포털 15127578](https://www.data.go.kr/data/15127578/openapi.do)의 현재 페이지와 인라인 Swagger를 읽었다. 공식 페이지는 무료, 이용허락범위 제한 없음, 개발단계 자동승인·운영단계 심의승인, 개발계정 트래픽 10,000으로 안내한다. 운영 사용 전 승인·트래픽 조건을 별도로 확인해야 한다.

[공식 명세 발췌](official-contract-excerpt.json)에 확인한 주소·파라미터·필드를 기록했다. HTTPS `/1471000/FoodNtrCpntDbInfo03/getFoodNtrCpntDbInq03`, `serviceKey`, `type=json`, `pageNo`, `numOfRows`, `FOOD_NM_KR`를 사용한다. 종료된 I2790의 인증키나 필드로 대체하지 않는다.

| 응답 필드 | 사용 |
| --- | --- |
| FOOD_CD | 공급자 범위의 안정 식품 ID |
| FOOD_NM_KR | 표시 및 저장 이름 |
| AMT_NUM3 | g 단위 단백질 원문, 손실 없는 centigram 반올림 |
| SERVING_SIZE | 영양성분함량기준량. 명시적인 양의 g 또는 mL만 자동 기록 허용 |

총내용량·1회섭취 참고량을 영양성분함량기준량 대신 사용하지 않는다. 기준량이 없거나 단위를 해석할 수 없으면 이름만 직접 입력으로 가져올 수 있다. 단백질 0·음수·잘못된 값·범위 초과도 선택 불가다.

## 구현

- 별도 KoreanFoodSearchProvider에서 URLSession 요청·취소·20초 timeout·HTTP/API 오류를 처리한다. 원시 URL·오류 본문·인증키는 로그나 사용자 메시지에 노출하지 않는다.
- 한글·공백·슬래시·따옴표·&·%·+를 URLQueryItem으로 인코딩한다. 인증키는 디코딩 키를 받고 +를 명시적으로 인코딩한다.
- 페이지당 20개를 요청하고 응답 totalCount/pageNo/numOfRows와 행 수를 검증한다. 잘린 응답·중복 ID·식품 ID 누락은 조용히 기록하지 않고 응답 오류로 처리한다.
- 다음 페이지의 동일 ID 값이 변경되면 이전 선택을 해제하고 최신 행을 보여준다. 기록 추가·언어 저장을 시작하면 진행 중 페이지 요청을 취소하고 늦은 callback을 무효화해 저장 중 선택을 보존한다.
- 최근 검색·미확정 저장·고정 날짜·원자적 기록 저장은 기존 경로를 사용한다. 데이터 schema와 기존 기록은 바꾸지 않는다.

## 로컬 인증 설정

사용자가 제공한 인증키를 Git에서 제외된 로컬 `Secrets.xcconfig`에 설정했고, 2026-10-14 인증된 실 API 호출에 성공했다. 구 API_KEY와 별개로 MFDS_API_KEY를 추가했다. 키가 없거나 빈 값, 미치환 빌드 변수이면 네트워크 요청 없이 사용 불가 안내를 표시한다.

1. 위 공식 서비스에 개인 계정으로 활용신청하고 승인된 **디코딩 인증키**를 준비한다. 채팅·PR·로그에 키를 붙이지 않는다.
2. gitignore 대상인 `ProteinTracker/ProteinTracker/Secrets.xcconfig`에 `MFDS_API_KEY = <디코딩 인증키>`를 로컬로 설정한다. 실제 파일에는 꺾쇠 예시 문자열을 넣지 않는다.
3. 빌드한 앱에서 한국어를 선택하고 대표 식품 정상 검색, 0건, 다음 페이지와 실제 기준량 표기를 확인한다. 계정에서 발급한 키가 이 서비스에 승인돼 있는지 확인한다.
4. 실제 응답은 키·URL을 제거하고 필요한 식품 필드만 fixture로 보관해 합성 fixture와 구분한다. 공개 클라이언트 앱에 내장되는 키는 추출 가능하므로 운영 승인·쿼터와 함께 배포 구성을 검토한다.

## 검증 범위

추가 테스트는 공식 명세에 맞춘 **합성 응답 및 URLProtocol 대역**이다. 실제 공급자 정상 응답을 관찰했다는 의미가 아니다. 인증키 준비 뒤 JSON envelope·items 표현·페이지 크기·코드·SERVING_SIZE 표본을 대조해야 한국어 검색의 실연결 검증을 완료할 수 있다.

자동 테스트: 검색어·키 인코딩, 단위·반올림·잘못된 값, 페이지·0건·단일 item wrapper, 서버 오류 비밀값 차단, 키 누락, HTTP·timeout·취소·오프라인, 늦은 페이지 응답과 저장 선택 보존. iPhone SE / iOS 26.5 시뮬레이터 앱 테스트 **123개 통과, 0 실패**(신규 공급자 테스트 8개·페이지 저장 경합 테스트 1개 포함). Debug 빌드 성공. 로그 `/private/tmp/hp-korean-tests.log`. 이후 Release 시뮬레이터 빌드와 실 API UI 하네스 검증도 완료했다(아래 참조). 실기기는 사용하지 않았다.


## 인증된 실 API 검증 (2026-10-14)

로컬 키를 사용한 HTTPS 요청 4건에서 모두 `resultCode=00`을 확인했다. 이미지 인식에서 발생한 비라틴 유사 문자를 보정한 뒤 인증에 성공했다. 인증키와 요청 URL은 증거 파일에 포함하지 않는다.

| 검색 | 페이지 | totalCount | 반환 행 |
| --- | --- | --- | --- |
| 닭가슴살 | 1 | 4160 | 20 |
| 닭가슴살 | 2 | 4160 | 20 |
| 계란 | 1 | 1436 | 20 |
| 존재하지않는음식zz987654 | 1 | 0 | 0 |

샘플 `샌드위치_닭가슴살`은 `AMT_NUM3=12.18`, `SERVING_SIZE=100g`을 반환했다. 결과 수와 식품 값은 공급자 갱신에 따라 달라질 수 있다.

`live-*.json`은 실 응답에서 결과 코드·페이지 정보·식품 ID/이름/단백질/기준량만 추출한 파일이다. 원본 전체 응답은 아니며, 이 호출은 Python을 통한 API 검증이다. 앱의 URLSession 및 Swift 디코더를 통과한 실연결 검증이나 시뮬레이터 검색→선택→기록 저장 UI 검증을 대체하지 않는다. 앱 경로 검증은 아래 UI 결과에서 별도로 확인했다.


## 실제 앱 UI 검증 (2026-10-14)

**iPhone SE / iOS 26.5, 한국어 UI, Release 앱 빌드에서 XCUITest 3개 모두 통과(0 실패).** 실제 MFDS API와 앱의 URLSession·Swift 디코더·저장 경로를 사용했다. 합성 데이터·실패 주입 인자를 사용하지 않았고 기존 시뮬레이터 데이터를 초기화하지 않았다. 실제 검색 식품 1개를 시뮬레이터의 오늘 기록에 추가했다.

1. 닭가슴살 검색 → `샌드위치_닭가슴살` 선택 → 1개 추가 → 홈의 단백질 12.18g / 100g 기준 확인 → 앱 종료·재실행 → 기록 유지·수정 화면의 기준량 확인.
2. 첫 페이지 20개를 지나 `더 보기` → 두 번째 페이지의 `DELISH 크리스피 닭가슴살 핫도그` 표시 확인.
3. 존재하지 않는 검색어 → 실제 API 0건 → 빈 결과 안내 및 선택 추가 버튼 없음 확인.

저장 파일도 별도로 읽어 `source=search`, `protein=1218`(centigram), `quantity={value:100, unit:gram}`, `day=2026-10-14`를 확인했다. 키가 포함된 앱 설정·전체 저장 파일은 증거에 복사하지 않았다.

### 화면 캡처

- [검색 결과](screenshots/01-live-search-results.png)
- [선택 및 추가 버튼](screenshots/02-live-search-selected.png)
- [저장된 기록](screenshots/03-saved-record.png)
- [재실행 후 수정 화면](screenshots/04-persisted-record-editor.png)
- [두 번째 페이지](screenshots/05-live-second-page.png)
- [검색 결과 없음](screenshots/06-live-empty-results.png)

### 재현 자료와 한계

[UI 하네스](ui-harness/Smoke.swift)는 설치된 앱을 실행한다. 실제 인증키를 반영한 앱을 해당 시뮬레이터에 먼저 설치해야 한다. 키는 하네스에 포함하지 않는다. 테스트의 식품 ID·함량 기대값은 검증 당일 표본이므로 공급자 데이터가 변경되면 기대값을 재확인해야 한다. 반복 실행은 시뮬레이터에 검색 기록 1개를 추가한다.

- 빌드 로그: `/private/tmp/hp-korean-ui-build.log` (`BUILD SUCCEEDED`)
- UI 로그: `/private/tmp/hp-korean-ui-test-first.log`
- XCTest 결과: `/private/tmp/hp-korean-ui-results-first.xcresult`
- 실행: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project docs/evidence/2026-10-14-korean-search/ui-harness/Smoke.xcodeproj -scheme Smoke -destination 'platform=iOS Simulator,id=AF20D47C-C440-470E-91D6-6380CEA5F9CB' -derivedDataPath /private/tmp/hp-korean-ui-build -parallel-testing-enabled NO test CODE_SIGNING_ALLOWED=NO`

Orca emulator 도구는 시스템의 이전 Xcode 경로에서 `SimulatorKit.framework`를 찾지 못해 연결에 실패했다. 시스템 Xcode 선택은 변경하지 않고, 설치된 `/Applications/Xcode.app`을 지정한 기존 XCUITest 방식으로 검증했다. 실기기·다른 화면 크기·운영 계정 쿼터·App Store 배포는 이번 검증에 포함되지 않는다.
