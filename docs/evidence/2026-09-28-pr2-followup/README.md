# 2026-09-28 PR #2 후속(R1·R2) 시뮬레이터 검증 증거

- 기기: iPhone 15 Pro, iOS 17.0 시뮬레이터 (UDID `B67306B6-85DB-44CC-BC0D-2F5673D79D7D`), Xcode 27.1.
- 앱: `xcodebuild … -configuration Debug … build` 산출물 (`/private/tmp/helloprotein-next/build/Build/Products/Debug-iphonesimulator/ProteinTracker.app`, 로그 `/private/tmp/helloprotein-next/app-build-7-debug.log`, exit 0). Release 빌드도 성공(`app-build-7-release.log`, exit 0)했고 `strings -a`로 확인한 Release 바이너리에는 `HelloProteinFailAfterReplaceOnce`·`HelloProteinInterruptAt`·`HelloProteinSeedLegacyFixture`·"simulated final read failure" 문자열이 없다(Debug `ProteinTracker.debug.dylib`에는 있다).
- 모든 데이터는 `-HelloProteinSeedLegacyFixture YES`가 심는 합성 픽스처다. 실제 사용자 데이터는 사용하지 않았고, 파일 손상·삭제는 시뮬레이터 컨테이너 안의 픽스처 파일에만 했으며 원본 바이트를 미리 복사해 두고 검사 후 되돌렸다.
- 입력은 `orca computer`(Simulator 창 접근성 AXPress/AXSetValue)와 `osascript System Events click`(시트 툴바 Save)으로 넣었고, 화면은 `xcrun simctl io <udid> screenshot`으로 저장했다.
- 새 흐름은 기본 비활성 그대로다. 모든 실행에 `-HelloProteinRenewalFlow YES`를 넘겼다.
- S1은 리뷰 반영 전 빌드(`app-build-6-debug.log`, 21:26)로 찍었고 그 경로의 코드는 리뷰에서 바뀌지 않았다. S2·S3은 별도 코드 리뷰 패스(아래)를 반영한 빌드(`app-build-7-debug.log`, 21:47–21:48)로 다시 찍었다.

## S1. 정상 이관 + 과거 날짜 추가 회귀
실행: 새 설치 → `-HelloProteinSeedLegacyFixture YES -HelloProteinRenewalFlow YES`

| 파일 | 확인 내용 |
| --- | --- |
| S1-old-date-add-regression.png | 이관(fingerprint `5af9edd01638`) 뒤 09-20으로 이동해 salmon 18g 추가 → 88g(보정 70 + 18), `salmon, 18g` 행. `app-state.json`에 `lastOperationID`가 기록되고 09-20 records `('salmon', 1800)`, 보정 7000 |

## S2. 손상된 완료 마커 (R1)
| 파일 | 확인 내용 |
| --- | --- |
| S2a-corrupt-marker-store-missing-recovery.png | 앱 종료 후 `app-state.json`을 치우고 `migration/migration-completed.json`을 잘린 JSON(`{"evidenceFormatVersion":1,"migration":{"origin":"legacyImport"`)으로 덮어쓴 뒤 실행. "Couldn't move your data" 복구 화면, 종류 `evidenceCorrupt: completion: dataCorrupted(…Unexpected end of file…)`(상세는 DEBUG 표시), 옆의 정상 백업이 있으므로 "A pre-migration backup copy is stored inside the app" 문구 표시(리뷰 M4 반영). `app-state.json`은 생성되지 않았고 원본 `Documents/default.realm`, `legacy-backup/default.realm`, `legacy-capture.json`, 손상 마커의 SHA-256이 실행 전후 동일(`cmp` 일치). 재이관·새 설치 없음 |
| S2b-corrupt-marker-store-present-normal.png | 정상 `app-state.json`을 되돌리고(마커는 손상 상태 유지) 재실행: 기록 화면으로 정상 진입(09-28 0g / Goal 120g), 손상 마커 SHA-256 그대로(`ebabe3261b4d58f8`, 덮어쓰지 않음). 검사 뒤 원래 마커 바이트로 복구 |

