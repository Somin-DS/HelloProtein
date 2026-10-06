import XCTest
import UIKit
import MigrationCore

/// Every sentence on the recovery screen follows a flag of the recovery state.
final class RecoveryViewControllerTests: XCTestCase {
    private func state(kind: RecoveryKind = .storeCorrupt, preserved: Bool = true, backup: Bool, canRetry: Bool) -> RecoveryState {
        RecoveryState(kind: kind, detail: "legacy:stat:1 value 7000", originalPreserved: preserved,
                      backupAvailable: backup, canRetry: canRetry)
    }

    private func load(_ controller: RecoveryViewController) -> [String: UIView] {
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 375, height: 667)
        controller.view.layoutIfNeeded()
        var found: [String: UIView] = [:]
        func walk(_ view: UIView) {
            if let id = view.accessibilityIdentifier { found[id] = view }
            view.subviews.forEach(walk)
        }
        walk(controller.view)
        return found
    }

    func testTitleCoversStoreProblemsNotOnlyMigration() {
        let content = RecoveryViewController.Content(presentation: .recovery(state(kind: .storeUnreadable, backup: false, canRetry: true)),
                                                     hasRetryAction: true, debugDetail: false)
        XCTAssertEqual(content.title, RenewalStrings.text("recovery_title"))
        XCTAssertTrue(content.body.hasPrefix(RenewalStrings.text("recovery_kind_storeUnreadable")))
    }

    func testPreservedAndBackupLinesFollowTheirFlags() {
        let preserved = RenewalStrings.text("recovery_preserved")
        let backup = RenewalStrings.text("recovery_backup_available")
        let both = RecoveryViewController.Content(presentation: .recovery(state(preserved: true, backup: true, canRetry: false)),
                                                  hasRetryAction: true, debugDetail: false)
        XCTAssertTrue(both.body.contains(preserved))
        XCTAssertTrue(both.body.contains(backup))
        let neither = RecoveryViewController.Content(presentation: .recovery(state(preserved: false, backup: false, canRetry: false)),
                                                     hasRetryAction: true, debugDetail: false)
        XCTAssertFalse(neither.body.contains(preserved), "the original is not called untouched unless the state says so")
        XCTAssertFalse(neither.body.contains(backup))
        let onlyBackup = RecoveryViewController.Content(presentation: .recovery(state(preserved: false, backup: true, canRetry: false)),
                                                        hasRetryAction: true, debugDetail: false)
        XCTAssertFalse(onlyBackup.body.contains(preserved))
        XCTAssertTrue(onlyBackup.body.contains(backup))
    }

    func testRetryHintAndButtonAppearOnlyWhenRetryIsPossibleAndWired() {
        let hint = RenewalStrings.text("recovery_retry_hint")
        let canRetryAndWired = RecoveryViewController.Content(presentation: .recovery(state(backup: false, canRetry: true)),
                                                              hasRetryAction: true, debugDetail: false)
        XCTAssertEqual(canRetryAndWired.retryHint, hint)
        let canRetryNoAction = RecoveryViewController.Content(presentation: .recovery(state(backup: false, canRetry: true)),
                                                              hasRetryAction: false, debugDetail: false)
        XCTAssertNil(canRetryNoAction.retryHint, "no hint for a button that would do nothing")
        let cannotRetry = RecoveryViewController.Content(presentation: .recovery(state(backup: true, canRetry: false)),
                                                         hasRetryAction: true, debugDetail: false)
        XCTAssertNil(cannotRetry.retryHint)
        XCTAssertFalse(cannotRetry.body.lowercased().contains("cannot be recovered"))
        XCTAssertFalse(cannotRetry.body.contains("복구할 수 없"))

        let withButton = RecoveryViewController(presentation: .recovery(state(backup: false, canRetry: true))) {}
        let views = load(withButton)
        XCTAssertNotNil(views["recovery.retry"])
        XCTAssertNotNil(views["recovery.retryHint"])
        XCTAssertGreaterThanOrEqual(views["recovery.retry"]?.bounds.height ?? 0, 44)

        let withoutAction = load(RecoveryViewController(presentation: .recovery(state(backup: false, canRetry: true)), retry: nil))
        XCTAssertNil(withoutAction["recovery.retry"])
        XCTAssertNil(withoutAction["recovery.retryHint"])
        let withoutRetry = load(RecoveryViewController(presentation: .recovery(state(backup: true, canRetry: false))) {})
        XCTAssertNil(withoutRetry["recovery.retry"])
        XCTAssertNil(withoutRetry["recovery.retryHint"])
    }

    func testRetryRunsOnceEvenWhenTappedRepeatedly() {
        var runs = 0
        let controller = RecoveryViewController(presentation: .recovery(state(backup: false, canRetry: true))) { runs += 1 }
        let button = try! XCTUnwrap(load(controller)["recovery.retry"] as? UIButton)
        XCTAssertTrue(controller.isRetryAvailable)
        // The button's only target/action is `retryTapped`; call it directly
        // because an unhosted test bundle has no UIApplication to dispatch it.
        XCTAssertEqual(button.actions(forTarget: controller, forControlEvent: .touchUpInside), ["retryTapped"])
        controller.retryTapped()
        controller.retryTapped()
        controller.retryTapped()
        XCTAssertEqual(runs, 1)
        XCTAssertFalse(controller.isRetryAvailable)
        XCTAssertFalse(button.isEnabled)
    }

    func testUnsupportedOSKeepsItsOwnCopyAndNoRetry() {
        let content = RecoveryViewController.Content(presentation: .unsupportedOS, hasRetryAction: true, debugDetail: true)
        XCTAssertEqual(content.body, RenewalStrings.text("recovery_unsupported_os"))
        XCTAssertNil(content.retryHint)
        XCTAssertEqual(content.detail, "")
        let views = load(RecoveryViewController(presentation: .unsupportedOS, retry: nil))
        XCTAssertNil(views["recovery.retry"])
    }

    func testReleaseDetailShowsOnlyTheKindCode() {
        let recovery = state(kind: .legacyInvalid, backup: true, canRetry: false)
        let release = RecoveryViewController.Content(presentation: .recovery(recovery), hasRetryAction: false, debugDetail: false)
        XCTAssertEqual(release.detail, "legacyInvalid")
        XCTAssertFalse(release.detail.contains("legacy:stat:1"))
        let debug = RecoveryViewController.Content(presentation: .recovery(recovery), hasRetryAction: false, debugDetail: true)
        XCTAssertTrue(debug.detail.contains("legacy:stat:1"))
    }

    func testLargeTextKeepsEverythingReadableWithoutTruncation() {
        let controller = RecoveryViewController(presentation: .recovery(state(backup: true, canRetry: true))) {}
        let views = load(controller)
        for id in ["recovery.title", "recovery.body", "recovery.retryHint"] {
            let label = try! XCTUnwrap(views[id] as? UILabel, id)
            XCTAssertEqual(label.numberOfLines, 0, "\(id) must wrap")
            XCTAssertTrue(label.adjustsFontForContentSizeCategory, "\(id) must follow Dynamic Type")
        }
    }
}
