import XCTest
import HelloProteinCore

@available(iOS 15.0, *)
final class AddSheetPolicyTests: XCTestCase {
    func testSwitchingTabsIsANoOpOnTheSameTabBlockedWhileBusyOrPendingAndAsksOnlyWhenDirty() {
        XCTAssertEqual(AddSheetPolicy.switchDecision(to: .manual, current: .manual, isBusy: false, hasPendingSave: false, currentTabDirty: true), .stay)
        XCTAssertEqual(AddSheetPolicy.switchDecision(to: .favorites, current: .manual, isBusy: true, hasPendingSave: false, currentTabDirty: false), .blocked)
        XCTAssertEqual(AddSheetPolicy.switchDecision(to: .favorites, current: .manual, isBusy: false, hasPendingSave: true, currentTabDirty: false), .blocked)
        XCTAssertEqual(AddSheetPolicy.switchDecision(to: .favorites, current: .manual, isBusy: false, hasPendingSave: false, currentTabDirty: true), .confirm)
        XCTAssertEqual(AddSheetPolicy.switchDecision(to: .manual, current: .favorites, isBusy: false, hasPendingSave: false, currentTabDirty: false), .switchNow)
    }

    func testManualDirtyCountsFieldsAndTheFavoriteToggle() {
        XCTAssertFalse(AddSheetPolicy.isManualDirty(initial: ["", ""], current: ["", ""], initialFavorite: false, currentFavorite: false))
        XCTAssertTrue(AddSheetPolicy.isManualDirty(initial: ["", ""], current: [" ", ""], initialFavorite: false, currentFavorite: false))
        XCTAssertTrue(AddSheetPolicy.isManualDirty(initial: ["", ""], current: ["", ""], initialFavorite: false, currentFavorite: true))
        XCTAssertFalse(AddSheetPolicy.isManualDirty(initial: ["Egg", "6"], current: ["Egg", "6"], initialFavorite: false, currentFavorite: false))
    }

    func testFavoritesDirtyCountsSelectionOrAChangedEditor() {
        XCTAssertFalse(AddSheetPolicy.isFavoritesDirty(selectionCount: 0, editorDirty: false))
        XCTAssertTrue(AddSheetPolicy.isFavoritesDirty(selectionCount: 1, editorDirty: false))
        XCTAssertTrue(AddSheetPolicy.isFavoritesDirty(selectionCount: 0, editorDirty: true))
    }

    func testEditingAsksOnlyWhenASelectionWouldBeLost() {
        XCTAssertEqual(AddSheetPolicy.editDecision(isBusy: true, hasPendingSave: false, selectionCount: 0), .blocked)
        XCTAssertEqual(AddSheetPolicy.editDecision(isBusy: false, hasPendingSave: true, selectionCount: 2), .blocked)
        XCTAssertEqual(AddSheetPolicy.editDecision(isBusy: false, hasPendingSave: false, selectionCount: 2), .confirm)
        XCTAssertEqual(AddSheetPolicy.editDecision(isBusy: false, hasPendingSave: false, selectionCount: 0), .switchNow)
    }

    func testAddButtonNeedsASelectionAnUnlockedSheetAndAFittingSum() {
        XCTAssertFalse(AddSheetPolicy.canAddSelection(locked: false, selectionCount: 0, totalCentigrams: 0))
        XCTAssertFalse(AddSheetPolicy.canAddSelection(locked: true, selectionCount: 2, totalCentigrams: 100))
        XCTAssertFalse(AddSheetPolicy.canAddSelection(locked: false, selectionCount: 2, totalCentigrams: nil))
        XCTAssertTrue(AddSheetPolicy.canAddSelection(locked: false, selectionCount: 2, totalCentigrams: 100))
    }

    func testOnlyPositiveFavoritesCanBeSelectedAndNeverWhileLocked() throws {
        let valid = try FavoriteFood(id: "a", name: "A", proteinCentigrams: 100, position: 0)
        let zero = try FavoriteFood(id: "b", name: "B", proteinCentigrams: 0, position: 1)
        let negative = try FavoriteFood(id: "c", name: "", proteinCentigrams: -500, position: 2)
        XCTAssertTrue(AddSheetPolicy.canSelect(valid, locked: false))
        XCTAssertFalse(AddSheetPolicy.canSelect(valid, locked: true))
        XCTAssertFalse(AddSheetPolicy.canSelect(zero, locked: false))
        XCTAssertFalse(AddSheetPolicy.canSelect(negative, locked: false))
    }

