import XCTest
import SwiftUI
import UIKit
import HelloProteinCore

/// The close/delete state table of the editing sheets, without SwiftUI.
final class EditorDismissPolicyTests: XCTestCase {
    typealias Policy = EditorDismissPolicy

    // MARK: Dirty detection: exact string comparison against the opening snapshot

    func testNewEntryIsCleanUntilSomethingIsTyped() {
        XCTAssertFalse(Policy.isDirty(initial: ["", ""], current: ["", ""]))
        XCTAssertTrue(Policy.isDirty(initial: ["", ""], current: ["t", ""]))
        XCTAssertTrue(Policy.isDirty(initial: ["", ""], current: ["", "1"]))
    }

    func testExistingEntryAndTotalCompareAgainstTheirFormattedInitialStrings() {
        XCTAssertFalse(Policy.isDirty(initial: ["닭가슴살", "23.5"], current: ["닭가슴살", "23.5"]))
        XCTAssertTrue(Policy.isDirty(initial: ["닭가슴살", "23.5"], current: ["닭가슴살", "23.50"]), "formatting change counts")
        XCTAssertTrue(Policy.isDirty(initial: ["닭가슴살", "23.5"], current: ["닭가슴살 ", "23.5"]), "whitespace counts")
        XCTAssertTrue(Policy.isDirty(initial: ["닭가슴살", "23.5"], current: ["닭가슴살", "abc"]), "invalid number still counts as typed")
        XCTAssertFalse(Policy.isDirty(initial: ["70"], current: ["70"]))
        XCTAssertTrue(Policy.isDirty(initial: ["70"], current: ["7"]))
    }

    func testReturningToTheOriginalStringIsCleanAgain() {
        XCTAssertFalse(Policy.isDirty(initial: ["a", "1"], current: ["a", "1"]))
    }

    // MARK: Close decision: busy > pending > dirty > clean

    func testCleanSheetClosesWithoutAsking() {
        XCTAssertEqual(Policy.decision(isBusy: false, hasPendingSave: false, isDirty: false), .close)
        XCTAssertNil(Policy.prompt(for: .close))
    }

    func testDirtySheetAsksBeforeDiscarding() {
        XCTAssertEqual(Policy.decision(isBusy: false, hasPendingSave: false, isDirty: true), .confirmDiscard)
        XCTAssertEqual(Policy.prompt(for: .confirmDiscard), .discard)
    }

    func testPendingSaveWinsOverDirty() {
        XCTAssertEqual(Policy.decision(isBusy: false, hasPendingSave: true, isDirty: true), .confirmPendingClose)
        XCTAssertEqual(Policy.decision(isBusy: false, hasPendingSave: true, isDirty: false), .confirmPendingClose)
        XCTAssertEqual(Policy.prompt(for: .confirmPendingClose), .pendingClose)
    }

    func testBusyBlocksEveryClose() {
        for pending in [false, true] {
            for dirty in [false, true] {
                XCTAssertEqual(Policy.decision(isBusy: true, hasPendingSave: pending, isDirty: dirty), .blocked)
            }
        }
        XCTAssertNil(Policy.prompt(for: .blocked))
    }

    // MARK: Confirmation handlers re-check the live state

    func testConfirmedDiscardClosesWhenStillDirtyOrAlreadyClean() {
        XCTAssertEqual(Policy.resolve(confirmed: .discard, isBusy: false, hasPendingSave: false, isDirty: true), .close)
        XCTAssertEqual(Policy.resolve(confirmed: .discard, isBusy: false, hasPendingSave: false, isDirty: false), .close)
    }

    func testConfirmedDiscardDoesNotCloseOverAStateThatMovedOn() {
        XCTAssertEqual(Policy.resolve(confirmed: .discard, isBusy: true, hasPendingSave: false, isDirty: true), .blocked)
        XCTAssertEqual(Policy.resolve(confirmed: .discard, isBusy: false, hasPendingSave: true, isDirty: true), .confirmPendingClose,
                       "an unconfirmed save appeared: ask with the pending wording instead")
    }

