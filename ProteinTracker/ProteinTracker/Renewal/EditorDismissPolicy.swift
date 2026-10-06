import Foundation

/// What an editing sheet does when the user asks to close it, by Cancel or by
/// swiping it down. Pure so it can be unit tested without SwiftUI.
enum EditorCloseDecision: Equatable {
    /// Nothing to lose: close immediately.
    case close
    /// Unsaved input would be lost: ask first.
    case confirmDiscard
    /// A save or deletion of this session has not been confirmed yet: ask first,
    /// with wording that does not call it a cancellation or a failure.
    case confirmPendingClose
    /// A write or re-read is running: the sheet cannot close right now.
    case blocked
}

/// A confirmation the sheet may show. Only one can be visible at a time, and
/// none while an error alert is up.
enum EditorPrompt: Equatable, Identifiable {
    case discard
    case delete
    case pendingClose

    var id: Self { self }
}

enum EditorDismissPolicy {
    /// Priority: busy > pending > dirty > clean. "Pending" wins over "dirty"
    /// because the unsaved input is not the thing the user needs to know about.
    static func decision(isBusy: Bool, hasPendingSave: Bool, isDirty: Bool) -> EditorCloseDecision {
        if isBusy { return .blocked }
        if hasPendingSave { return .confirmPendingClose }
        if isDirty { return .confirmDiscard }
        return .close
    }

    /// Exact comparison against the strings the fields started with. Whitespace
    /// and formatting differences count as changes: the user typed them.
    static func isDirty(initial: [String], current: [String]) -> Bool {
        initial != current
    }

    /// The prompt to show for a decision, or nil when the sheet closes or stays
    /// without asking.
    static func prompt(for decision: EditorCloseDecision) -> EditorPrompt? {
        switch decision {
        case .confirmDiscard: return .discard
        case .confirmPendingClose: return .pendingClose
        case .close, .blocked: return nil
        }
    }

    /// Whether the user's confirmation of `prompt` still closes the sheet given
    /// the state at the moment the button was tapped. If the state moved on
    /// (a save started, or an unconfirmed save appeared while the discard
    /// prompt was up), the sheet stays and the caller shows the newer prompt.
    static func resolve(confirmed prompt: EditorPrompt, isBusy: Bool, hasPendingSave: Bool, isDirty: Bool) -> EditorCloseDecision {
        let current = decision(isBusy: isBusy, hasPendingSave: hasPendingSave, isDirty: isDirty)
        switch (prompt, current) {
        case (_, .close), (_, .blocked):
            return current
        case (.discard, .confirmDiscard), (.pendingClose, .confirmPendingClose):
            return .close
        case (.pendingClose, .confirmDiscard):
            // The outcome became known (not applied) while the prompt was up;
            // the user agreed to lose the input anyway.
            return .close
        default:
            return current
        }
    }

    /// Whether a delete may start now. One call per confirmation; nothing while
    /// a write runs, while an outcome is unknown, or while a delete is already
    /// in flight.
    static func canDelete(isBusy: Bool, hasPendingSave: Bool, deleteInFlight: Bool) -> Bool {
        !isBusy && !hasPendingSave && !deleteInFlight
    }
}
