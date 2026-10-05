# 일반 iPhone UI 보정·검증 (2026-10-05)

[인계 계획](../../iphone-ui-correction-plan.md)에 따라 Phase 1 홈 구현을 일반 iPhone 세로 화면에서 실행·보정·검증했다. 브랜치 `feat/renewal-home-phase1`, HEAD `d6ad3dd`. 기존 미커밋 Phase 1 변경과 untracked 파일은 보존했고, Duo 자료([2026-09-30 기록](../2026-09-30-ui-phase1/README.md))는 과거 기록으로 유지한다. Duo 동시 대응은 이번 범위가 아니다.

## 실행 환경

| 항목 | 값 |
| --- | --- |
| Xcode | `/Applications/Xcode.app` Xcode 26.5 (17F42), 명령마다 `DEVELOPER_DIR` 지정. 전역 `xcode-select`(Downloads Xcode 27.1)는 변경하지 않음 |
| 시뮬레이터 런타임 | iOS 26.5 (23F77). `xcodebuild -downloadPlatform iOS`로 10.6 GB 다운로드 후 설치. 기존 iOS 27.1 런타임은 iPhone Duo 전용이며 SE/17 생성 시 `Incompatible device` |
| 작은 iPhone | `HelloProtein iPhone SE` = iPhone SE (3rd generation), UDID `AF20D47C-C440-470E-91D6-6380CEA5F9CB`, 375×667 pt @2x (750×1334 px) |
| 일반 iPhone | `HelloProtein iPhone 17` = iPhone 17, UDID `8C3433BA-B9F6-4283-A7EE-DCCCF74A4982`, 402×874 pt @3x (1206×2622 px) |
| 데이터 | 두 기기 모두 신규 생성 후 `-HelloProteinRenewalFlow YES -HelloProteinSeedLegacyFixture YES`로 1회 시드. 사용자 실데이터·Duo 기기는 건드리지 않음 |
| UI 조작 | Orca `emulator attach`는 `runtime_unavailable`("The Orca runtime closed the connection before responding")로 실패. 설치된 앱을 XCTest UI 하네스가 직접 조작([ui-harness](ui-harness/)) |

fixture: 2026-09-23 음식 우유 10 g·계란 2개 35 g(상세 45), 원본 55 → 보정 +10. 09-20 합계 전용 70 g, 09-21 0 g, 09-22 15 g. 목표 120 g은 이관일(10-05)부터 적용되므로 9월 날짜는 "목표 이력 없음". 하네스는 날짜를 실행일 기준으로 계산해 09-23/09-20에 도달한다(이전 하네스의 고정 주 이동 횟수·132 g 기대값은 사용하지 않음).

## 수정 전 확인 결과 (보정 전 소스, 같은 데이터)

| 기기 | 결과 | 근거 |
| --- | --- | --- |
| iPhone SE | 날짜 줄 좌우 잘림. 첫 버튼 frame x=15.5 pt(페이지 인셋 20 pt보다 4.5 pt 왼쪽), 마지막 버튼도 오른쪽으로 4.5 pt 넘침. 7×44 + 6×6 = 344 pt > 335 pt | `before/iphone-se/home-en.png`, 하네스 실패 `before-se-192516` ("15.5 is less than 19.5 - clipped left of content edge 20.0") |
| iPhone 17 | 7일 모두 20~364 pt 안. 문제 없음 | `before/iphone-17/home-en.png`, `before/iphone-17/day-strip-frames-en.txt`, `before-17-193537` 통과 |

SE에서 시트·달력·키보드·펼침·하단 버튼은 수정 전에도 정상이었다(`before/iphone-se/home-en-seeded.png`는 시드 직후 `simctl io screenshot`). 그 외 컴포넌트는 변경하지 않았다.

## 보정 내용

`ProteinTracker/ProteinTracker/Renewal/Components/DayStrip.swift`만 변경([diff](daystrip-correction.diff)). untracked 파일이라 git diff가 없어 패치를 따로 보관한다.