    func testRecordIDsAreFixedPerFavoriteForTheSession() {
        var ids: [String: String] = [:]
        var counter = 0
        func make() -> String { counter += 1; return "r\(counter)" }
        let first = AddSheetPolicy.recordID(for: "fav-1", in: &ids, make: make)
        let again = AddSheetPolicy.recordID(for: "fav-1", in: &ids, make: make)
        let other = AddSheetPolicy.recordID(for: "fav-2", in: &ids, make: make)
        XCTAssertEqual(first, "r1")
        XCTAssertEqual(again, "r1", "deselect and re-select keeps the ID")
        XCTAssertEqual(other, "r2")
        XCTAssertEqual(counter, 2)
    }

    func testConfirmedPendingOutcomeDependsOnTheOperation() {
        XCTAssertEqual(AddSheetPolicy.afterConfirmed(.record), .close)
        XCTAssertEqual(AddSheetPolicy.afterConfirmed(.favoriteBatch), .close)
        XCTAssertEqual(AddSheetPolicy.afterConfirmed(.searchBatch), .close)
        XCTAssertEqual(AddSheetPolicy.afterConfirmed(.searchHistory), .stay, "no re-search, no second write")
        XCTAssertEqual(AddSheetPolicy.afterConfirmed(.searchHistoryDelete), .stay)
        XCTAssertEqual(AddSheetPolicy.afterConfirmed(.searchLanguage), .stay)
        XCTAssertEqual(AddSheetPolicy.afterConfirmed(.favoriteEdit), .leaveEdit)
        XCTAssertEqual(AddSheetPolicy.afterConfirmed(.favoriteDelete), .stay)
        XCTAssertEqual(AddSheetPolicy.afterConfirmed(.unknown), .stay)
        XCTAssertEqual(AddSheetPolicy.afterConfirmed(nil), .stay)
    }

    func testPromptIdentitiesAreDistinct() throws {
        let favorite = try FavoriteFood(id: "x", name: "X", proteinCentigrams: 1, position: 0)
        let term = try SearchTerm(id: "t", value: "egg", position: 0)
        let prompts: [AddSheetPrompt] = [.discard, .pendingClose, .switchTab(.manual), .switchTab(.search), .switchTab(.favorites),
                                         .discardSelection(favoriteID: "x"), .deleteFavorite(favorite), .discardEdit,
                                         .discardSearch(.newSearch("egg")), .discardSearch(.recentSearch(term)),
                                         .discardSearch(.languageChange(.english)), .discardSearch(.languageChange(.korean)),
                                         .deleteSearchTerm(term), .copyNameToManual(name: "Brie")]
        XCTAssertEqual(Set(prompts.map(\.id)).count, prompts.count)
    }

    func testSearchTabIsDirtyOnlyWithASelectionAndSearchActionsAskOnlyThen() {
        XCTAssertFalse(AddSheetPolicy.isSearchDirty(selectionCount: 0), "typed text, results and the recent list are not a draft")
        XCTAssertTrue(AddSheetPolicy.isSearchDirty(selectionCount: 1))
        XCTAssertEqual(AddSheetPolicy.searchActionDecision(isBusy: true, hasPendingSave: false, selectionCount: 0), .blocked)
        XCTAssertEqual(AddSheetPolicy.searchActionDecision(isBusy: false, hasPendingSave: true, selectionCount: 0), .blocked)
        XCTAssertEqual(AddSheetPolicy.searchActionDecision(isBusy: false, hasPendingSave: false, selectionCount: 2), .confirm)
        XCTAssertEqual(AddSheetPolicy.searchActionDecision(isBusy: false, hasPendingSave: false, selectionCount: 0), .switchNow)
    }

    func testLanguagePickWritesOnlyWhenItChangesSomething() {
        XCTAssertFalse(AddSheetPolicy.languageChangeIsNeeded(current: .confirmed(.korean), picked: .korean))
        XCTAssertTrue(AddSheetPolicy.languageChangeIsNeeded(current: .confirmed(.korean), picked: .english))
        XCTAssertTrue(AddSheetPolicy.languageChangeIsNeeded(current: .interpret(raw: "english"), picked: .english), "a fallback is replaced by the explicit pick")
        XCTAssertTrue(AddSheetPolicy.languageChangeIsNeeded(current: .interpret(raw: nil), picked: .english))
    }

    func testCopyingANameToManualEntryCarriesOnlyTheName() {
        let draft = AddSheetPolicy.manualDraft(copyingName: "Cheese, brie")
        XCTAssertEqual(draft.name, "Cheese, brie")
        XCTAssertEqual(draft.protein, "")
        XCTAssertFalse(draft.saveAsFavorite)
        XCTAssertTrue(AddSheetPolicy.isManualDirty(initial: ["", ""], current: [draft.name, draft.protein],
                                                   initialFavorite: false, currentFavorite: draft.saveAsFavorite))
    }
}