    func testConfirmedPendingCloseClosesUnlessBusy() {
        XCTAssertEqual(Policy.resolve(confirmed: .pendingClose, isBusy: false, hasPendingSave: true, isDirty: true), .close)
        XCTAssertEqual(Policy.resolve(confirmed: .pendingClose, isBusy: false, hasPendingSave: false, isDirty: true), .close,
                       "outcome became known as not applied meanwhile; the user agreed to lose the input")
        XCTAssertEqual(Policy.resolve(confirmed: .pendingClose, isBusy: false, hasPendingSave: false, isDirty: false), .close)
        XCTAssertEqual(Policy.resolve(confirmed: .pendingClose, isBusy: true, hasPendingSave: true, isDirty: false), .blocked)
    }

    // MARK: Delete

    func testDeleteRunsOnlyWhenIdleAndNotAlreadyRunning() {
        XCTAssertTrue(Policy.canDelete(isBusy: false, hasPendingSave: false, deleteInFlight: false))
        XCTAssertFalse(Policy.canDelete(isBusy: true, hasPendingSave: false, deleteInFlight: false))
        XCTAssertFalse(Policy.canDelete(isBusy: false, hasPendingSave: true, deleteInFlight: false))
        XCTAssertFalse(Policy.canDelete(isBusy: false, hasPendingSave: false, deleteInFlight: true), "a second tap must not delete twice")
    }

    // MARK: Copy

    @available(iOS 15.0, *)
    func testDeleteTargetDescribesTheStoredRecordAndFallsBackToManualEntry() throws {
        let day = try CalendarDay(iso8601: "2026-09-23")
        for language in ["en", "ko"] {
            let strings = try table(language)
            let template = try XCTUnwrap(strings["renewal_delete_confirm_target"])
            let manualEntry = try XCTUnwrap(strings["renewal_manual_entry"])
            let named = EditorPromptText.deleteTarget(name: "두부", day: day, centigrams: 1_250, decimalSeparator: ".",
                                                      template: template, manualEntry: manualEntry)
            XCTAssertEqual(named, "두부 · \(RecordHomeView.longDate(day)) · 12.5 g")
            let manual = EditorPromptText.deleteTarget(name: nil, day: day, centigrams: 1_000, decimalSeparator: ".",
                                                       template: template, manualEntry: manualEntry)
            XCTAssertTrue(manual.hasPrefix(manualEntry + " · "), manual)
            XCTAssertTrue(manual.hasSuffix(" · 10 g"), manual)
            let blank = EditorPromptText.deleteTarget(name: "", day: day, centigrams: 1_000, decimalSeparator: ".",
                                                      template: template, manualEntry: manualEntry)
            XCTAssertEqual(blank, manual, "\(language): an empty name is a manual entry")
        }
    }

    @available(iOS 15.0, *)
    func testPromptCopyNeverUsesFinalWordingForTheUnconfirmedClose() {
        for prompt in [EditorPrompt.discard, .delete, .pendingClose] {
            XCTAssertFalse(EditorPromptText.title(prompt).isEmpty)
            XCTAssertFalse(EditorPromptText.keep(prompt).isEmpty)
            XCTAssertFalse(EditorPromptText.confirm(prompt).isEmpty)
            XCTAssertNotEqual(EditorPromptText.keep(prompt), EditorPromptText.confirm(prompt))
        }
        XCTAssertTrue(EditorPromptText.message(.delete, deleteSummary: "x · y · 1 g").hasPrefix("x · y · 1 g\n"))
        XCTAssertEqual(EditorPromptText.message(.delete, deleteSummary: nil), RenewalStrings.text("renewal_delete_confirm_message"))
    }

    // MARK: Strings files (read from the source tree; the test bundle carries no resources)