## S3. rename 이후 읽기 실패 → 재확인 → 재실행 (R2)
실행: `-HelloProteinRenewalFlow YES -HelloProteinFailAfterReplaceOnce YES`

| 파일 | 확인 내용 |
| --- | --- |
| S3a-indeterminate-save-alert.png | 오늘(09-28) 추가 시트에 tuna / 15 입력 후 Save. 로그 `HelloProtein: simulated final read failure after replace` 발생, 경고 "Save result unconfirmed — The file was replaced, but it couldn't be read back. Your input is kept. Nothing else will be saved until the saved result has been checked." |
| S3b-pending-section-in-sheet.png | 경고를 닫아도 시트와 입력(tuna, 15)이 유지되고 "This save couldn't be confirmed…" 안내와 `Check saved result` 버튼만 활성. 이 시점 디스크의 `app-state.json`에는 이미 `lastOperationID 8332095D-…`와 09-28 `('tuna', 1500)`이 있으나 화면은 마지막 확정 상태(0g)를 유지 |
| S3c-after-reconfirm-one-row.png | `Check saved result` 누름: 저장소를 다시 읽어 pending 작업 ID 일치 → 시트 닫힘, 홈 15g / `tuna, 15g` 한 행. 자동 재저장 없음 |
| S3d-relaunch-one-row.png | 주입 인자 없이 재실행: 15g / `tuna, 15g` 한 행, `lastOperationID` 동일, 중복 행 없음 |
| S3e-inputs-locked-while-unconfirmed.png | (2차 리뷰 반영 빌드 `app-build-8-debug.log`) egg / 10 저장이 미확정된 뒤 접근성 트리에서 두 입력란이 `text field (disabled)`로 바뀌고, 단백질을 20으로 바꾸려는 AXSetValue가 `value_not_settable`로 거부됨. 재확인 후 `egg, 10g` 한 행, 디스크도 동일 |

## 자동 테스트 (같은 변경 기준)
| 대상 | 결과 | 로그 |
| --- | --- | --- |
| HelloProteinCore `swift test` | 45개 통과, exit 0 | `/private/tmp/helloprotein-next/core-tests-5.log` |
| MigrationCore `swift test` | 64개 통과, exit 0 | `/private/tmp/helloprotein-next/migration-tests-6.log` |
| ProteinTrackerTests (iOS 시뮬레이터) | 30개 통과, TEST SUCCEEDED, exit 0 | `/private/tmp/helloprotein-next/app-test-10.log`, `test-10.xcresult` |
| 앱 Debug / Release 빌드 (2차 리뷰 반영) | 둘 다 성공, exit 0, Release에 주입 문자열 없음 | `app-build-8-debug.log`, `app-build-8-release.log` |

리뷰 반영 전 수치는 43 / 61 / 28(`core-tests-4.log`, `migration-tests-4.log`, `app-test-6.log`)이었다.

