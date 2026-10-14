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
        XCTAssertFalse(AddSheetPolicy.isSearchDirty(selectionCount: 0, amountDraftCount: 0), "typed text, results and the recent list are not a draft")
        XCTAssertTrue(AddSheetPolicy.isSearchDirty(selectionCount: 1, amountDraftCount: 0))
        XCTAssertTrue(AddSheetPolicy.isSearchDirty(selectionCount: 0, amountDraftCount: 1), "an applied amount is a draft in its own right")
        XCTAssertTrue(AddSheetPolicy.canEditAmount(locked: false, isSelected: true, hasBasis: true))
        XCTAssertFalse(AddSheetPolicy.canEditAmount(locked: true, isSelected: true, hasBasis: true))
        XCTAssertFalse(AddSheetPolicy.canEditAmount(locked: false, isSelected: false, hasBasis: true))
        XCTAssertFalse(AddSheetPolicy.canEditAmount(locked: false, isSelected: true, hasBasis: false), "no basis, no amount editing")
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

@available(iOS 15.0, *)
final class PortionEditorPolicyTests: XCTestCase {
    private var per100g: FoodQuantity { try! FoodQuantity(value: "100", unit: .gram) }
    private var basis: CalculationBasis {
        try! CalculationBasis.providerSnapshot(proteinGramsText: "12.18", referenceQuantity: per100g,
                                               providerID: "mfds", dataVersion: "2026-10", itemID: "D000001")
    }

    private func item(raw: String = "12.18", centigrams: Int64? = 1_218, reference: String? = "100",
                      unavailability: SearchItemUnavailability? = nil) -> SearchResultItem {
        SearchResultItem(providerID: "mfds", dataVersion: "2026-10", itemID: "D1", name: "Chicken", rawProtein: raw,
                         proteinCentigrams: centigrams, rounded: false,
                         reference: reference.map { SearchReferenceAmount(quantity: try! FoodQuantity(value: $0, unit: .gram)) },
                         sourceKey: "renewal_search_source_mfds", unavailability: unavailability)
    }

    func testPreviewComputesFromTheBasisInTheUsersSeparatorAndNamesEveryError() throws {
        XCTAssertEqual(PortionEditorPolicy.preview(basis: basis, amountText: "150", decimalSeparator: "."),
                       .valid(quantity: try FoodQuantity(value: "150", unit: .gram), centigrams: 1_827, rounded: false))
        XCTAssertEqual(PortionEditorPolicy.preview(basis: basis, amountText: " 150,5 ", decimalSeparator: ",").centigrams, 1_833, "150.5 → 18.3309 → 18.33")
        XCTAssertEqual(PortionEditorPolicy.preview(basis: basis, amountText: "150.5", decimalSeparator: ",").quantity?.value, "150.5", "a lone point is the decimal point in a comma locale")
        if case .valid(_, _, let rounded) = PortionEditorPolicy.preview(basis: basis, amountText: "150.5", decimalSeparator: ".") {
            XCTAssertTrue(rounded)
        } else { XCTFail() }
        XCTAssertEqual(PortionEditorPolicy.preview(basis: basis, amountText: "", decimalSeparator: "."), .input(.empty))
        XCTAssertEqual(PortionEditorPolicy.preview(basis: basis, amountText: "abc", decimalSeparator: "."), .input(.notANumber))
        XCTAssertEqual(PortionEditorPolicy.preview(basis: basis, amountText: "1e3", decimalSeparator: "."), .input(.notANumber))
        XCTAssertEqual(PortionEditorPolicy.preview(basis: basis, amountText: "0", decimalSeparator: "."), .input(.zero))
        XCTAssertEqual(PortionEditorPolicy.preview(basis: basis, amountText: "-5", decimalSeparator: "."), .input(.negative))
        XCTAssertEqual(PortionEditorPolicy.preview(basis: basis, amountText: "1 000", decimalSeparator: "."), .input(.groupingNotAllowed))
        XCTAssertEqual(PortionEditorPolicy.preview(basis: basis, amountText: "1.5.5", decimalSeparator: "."), .input(.mixedSeparators))
        XCTAssertEqual(PortionEditorPolicy.preview(basis: basis, amountText: "1234567890", decimalSeparator: "."), .input(.tooManyIntegerDigits))
        XCTAssertEqual(PortionEditorPolicy.preview(basis: basis, amountText: "1.2345", decimalSeparator: "."), .input(.tooManyFractionDigits))
        XCTAssertEqual(PortionEditorPolicy.preview(basis: basis, amountText: "0.01", decimalSeparator: "."), .calculation(.roundsToZero))
        let huge = try CalculationBasis.userDefined(proteinGramsText: "999999999999999999", referenceQuantity: FoodQuantity(value: "1", unit: .gram))
        XCTAssertEqual(PortionEditorPolicy.preview(basis: huge, amountText: "999999999", decimalSeparator: "."), .calculation(.overflow))
        XCTAssertNil(PortionEditorPolicy.preview(basis: basis, amountText: "x", decimalSeparator: ".").centigrams, "no stale result for a bad input")
    }

    func testDirtyApplyAndTextHelpers() throws {
        XCTAssertFalse(PortionEditorPolicy.isDirty(initial: "150", current: "150"))
        XCTAssertTrue(PortionEditorPolicy.isDirty(initial: "150", current: "150 "), "exact text, like the other editors")
        let valid = PortionEditorPolicy.preview(basis: basis, amountText: "150", decimalSeparator: ".")
        XCTAssertTrue(PortionEditorPolicy.canApply(valid, locked: false))
        XCTAssertFalse(PortionEditorPolicy.canApply(valid, locked: true))
        XCTAssertFalse(PortionEditorPolicy.canApply(.input(.empty), locked: false))
        XCTAssertEqual(PortionEditorPolicy.amountText(try FoodQuantity(value: "150.5", unit: .gram), decimalSeparator: ","), "150,5")
        let raw = try CalculationBasis.userDefined(proteinGramsText: "1.005", referenceQuantity: per100g)
        XCTAssertEqual(PortionEditorPolicy.basisProteinText(raw, decimalSeparator: ","), "1,005", "full stored precision, never 1.01")
    }

    func testResultRowsGetABasisOnlyWhenTheyCanBeRecalculatedExactly() throws {
        let editable = try XCTUnwrap(item().calculationBasis)
        XCTAssertEqual(editable.origin, .providerSnapshot)
        XCTAssertEqual(editable.proteinGramsText, "12.18")
        XCTAssertEqual(editable.provider?.itemID, "D1")
        XCTAssertEqual(editable.referenceQuantity, per100g)
        XCTAssertNotNil(item(raw: "1.005", centigrams: 101).calculationBasis, "the provider's half-up rounding is reproduced")
        XCTAssertNil(item(raw: "12.18", centigrams: 1_219).calculationBasis, "a value the calculation would not reproduce gets no basis")
        XCTAssertNil(item(reference: "0.0001").calculationBasis, "reference outside the amount editor's range")
        XCTAssertNil(item(reference: "1234567890").calculationBasis)
        XCTAssertNil(item(raw: "abc", centigrams: nil, unavailability: .invalidProtein).calculationBasis)
        XCTAssertNil(item(reference: nil, unavailability: .unknownReference).calculationBasis)
        XCTAssertNil(item(raw: "0.0000000001", centigrams: 0, unavailability: .zeroProtein).calculationBasis)
    }
}
