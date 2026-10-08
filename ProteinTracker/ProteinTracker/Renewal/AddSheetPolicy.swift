import Foundation
import HelloProteinCore

/// The add sheet's tabs. Only the current tab is ever saved; the other tab
/// holds no draft.
@available(iOS 15.0, *)
enum AddTab: String, Equatable, Hashable, CaseIterable {
    case manual
    case search
    case favorites
}

/// What would clear the search selection. Each asks first; cancelling keeps
/// results, selection and the confirmed language, and starts nothing.
@available(iOS 15.0, *)
enum SearchDiscardReason: Equatable {
    case newSearch(String)
    case recentSearch(SearchTerm)
    case languageChange(SearchLanguage)

    var id: String {
        switch self {
        case .newSearch: return "newSearch"
        case .recentSearch(let term): return "recentSearch.\(term.id)"
        case .languageChange(let language): return "languageChange.\(language.rawValue)"
        }
    }
}

/// Every confirmation the add sheet can show. One at a time, none while an
/// error alert is up; the sheet serialises them through a single state.
@available(iOS 15.0, *)
enum AddSheetPrompt: Equatable, Identifiable {
    /// Close with unsaved input or a selection.
    case discard
    /// Close while a write of this session is unconfirmed.
    case pendingClose
    /// Move to the other tab, losing the current tab's input or selection.
    case switchTab(AddTab)
    /// Enter favorite editing while items are selected.
    case discardSelection(favoriteID: String)
    /// Remove one favorite; the summary names the stored entry.
    case deleteFavorite(FavoriteFood)
    /// Leave favorite editing with changed fields.
    case discardEdit
    /// A new search, a recent-search tap or a language change while results
    /// are selected.
    case discardSearch(SearchDiscardReason)
    /// Remove one recent search; the summary names the stored term.
    case deleteSearchTerm(SearchTerm)
    /// Copy a result's name into manual entry (unknown reference amount),
    /// dropping the search selection.
    case copyNameToManual(name: String)

    var id: String {
        switch self {
        case .discard: return "discard"
        case .discardEdit: return "discardEdit"
        case .pendingClose: return "pendingClose"
        case .switchTab(let tab): return "switchTab.\(tab.rawValue)"
        case .discardSelection(let id): return "discardSelection.\(id)"
        case .deleteFavorite(let favorite): return "deleteFavorite.\(favorite.id)"
        case .discardSearch(let reason): return "discardSearch.\(reason.id)"
        case .deleteSearchTerm(let term): return "deleteSearchTerm.\(term.id)"
        case .copyNameToManual(let name): return "copyNameToManual.\(name)"
        }
    }
}

/// What the sheet does once a pending write of this session is confirmed.
@available(iOS 15.0, *)
enum AddSheetConfirmedAction: Equatable {
    /// The record(s) are in the file: the sheet's job is done.
    case close
    /// The favorite edit landed: back to the list, sheet stays open.
    case leaveEdit
    /// The delete landed (or the kind is unknown): stay where the user is.
    case stay
}

@available(iOS 15.0, *)
enum AddSheetSwitchDecision: Equatable {
    /// Already on that tab.
    case stay
    /// A write is running or unconfirmed: tabs do not move.
    case blocked
    /// Ask first; the tab changes only after the user agrees.
    case confirm
    case switchNow
}

/// Pure decisions for the tabbed add sheet, so they can be unit tested.
/// Closing reuses `EditorDismissPolicy`; this adds tab switching, selection
/// and the enable rules.
@available(iOS 15.0, *)
enum AddSheetPolicy {
    /// Tab switch: same tab is a no-op; busy or pending blocks; a dirty
    /// current tab asks; otherwise switch at once.
    static func switchDecision(to target: AddTab, current: AddTab, isBusy: Bool, hasPendingSave: Bool,
                               currentTabDirty: Bool) -> AddSheetSwitchDecision {
        if target == current { return .stay }
        if isBusy || hasPendingSave { return .blocked }
        return currentTabDirty ? .confirm : .switchNow
    }

    /// The manual tab is dirty when a field or the favorite toggle differs
    /// from how it opened. Exact comparison, like the other editors.
    static func isManualDirty(initial: [String], current: [String], initialFavorite: Bool, currentFavorite: Bool) -> Bool {
        EditorDismissPolicy.isDirty(initial: initial, current: current) || initialFavorite != currentFavorite
    }

    /// The favorites tab is dirty when something is selected or a favorite is
    /// being edited with changed fields.
    static func isFavoritesDirty(selectionCount: Int, editorDirty: Bool) -> Bool {
        selectionCount > 0 || editorDirty
    }

    /// The search tab is dirty only when results are selected. Typed query
    /// text, shown results and an expanded recent list are not worth a prompt.
    static func isSearchDirty(selectionCount: Int) -> Bool {
        selectionCount > 0
    }

    /// Starting a new search, re-running a recent one or changing the
    /// language: blocked while busy/pending; asks when a selection would be
    /// lost; otherwise goes ahead at once.
    static func searchActionDecision(isBusy: Bool, hasPendingSave: Bool, selectionCount: Int) -> AddSheetSwitchDecision {
        if isBusy || hasPendingSave { return .blocked }
        return selectionCount > 0 ? .confirm : .switchNow
    }

    /// Whether a language pick writes anything: the confirmed language is a
    /// no-op; a fallback (unknown stored value) is replaced by the explicit pick.
    static func languageChangeIsNeeded(current: SearchLanguageSetting, picked: SearchLanguage) -> Bool {
        current.isFallback || current.resolved != picked
    }

    /// Entering favorite editing: blocked while busy/pending; asks when a
    /// selection would be lost; otherwise enters at once.
    static func editDecision(isBusy: Bool, hasPendingSave: Bool, selectionCount: Int) -> AddSheetSwitchDecision {
        if isBusy || hasPendingSave { return .blocked }
        return selectionCount > 0 ? .confirm : .switchNow
    }

    /// A confirmed outcome means something different per operation.
    static func afterConfirmed(_ kind: RecordHomeViewModel.OperationKind?) -> AddSheetConfirmedAction {
        switch kind {
        case .record, .favoriteBatch, .searchBatch: return .close
        case .favoriteEdit: return .leaveEdit
        case .favoriteDelete, .searchHistory, .searchHistoryDelete, .searchLanguage, .goal, .legacyTotal, .unknown, nil:
            return .stay
        }
    }

    /// Manual-entry draft after "use name in manual entry": only the name,
    /// protein empty, favorite off. The copied name counts as dirty.
    static func manualDraft(copyingName name: String) -> (name: String, protein: String, saveAsFavorite: Bool) {
        (name: name, protein: "", saveAsFavorite: false)
    }

    /// The batch button: something selected, not locked, and a sum that fits.
    static func canAddSelection(locked: Bool, selectionCount: Int, totalCentigrams: Int64?) -> Bool {
        !locked && selectionCount > 0 && totalCentigrams != nil
    }

    /// Whether a favorite row can be picked for a record: positive amount and
    /// not locked. Invalid rows stay visible but cannot be selected.
    static func canSelect(_ favorite: FavoriteFood, locked: Bool) -> Bool {
        !locked && FavoriteCollection.recordAmount(of: favorite) != nil
    }

    /// Record IDs are fixed per favorite for the whole session: deselecting
    /// and re-selecting, or retrying after a failure, reuses the same ID.
    static func recordID(for favoriteID: String, in ids: inout [String: String], make: () -> String) -> String {
        if let existing = ids[favoriteID] { return existing }
        let id = make()
        ids[favoriteID] = id
        return id
    }
}