## 코드 리뷰 패스에서 고친 것
별도 리뷰(opus code-reviewer, 읽기 전용)가 지적한 항목과 반영 내용.
- C1(치명): 미확정 차단이 저장소 인스턴스에만 있고 `inspect()`가 풀지 않아, 이관 커밋이 미확정으로 끝난 뒤 재시도 → 기록 화면으로 들어가면 모든 저장이 "저장 실패"로만 나오고 재확인 버튼이 없었다. 차단 상태를 파일 경로 단위 공유 상태로 옮기고, `inspect()`가 `.ready`를 찾으면 `load()`처럼 차단을 푼다. 차단 중 거부는 `notCommitted`가 아니라 `indeterminate(previousCommitUnconfirmed)`로 보고하고, 화면 모델은 시작 시 저장소의 미확정 상태를 읽어 배너·재확인을 바로 보여준다(`testScreenStartedOnAnAlreadyBlockedStore…`, `testBlockedStoreRefusalNamesTheEarlierOperation…`, `testInspectFindingAReadyFileLiftsTheWriteBlockLikeLoad`).
- M2: 홈 배너의 재확인이 `notApplied`를 삼켜 입력이 조용히 사라졌다 → 배너에서도 "Not saved" 경고 표시.
- M3: 같은 파일의 다른 저장소 인스턴스가 차단을 우회했다 → 경로 단위 공유 상태(위와 같은 수정, 저장소 테스트에 교차 인스턴스 검사 추가).
- M4: 증거 파일 문제 시 `backupAvailable`을 항상 false로 냈다 → 손상된 파일이 백업 자체일 때만 false, 완료 마커가 손상된 경우엔 실제 검사 결과(`testCorruptCompletionNextToAValidBackupStillReportsTheBackup`).
- m5: `indeterminate(interrupted(afterReplace))`를 `interrupted`로 분류 → `indeterminate` 판정을 먼저 한다(중단 지점 순회 테스트의 기대값 수정).
- m6: `commit()`이 검증 오류를 `writeFailed`로 감쌌다 → 검증은 그대로 다시 던진다(`testCommitRethrowsValidationErrorsUnchanged`).
- m7: `hasUnconfirmedCommit` 읽기가 커밋 락을 잡았다 → 플래그 전용 짧은 락.
- m8: 미확정 중에도 기록 행·총량 편집을 눌러 다른 작업 ID로 거부되는 시트가 열렸다 → 미확정 중 비활성화.
- m9: 백업의 `captureFormatVersion` 상위 버전을 본문 디코드 뒤에만 잡았다 → 버전 프로브에서 함께 확인(`testNewerCaptureFormatInsideBackupIsUnsupported…`).
- nit: `-HelloProteinFailAfterReplaceOnce`가 `YES`만 받았다 → 다른 플래그와 같은 truthy 판정.
- 남긴 것: 유효한 백업을 다른 fingerprint의 새 캡처로 덮어쓰는 기존 동작(이번 범위 밖), `latestBackup()/completionEvidence()` 던지는 API의 잔존(테스트만 사용), `fileExists` 직후 삭제된 파일을 `unreadable`로 보고.

## 2차 리뷰(PR #3)에서 고친 것
- P2 손상된 백업을 정상으로 판정: 백업은 JSON 디코드만으로 `.valid`가 됐다. 본문(음식 값)이 바뀌었는데 fingerprint가 구 원본과 같은 백업이 있으면 구 원본 이관이 그 백업을 "같은 원본의 백업"으로 두고 완료했고, 나중에 백업 복구 시에만 지문 불일치로 실패했다. 이제 코디네이터가 백업 본문의 SHA-256을 다시 계산해 fingerprint와 다르면 `corrupt`로 판정한다. 구 원본이 있어도 멈추고(`evidenceCorrupt`, 캡처 전), 파일은 보존하며, `backupAvailable`은 false다(`testBackupWithEditedContentsUnderTheOldFingerprintStopsALegacyMigration`, `testTamperedBackupIsNotUsed` 기대값을 `legacyCaptureFailed`에서 `evidenceCorrupt`로 수정).
- P2 미확정 중 변경한 입력이 사라짐: 미확정 상태에서도 입력란을 고칠 수 있었고, 재확인이 앞선 저장을 확인하면 시트가 닫히며 새 입력이 버려졌다. 이제 저장 중과 미확정 중에는 이름·단백질·총량 입력란을 잠근다. `notApplied`로 돌아오면 다시 풀린다(S3e).

## 미검증
- 실제 사용자 파일, 실기기, iOS 13/14, 전원 차단 중 rename, 디스크 가득 참.
- `notApplied`(재확인했더니 파일에 작업이 없음) 경로와 삭제/수정의 미확정 경로는 단위 테스트(`RecordHomeViewModelTests`)로만 검증했고 시뮬레이터 화면으로는 찍지 않았다.
- `evidenceUnreadable`(권한 없음)·`evidenceUnsupported`(상위 버전) 복구 화면은 코디네이터 테스트로만 검증했다.
- 실행 중 다른 앱/프로세스가 파일을 바꾸는 경우.
