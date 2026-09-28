# 2026-09-28 시뮬레이터 검증 증거

- 기기: iPhone 15 Pro, iOS 17.0 시뮬레이터 (UDID `B67306B6-85DB-44CC-BC0D-2F5673D79D7D`), Xcode 27.1.
- 앱: `xcodebuild … -configuration Debug … build` 산출물 (`/private/tmp/helloprotein-next/build/Build/Products/Debug-iphonesimulator/ProteinTracker.app`, 로그 `/private/tmp/helloprotein-next/app-build-4-debug.log`, exit=0).
- 모든 데이터는 `-HelloProteinSeedLegacyFixture YES`가 심는 합성 픽스처다. 실제 사용자 데이터는 사용하지 않았다.
- 입력은 `orca computer`(Simulator 창 접근성 AXPress/AXSetValue)와 `osascript System Events click`로 넣었고, 화면은 `xcrun simctl io <udid> screenshot`으로 저장했다.
- A 시리즈는 픽스처 `originDate` 상수가 2025년으로 잘못 잡혀 있던 빌드(20:02)로 찍었다. 이후 상수만 2026년으로 고쳐 재빌드했고, 화면에는 그 값이 표시되지 않는다. B1–B4/C/D/R 시리즈는 고친 빌드(20:25), B5–B7은 코드 리뷰 반영 빌드(20:49, `app-build-5-debug.log`)다.

## A. 정상 업그레이드
실행: `xcrun simctl launch <udid> com.devsom.ProteinTracker -HelloProteinSeedLegacyFixture YES -HelloProteinRenewalFlow YES`

| 파일 | 확인 내용 |
| --- | --- |
| A1-after-migration-today.png | 이관 직후 오늘(09-28) 화면, 목표 120g, 기록 없음 |
| A2-2026-09-23-migrated-details.png | 구버전 "오늘" 상세: 우유 10g, 계란 2개 35g, 보정 +10g, 합계 55g, 원본 총량 55g 표시 |
| A3-2026-09-20-legacy-total-only.png | 과거 합계만 있는 날: 70g, "상세 기록 없음" 안내 |
| A4-2026-09-20-after-add-entry.png | 09-20에 chicken breast 20g 추가 → 90g (70 보정 + 20) |
| A5-2026-09-20-edit-total-sheet.png | 일일 총량 편집 시트 (값 75 입력) |
| A6-2026-09-20-after-total-75.png | 총량 75g, 보정 +55g, 원본 총량 70g 별도 유지, "총량을 75g로 변경" 안내 |
| A7-relaunch-no-flag-2026-09-20-persisted.png | 실행 인자 없이 재실행: 새 저장소 증거로 새 흐름 강제, 09-20 값 75g 유지 |

저장소 확인(app-state.json): 09-20 `legacyAdjustmentCentigrams=5500`, `legacyAggregate.importedTotalCentigrams=7000`, `userEditedTotalCentigrams=7500`, 기록 chicken breast 2000. 09-23 기록 우유 1000/계란 2개 3500, 보정 1000. 즐겨찾기 2, 검색 이력 2, 목표 12000 effectiveFrom 2026-09-28, `legacyTargetRaw="120"`, searchLanguage korean.

## B. 중단 후 재실행
| 파일 | 확인 내용 |
| --- | --- |
| B1-interrupt-beforeReplace-after-kill.png | `-HelloProteinInterruptAt beforeReplace`로 SIGKILL 직후. 컨테이너: `.app-state.json.tmp-*`만 있고 `app-state.json`/완료 마커 없음, `migration/legacy-capture.json`과 `legacy-backup/default.realm`(원본과 SHA-256 동일) 존재 |
| B2-relaunch-after-beforeReplace-interrupt.png | `-HelloProteinRenewalFlow YES`로 재실행: `app-state.json`+`migration-completed.json` 생성(같은 fingerprint), 원본 realm SHA-256 변화 없음, 기록 화면 진입. (촬영 당시 빌드는 임시 파일을 즉시 지웠고, 리뷰 반영 후에는 1시간 이상 지난 임시 파일만 지운다) |
| B3-interrupt-afterReplace-after-kill.png | `afterReplace`에서 SIGKILL: `app-state.json`은 완전한 상태, 완료 마커 없음 |
| B4-relaunch-after-afterReplace-interrupt.png | 재실행: 재이관 없이 `ready` 경로, `app-state.json` 바이트 동일(cmp), 완료 마커만 추가 기록 |
| B5-interrupt-afterTemporaryWrite-after-kill.png | (리뷰 반영 빌드) `afterTemporaryWrite`에서 SIGKILL: 임시 파일만 있고 `app-state.json`/완료 마커 없음, 백업은 원본과 SHA-256 동일 |
| B6-relaunch-no-flag-after-precommit-interrupt-legacy-path.png | 실행 인자 없이 재실행: 커밋된 저장소가 없으므로 기존 UIKit 화면(0g / 120g)이 그대로 뜬다. 기존 앱은 자기 규칙대로 날짜 변경 처리를 수행해 09-23 상세를 StatProtein 합계 55로 접었다(원본 realm SHA 변경은 기존 앱의 쓰기이며 새 코드는 원본을 쓰지 않는다) |
| B7-relaunch-with-flag-after-afterTemporaryWrite.png | `-HelloProteinRenewalFlow YES`로 재실행: 최신 구버전 상태(09-23 합계 55, 상세 없음)를 다시 캡처해 이관 완료. 첫 시도의 백업(`legacy-backup/default.realm`, SHA 5e79…)은 덮어쓰지 않고 유지 |

주의: B6은 리뷰에서 바꾼 판정(캡처/백업 디렉터리만으로는 기존 경로를 막지 않음)의 결과다. 커밋 전에 중단된 뒤 플래그 없이 실행하면 기존 앱이 계속 동작하며, 기존 앱의 날짜 변경 규칙(오늘 상세 → 과거 합계)이 그대로 적용된다. 이는 기존 앱의 원래 동작이지 새 코드의 삭제가 아니다.

## C. 저장 실패
| 파일 | 확인 내용 |
| --- | --- |
| C1-save-failure-alert-sheet-stays.png | 저장 디렉터리를 `chmod 555` 한 뒤 저장: "Couldn't save … writeFailed(createFile)" 경고, 시트와 입력값(tofu, 12) 유지, `app-state.json` 변화 없음 |
| C2-after-alert-sheet-still-open.png | 경고 닫은 뒤에도 시트가 열려 있음 |
| C3-save-succeeds-after-restore.png | 권한 복구(`chmod 755`) 후 같은 시트에서 저장 성공: 오늘 12g, tofu 12g 기록 |

## D. 기본 경로 유지
| 파일 | 확인 내용 |
| --- | --- |
| D1-fresh-install-no-flag-legacy-path.png | 새 설치 + 실행 인자 없음: 기존 UIKit Init 화면(Protein Calculator) 그대로, `Application Support/HelloProtein` 미생성 |

## R. 복구 화면
| 파일 | 확인 내용 |
| --- | --- |
| R1-recovery-screen-corrupt-store.png | `app-state.json`을 잘린 JSON으로 덮어쓴 뒤 실행: "Couldn't move your data" 복구 화면, `Try again` 버튼만 있음(초기화 없음), 원본 realm·백업·capture 모두 그대로. 파일 복구 후 재실행 시 정상 진입 |