    private func table(_ language: String) throws -> [String: String] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("ProteinTracker/Localization/\(language).lproj/Localizable.strings")
        return try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String], url.path)
    }

    func testEveryNewKeyIsLocalizedInBothLanguages() throws {
        let keys = ["renewal_discard_title", "renewal_discard_message", "renewal_discard_keep", "renewal_discard_confirm",
                    "renewal_delete_confirm_title", "renewal_delete_confirm_message", "renewal_delete_confirm_target",
                    "renewal_pending_close_title", "renewal_pending_close_message", "renewal_pending_close_stay",
                    "renewal_pending_close_confirm", "recovery_retry_hint", "recovery_title"]
        for language in ["en", "ko"] {
            let strings = try table(language)
            for key in keys {
                let value = strings[key]
                XCTAssertNotNil(value, "\(language) is missing \(key)")
                XCTAssertNotEqual(value, "", "\(language) has an empty \(key)")
            }
            XCTAssertEqual(strings["renewal_delete_confirm_target"]?.components(separatedBy: "%").count, 4, "\(language): three placeholders")
        }
    }

    func testPendingCloseCopyDoesNotClaimAnOutcome() throws {
        let banned = ["not saved", "wasn’t saved", "failed", "cancelled", "canceled", "deleted",
                      "저장 실패", "저장 취소", "삭제됨", "삭제됐", "저장되지 않았"]
        for language in ["en", "ko"] {
            let strings = try table(language)
            let text = ((strings["renewal_pending_close_title"] ?? "") + " " + (strings["renewal_pending_close_message"] ?? "")).lowercased()
            for word in banned {
                XCTAssertFalse(text.contains(word), "\(language): pending close must not say \"\(word)\"")
            }
            XCTAssertNotEqual(strings["renewal_pending_close_confirm"], strings["renewal_cancel"], "\(language): closing is not cancelling")
        }
    }
}

/// The sheet-scoped delegate takeover: decides close, forwards everything else
/// to SwiftUI's delegate, and hands the delegate back on detach.
@available(iOS 15.0, *)
final class SheetDismissAdapterTests: XCTestCase {
    final class RecordingDelegate: NSObject, UIAdaptivePresentationControllerDelegate {
        var allow = true
        var calls: [String] = []
        func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
            calls.append("should"); return allow
        }
        func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) { calls.append("attempt") }
        func presentationControllerWillDismiss(_ presentationController: UIPresentationController) { calls.append("will") }
        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { calls.append("did") }
    }

    func testTakesOverForwardsAndRestores() {
        let presentation = UIPresentationController(presentedViewController: UIViewController(), presenting: nil)
        let swiftUI = RecordingDelegate()
        presentation.delegate = swiftUI
        let coordinator = SheetDismissAdapter.Coordinator()
        var policyAllows = false
        var attempts = 0
        coordinator.shouldDismiss = { policyAllows }
        coordinator.onAttemptToDismiss = { attempts += 1 }

        coordinator.attach(to: presentation)
        XCTAssertTrue(presentation.delegate === coordinator)

        // Policy refuses: SwiftUI is not even asked.
        XCTAssertFalse(coordinator.presentationControllerShouldDismiss(presentation))
        XCTAssertEqual(swiftUI.calls, [])
        // Policy allows: SwiftUI's answer still counts.
        policyAllows = true
        swiftUI.allow = false
        XCTAssertFalse(coordinator.presentationControllerShouldDismiss(presentation))
        swiftUI.allow = true
        XCTAssertTrue(coordinator.presentationControllerShouldDismiss(presentation))

        coordinator.presentationControllerDidAttemptToDismiss(presentation)
        XCTAssertEqual(attempts, 1)
        coordinator.presentationControllerWillDismiss(presentation)
        coordinator.presentationControllerDidDismiss(presentation)
        XCTAssertEqual(swiftUI.calls, ["should", "should", "attempt", "will", "did"], "SwiftUI bookkeeping keeps running")

        // Re-attaching to the same controller is a no-op, not a self-forwarding loop.
        coordinator.attach(to: presentation)
        XCTAssertTrue(presentation.delegate === coordinator)
        coordinator.presentationControllerDidDismiss(presentation)
        XCTAssertEqual(swiftUI.calls.last, "did")
        XCTAssertEqual(swiftUI.calls.count, 6)

        coordinator.detach()
        XCTAssertTrue(presentation.delegate === swiftUI, "original delegate restored")
    }
}