- 기본/큰 글자(비접근성 카테고리): 가로 스크롤 대신 `HStack(spacing: 4)` + 균등 폭(`maxWidth: .infinity`). 335 pt에서 7×44 + 6×4 = 332 pt로 모두 표시. 터치 영역 `minWidth: 44, minHeight: 64` 유지.
- 접근성 카테고리(AX1 이상): 기존 `ScrollView` + 선택 날짜 중앙 스크롤 유지. 글자 축소·터치 영역 축소 없음.
- 음수 padding, 상태바 숨김, 고정 폭, UIKit 전역 appearance 변경 없음. `RecordHomeViewModel`, 코어, 이관, strings 변경 없음.

## 수정 후 결과

하네스 7개 메서드를 두 기기에서 실행. 영어 5개 + 한국어/큰 글씨 2개 + 다크 1개. 모두 실제 설치 앱을 탭·입력·재실행했다.

| 시나리오 | SE | 17 | 확인 내용 |
| --- | --- | --- | --- |
| `test1HomeEnglish` 홈·달력·과거·펼침·총량 시트·합계 전용·오늘 복귀 | 통과 | 통과 | 7일 버튼이 인셋 안·폭 ≥ 44 pt(`day-strip-frames-en.txt`: SE 44~44.5 pt, 17 48~48.3 pt). 09-23 55 g·보정 +10·원본 55·상세 45, 총량 시트 초기값 55·키보드·저장/취소 hittable, 09-20 70 g·목표 이력 없음, 오늘 버튼으로 복귀 |
| `test2EntryLifecycle` 추가→목표 달성→수정→재실행→삭제 | 통과 | 통과 | 긴 이름 + 120.5 g 추가 → "Goal reached", "0.5 g above your goal". 마지막 행이 추가 버튼 위에 완전히 노출된 뒤 탭(`last-row-above-add.png`), "Edit entry" 확인 후 60 g 수정, 같은 이름 행 1개(중복 없음), 종료·재실행 후 60 유지, 삭제 후 사라짐 |
| `test3KoreanHome` 한국어 홈·과거 | 통과 | 통과 | 7일 버튼 동일 조건(`day-strip-frames-ko.txt`), 09-23 "이 날짜에는 목표 이력이 없어요", 보정 펼침 |
| `test4UnconfirmedCloseAndReconfirm` 미확정→닫기→홈 재확인 | 통과 | 통과 | `-HelloProteinFailAfterReplaceOnce` 주입. 알림 → 필드·저장 잠금 → 취소 → 홈 추가 잠금·배너 → 저장 결과 확인 → 행 1개·잠금 해제 |
| `test5LargeTextKorean` AX3 (`UICTContentSizeCategoryAccessibilityXL`) | 통과 | 통과 | 선택 날짜·추가 버튼 hittable, 7일째는 스크롤로 도달, 긴 음식명 세로 배치, 추가 시트 키보드 |
| `test6SystemDark` 시스템 다크 (`simctl ui appearance dark` 후 실행, 종료 후 light 복원) | 통과 | 통과 | 홈·달력·추가 시트가 라이트로 읽힘 |

결과 번들(`/private/tmp/hp-iphone-ui/results/`): `after-se-193656`(5/5), `after-17-194007`(5/5), `after-se-194221`(test5 AX3 재실행 1/1; 최초 실행은 AX2 인자였음), `after-se-194257`·`after-17-194321`(다크 1/1). iPhone 17 첫 실행 `after-17-193921`은 테스트 러너가 0개 실행하고 종료해 재실행했다. 모두 exit 0, skipped 0.

AX3에서 SE 날짜 줄은 설계대로 가로 스크롤이며 첫/마지막 버튼이 인셋 밖으로 약 4.5 pt 걸친다(`iphone-se/large-text.png`). iPhone 17 AX3는 7일이 362 pt 안에 들어간다.

데이터 검산([SE](data-check-iphone-se.json), [17](data-check-iphone-17.json), 이관 시각만 다름): 09-23 원본 5500·상세 4500·보정 1000·합계 5500·행 2, 09-20 원본 7000·합계 7000, 오늘 행은 미확정 시나리오의 31.5 g 1개뿐, 수명 시나리오 행 없음, record ID 고유, 목표 12000(10-05부터), 즐겨찾기 2, 검색 이력 2.

## 자동 검사

| 검사 | 결과 | 증거 |
| --- | --- | --- |
| HelloProteinCore | 45개 통과, exit 0 | `/private/tmp/hp-iphone-core-tests.log` |
| MigrationCore | 64개 통과, exit 0 | `/private/tmp/hp-iphone-migration-tests.log` |
| 앱 빌드(보정 전·후, SE 대상) | exit 0 | `/private/tmp/hp-iphone-baseline-build.log`, `/private/tmp/hp-iphone-after-build.log`(기존 SearchViewController 경고 잔존) |
| 앱 테스트 타깃(iPhone 17, iOS 26.5) | 32개 통과, 실패 0, 스킵 0, exit 0 | `/private/tmp/hp-iphone-tests-193713.xcresult` |
| `git diff --check`, `plutil -lint` (en/ko strings, pbxproj) | 통과 | — |

`IPHONEOS_DEPLOYMENT_TARGET=15.0` override는 환경용이며 프로젝트 최소 OS는 바꾸지 않았다.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun simctl create "HelloProtein iPhone SE" "iPhone SE (3rd generation)" com.apple.CoreSimulator.SimRuntime.iOS-26-5
xcodebuild -project ProteinTracker/ProteinTracker.xcodeproj -scheme ProteinTracker -configuration Debug \
  -destination 'platform=iOS Simulator,id=<UDID>' -derivedDataPath /private/tmp/hp-iphone-build \
  -onlyUsePackageVersionsFromResolvedFile -disableAutomaticPackageResolution \
  build CODE_SIGNING_ALLOWED=NO IPHONEOS_DEPLOYMENT_TARGET=15.0 -quiet
xcrun simctl install <UDID> /private/tmp/hp-iphone-build/Build/Products/Debug-iphonesimulator/ProteinTracker.app
xcrun simctl launch <UDID> com.devsom.ProteinTracker -HelloProteinRenewalFlow YES -HelloProteinSeedLegacyFixture YES
# 하네스: ui-harness/ 를 /private/tmp/hp-iphone-ui/ 에 두고 udid-se.txt / udid-17.txt 작성 후
./run-test.sh se after test1HomeEnglish test2EntryLifecycle test3KoreanHome test4UnconfirmedCloseAndReconfirm test5LargeTextKorean
xcrun simctl ui <UDID> appearance dark && ./run-test.sh se after test6SystemDark && xcrun simctl ui <UDID> appearance light
```

## 캡처 (기기별 폴더, 절대 경로 `/Users/somin/orca/HelloProtein/docs/evidence/2026-10-05-iphone-ui/`)

`iphone-se/`, `iphone-17/` 각각: `home-ko.png`, `home-en.png`, `date-picker.png`, `past-records.png`, `past-records-ko.png`, `legacy-expanded.png`, `aggregate-only.png`, `add-keyboard.png`, `edit-keyboard.png`, `total-editor.png`, `goal-reached.png`, `last-row-above-add.png`, `after-delete.png`, `pending-sheet.png`, `pending-home.png`, `pending-confirmed.png`, `large-text.png`, `large-text-scrolled.png`, `large-text-add.png`, `dark-home.png`, `dark-calendar.png`, `dark-sheet.png`. 수정 전은 `before/iphone-se/`, `before/iphone-17/`. 모두 XCTest/`simctl` 원본 PNG이며 가공하지 않았다. 시뮬레이터 상태바의 "이동통신사"는 시뮬레이터 표시다.

## 미검증·주의

- 실제 VoiceOver 초점·발화. XCTest 접근성 쿼리는 VoiceOver 검증이 아니다.
- iOS 15 런타임, 실기기, 320 pt 폭 기기(iOS 26.5 미지원), iPad, 가로 모드.
- 미반영(notApplied)·재확인 읽기 실패의 UI 주입.
- 한국어 AX3는 홈·추가 시트만, 영어 AX3·한국어 다크·한국어 키보드 입력 조합은 캡처하지 않았다.
- Duo 기기에서의 재검증은 하지 않았다(연기).
- 새 흐름 기본 활성화·출시·머지는 하지 않았다. 필수 미검증이 남아 있으므로 "전체 QA 완료"가 아니다.
