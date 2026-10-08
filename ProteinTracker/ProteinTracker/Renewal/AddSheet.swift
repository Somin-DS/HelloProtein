import SwiftUI
import HelloProteinCore

/// Fixed when the sheet opens: the day every write of this session targets
/// (today or a past day; it never moves, even past midnight) and the IDs a
/// manual save uses so a retry can never add twice.
@available(iOS 15.0, *)
struct AddSheetTarget: Identifiable {
    let id = UUID()
    let day: CalendarDay
    let manualRecordID = UUID().uuidString
    let manualFavoriteID = UUID().uuidString
}

/// The add sheet: manual entry, search and favorites tabs. Only the current
/// tab holds a draft; switching with unsaved input or a selection asks first.
/// Favorites are read from the last confirmed state and managed in place
/// (edit mode, delete); records from favorites or search results are added
/// as one commit. Search lookups live in `SearchSessionModel`; every write
/// (history, language, records) goes through the view model from here.
@available(iOS 15.0, *)
struct AddSheet: View {
    let target: AddSheetTarget
    @ObservedObject var model: RecordHomeViewModel
    @StateObject private var search: SearchSessionModel
    @Environment(\.dismiss) private var dismiss

    init(target: AddSheetTarget, model: RecordHomeViewModel,
         makeSearchProvider: @escaping (SearchLanguage) -> FoodSearchProvider) {
        self.target = target
        self.model = model
        _search = StateObject(wrappedValue: SearchSessionModel(language: model.searchLanguage.resolved,
                                                               makeProvider: makeSearchProvider))
    }

    @State private var tab: AddTab = .manual
    // Search tab
    /// The last executed search's term could not be recorded; searching went on.
    @State private var historyNotSaved = false
    // Manual tab
    @State private var name = ""
    @State private var protein = ""
    @State private var saveAsFavorite = false
    // Favorites tab
    /// Selected favorite IDs in selection order; the snapshots are what the
    /// user saw when picking, re-checked inside the commit.
    @State private var selected: [String] = []
    @State private var snapshots: [String: FavoriteSelection] = [:]
    /// Record IDs per favorite, kept for the whole session.
    @State private var recordIDs: [String: String] = [:]
    @State private var editing: FavoriteFood?
    @State private var editName = ""
    @State private var editProtein = ""
    @State private var editInitial: [String] = []
    // Shared
    @State private var error: RecordHomeViewModel.ActionError?
    @State private var prompt: AddSheetPrompt?
    @State private var favoriteExistsNotice = false
    /// Set when a write of this session ended unconfirmed; the kind decides
    /// what a confirmed outcome means.
    @State private var saveUnconfirmed = false
    @State private var sessionOperation: RecordHomeViewModel.OperationKind?
    @State private var deleteInFlight = false

    // MARK: Derived state

    private var locked: Bool { model.isBusy || saveUnconfirmed }
    private var hasPendingSave: Bool { saveUnconfirmed || model.pendingSave != nil }
    private var manualDirty: Bool {
        AddSheetPolicy.isManualDirty(initial: ["", ""], current: [name, protein],
                                     initialFavorite: false, currentFavorite: saveAsFavorite)
    }
    private var editorDirty: Bool {
        editing != nil && EditorDismissPolicy.isDirty(initial: editInitial, current: [editName, editProtein])
    }
    private var favoritesDirty: Bool {
        AddSheetPolicy.isFavoritesDirty(selectionCount: selected.count, editorDirty: editorDirty)
    }
    private var searchDirty: Bool { AddSheetPolicy.isSearchDirty(selectionCount: search.selected.count) }
    private var currentTabDirty: Bool {
        switch tab {
        case .manual: return manualDirty
        case .search: return searchDirty
        case .favorites: return favoritesDirty
        }
    }
    private var closeDecision: EditorCloseDecision {
        EditorDismissPolicy.decision(isBusy: model.isBusy, hasPendingSave: hasPendingSave, isDirty: currentTabDirty)
    }
    private var selections: [FavoriteSelection] { selected.compactMap { snapshots[$0] } }
    /// nil when the checked sum overflows; the add button is then disabled.
    private var totalCentigrams: Int64? { try? FavoriteBatch.totalCentigrams(selections) }
    private var canAdd: Bool {
        AddSheetPolicy.canAddSelection(locked: locked, selectionCount: selected.count, totalCentigrams: totalCentigrams)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                tabBar
                    .alert(Text("renewal_favorite_exists_title"), isPresented: $favoriteExistsNotice) {
                        // The record is saved; closing is the only next step.
                        // After the alert has finished closing, so the dismiss is not swallowed.
                        Button { DispatchQueue.main.async { dismiss() } } label: { Text("renewal_ok") }
                    } message: { Text("renewal_favorite_exists_message") }
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch tab {
                        case .manual: manualTab
                        case .search: searchTab
                        case .favorites: favoritesTab
                        }
                        if saveUnconfirmed {
                            PendingSaveSection(model: model, onConfirmed: confirmedPending, onNotApplied: {
                                saveUnconfirmed = false
                                showError(.notApplied)
                            }, onError: { showError($0) })
                        }
                    }
                    .padding(RenewalTheme.pageInset)
                    .addSheetPromptAlert($prompt, decimalSeparator: model.decimalSeparator, onConfirm: confirm)
                    .background(SheetDismissAdapter(shouldDismiss: { closeDecision == .close },
                                                    onAttemptToDismiss: { requestClose() }))
                }
                .actionErrorAlert($error)
                if tab == .favorites, editing == nil { selectionBar }
                if tab == .search, search.hasSelection { searchSelectionBar }
            }
            .background(RenewalTheme.canvas)
            .navigationTitle(Text("renewal_add"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { requestClose() } label: { Text("renewal_cancel").frame(minWidth: 44, minHeight: 44) }
                        .disabled(model.isBusy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    // The top Save belongs to the manual entry; the favorites
                    // tab adds with its own button and edits save in place.
                    if tab == .manual {
                        Button { saveManual() } label: { Text("renewal_save").frame(minWidth: 44, minHeight: 44) }
                            .disabled(locked)
                            .opacity(locked ? 0.5 : 1)
                            .accessibilityIdentifier("renewal.add.save")
                    }
                }
            }
            .interactiveDismissDisabled(model.isBusy)
        }
        .navigationViewStyle(.stack)
        .tint(RenewalTheme.action)
        .preferredColorScheme(.light)
        // Closing the sheet (by any route) cancels the lookup and forgets the results.
        .onDisappear { search.invalidate() }
    }

    // MARK: Tabs

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(.manual, key: "renewal_tab_manual")
            tabButton(.search, key: "renewal_tab_search")
            tabButton(.favorites, key: "renewal_tab_favorites")
        }
        .padding(.horizontal, RenewalTheme.pageInset)
        .padding(.top, 8)
        .background(RenewalTheme.canvas)
    }

    private func tabButton(_ value: AddTab, key: String) -> some View {
        let isCurrent = tab == value
        return Button { selectTab(value) } label: {
            VStack(spacing: 6) {
                Text(LocalizedStringKey(key))
                    .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                    .foregroundColor(isCurrent ? RenewalTheme.ink : RenewalTheme.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
                Rectangle().fill(isCurrent ? RenewalTheme.action : Color.clear).frame(height: 3)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
        .accessibilityIdentifier("renewal.add.tab.\(value.rawValue)")
    }

    private func selectTab(_ value: AddTab) {
        switch AddSheetPolicy.switchDecision(to: value, current: tab, isBusy: model.isBusy,
                                             hasPendingSave: hasPendingSave, currentTabDirty: currentTabDirty) {
        case .stay, .blocked: break
        case .confirm: show(.switchTab(value))
        case .switchNow: applySwitch(to: value)
        }
    }

    /// Drops the current tab's draft only; record IDs survive so a later
    /// re-selection of the same favorite keeps its ID.
    private func applySwitch(to value: AddTab) {
        switch tab {
        case .manual:
            name = ""
            protein = ""
            saveAsFavorite = false
        case .search:
            // Cancels any request and forgets results and selection; the
            // next visit starts from the saved language and recent list.
            search.invalidate()
            historyNotSaved = false
        case .favorites:
            selected = []
            snapshots = [:]
            editing = nil
        }
        tab = value
    }

    // MARK: Search tab

    private var searchTab: some View {
        SearchTab(session: search, model: model, targetDay: target.day, locked: locked, historyNotSaved: historyNotSaved,
                  actions: SearchTabActions(
                    search: { query in requestSearch(.newSearch(query)) },
                    recent: { term in requestSearch(.recentSearch(term)) },
                    deleteRecent: { term in requestDeleteRecent(term) },
                    pickLanguage: { language in requestLanguage(language) },
                    useName: { item in requestUseName(item) }))
    }

    /// A new search, a recent tap or a language pick: blocked while locked,
    /// asks when a selection would be lost, otherwise runs at once.
    private func requestSearch(_ reason: SearchDiscardReason) {
        switch AddSheetPolicy.searchActionDecision(isBusy: model.isBusy, hasPendingSave: hasPendingSave,
                                                   selectionCount: search.selected.count) {
        case .blocked, .stay: break
        case .confirm: show(.discardSearch(reason))
        case .switchNow: performSearchAction(reason)
        }
    }

    private func requestLanguage(_ language: SearchLanguage) {
        guard AddSheetPolicy.languageChangeIsNeeded(current: model.searchLanguage, picked: language) else { return }
        // A fallback setting that already resolves to this language: the
        // write confirms it, results of this language stay, so no prompt.
        if search.language == language {
            guard !locked else { return }
            return changeLanguage(language)
        }
        requestSearch(.languageChange(language))
    }

    private func performSearchAction(_ reason: SearchDiscardReason) {
        guard !locked else { return }
        switch reason {
        case .newSearch(let query): runSearch(query)
        case .recentSearch(let term): runSearch(term.value)
        case .languageChange(let language): changeLanguage(language)
        }
    }

    /// An explicit search: the term is recorded first (one attempt, with its
    /// own new ID), whatever that write's outcome the lookup then runs once
    /// for this generation. A later reconfirm never re-searches or re-writes.
    private func runSearch(_ query: String) {
        historyNotSaved = false
        guard SearchSessionModel.normalized(query) != nil else {
            // A blank query shows the recent list again; nothing is written or requested.
            search.invalidate()
            return
        }
        search.execute(query: query) { trimmed, proceed in
            model.recordSearchTerm(query: trimmed, newID: UUID().uuidString) { result in
                switch result {
                case .success:
                    break
                case .failure(.unconfirmed(let operationID)):
                    sessionOperation = .searchHistory
                    saveUnconfirmed = true
                    showError(.unconfirmed(operationID: operationID))
                case .failure:
                    // The term is not in the list; the search itself is unaffected.
                    historyNotSaved = true
                }
                proceed()
            }
        }
    }

    /// The language is a separate write. Results and selection are dropped
    /// only once the new language is confirmed in the file.
    private func changeLanguage(_ language: SearchLanguage) {
        model.setSearchLanguage(language) { result in
            switch result {
            case .success:
                search.applyLanguage(language)
            case .failure(.unconfirmed(let operationID)):
                sessionOperation = .searchLanguage
                saveUnconfirmed = true
                showError(.unconfirmed(operationID: operationID))
            case .failure(let failure):
                showError(failure)
            }
        }
    }

    private func requestDeleteRecent(_ term: SearchTerm) {
        guard !locked else { return }
        show(.deleteSearchTerm(term))
    }

    /// Runs only from the confirmation, once per confirmation.
    private func performDeleteRecent(_ term: SearchTerm) {
        guard EditorDismissPolicy.canDelete(isBusy: model.isBusy, hasPendingSave: hasPendingSave,
                                            deleteInFlight: deleteInFlight) else { return }
        deleteInFlight = true
        model.deleteSearchTerm(id: term.id) { result in
            deleteInFlight = false
            switch result {
            case .success: break
            case .failure(.unconfirmed(let operationID)):
                sessionOperation = .searchHistoryDelete
                saveUnconfirmed = true
                showError(.unconfirmed(operationID: operationID))
            case .failure(let failure):
                showError(failure)
            }
        }
    }

    /// "Use name in manual entry" for a row that cannot be added directly.
    private func requestUseName(_ item: SearchResultItem) {
        guard !locked else { return }
        if search.hasSelection { show(.copyNameToManual(name: item.name)) } else { copyNameToManual(item.name) }
    }

    /// One transition: the search tab is left, only the name is carried over.
    private func copyNameToManual(_ name: String) {
        guard !locked else { return }
        search.invalidate()
        historyNotSaved = false
        let draft = AddSheetPolicy.manualDraft(copyingName: name)
        self.name = draft.name
        protein = draft.protein
        saveAsFavorite = draft.saveAsFavorite
        tab = .manual
    }

    private var searchTotal: Int64? { search.totalCentigrams }
    private var canAddSearch: Bool {
        AddSheetPolicy.canAddSelection(locked: locked, selectionCount: search.selected.count, totalCentigrams: searchTotal)
    }

    private var searchSelectionBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(RenewalStrings.format("renewal_favorite_selected_summary", search.selected.count,
                                       searchTotal.map { ProteinInput.format(centigrams: $0, decimalSeparator: model.decimalSeparator) }
                                       ?? RenewalStrings.text("renewal_total_error")))
                .font(.subheadline).monospacedDigit()
                .accessibilityIdentifier("renewal.search.summary")
            Button { addSearchSelected() } label: {
                Text(RenewalStrings.format("renewal_search_add_count", search.selected.count)).font(.headline)
            }
            .buttonStyle(RenewalPrimaryButtonStyle())
            .disabled(!canAddSearch)
            .accessibilityIdentifier("renewal.search.addSelected")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, RenewalTheme.pageInset)
        .padding(.vertical, 12)
        .background(RenewalTheme.canvas)
    }

    /// Writes the confirmed snapshot (name, verified protein, reference
    /// amount) with the session's record IDs; no provider is consulted again.
    private func addSearchSelected() {
        guard canAddSearch else { return }
        let batch = search.selections
        model.addSearchRecords(day: target.day, selections: batch) { result in
            switch result {
            case .success:
                dismiss()
            case .failure(.unconfirmed(let operationID)):
                sessionOperation = .searchBatch
                saveUnconfirmed = true
                showError(.unconfirmed(operationID: operationID))
            case .failure(let failure):
                showError(failure)
            }
        }
    }

    // MARK: Manual tab

    private var manualTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(RecordHomeView.longDate(target.day)).foregroundStyle(.secondary)
            TextField(RenewalStrings.text("renewal_name_placeholder"), text: $name)
                .renewalInput()
                .disabled(locked)
                .opacity(locked ? 0.5 : 1)
            TextField(RenewalStrings.text("renewal_protein_placeholder"), text: $protein)
                .renewalInput()
                .keyboardType(.decimalPad)
                .accessibilityLabel(Text("renewal_protein_placeholder"))
                .disabled(locked)
                .opacity(locked ? 0.5 : 1)
            Toggle(isOn: $saveAsFavorite) {
                Text("renewal_favorite_also_save").font(.subheadline)
            }
            .frame(minHeight: 44)
            .disabled(locked)
            .accessibilityIdentifier("renewal.add.favoriteToggle")
        }
        .renewalCard()
    }

    private func saveManual() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        model.addRecord(day: target.day, id: target.manualRecordID, name: trimmed.isEmpty ? nil : trimmed,
                        proteinText: protein, favoriteID: saveAsFavorite ? target.manualFavoriteID : nil) { result in
            switch result {
            case .success(.alreadyExisted):
                prompt = nil
                favoriteExistsNotice = true
            case .success:
                dismiss()
            case .failure(.unconfirmed(let operationID)):
                sessionOperation = .record
                saveUnconfirmed = true
                showError(.unconfirmed(operationID: operationID))
            case .failure(let failure):
                showError(failure)
            }
        }
    }

    // MARK: Favorites tab

    @ViewBuilder private var favoritesTab: some View {
        if let editing {
            favoriteEditor(editing)
        } else {
            Text(RenewalStrings.format("renewal_favorite_target_day", RecordHomeView.longDate(target.day)))
                .font(.subheadline).foregroundColor(RenewalTheme.secondary)
            if model.favorites.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "star").font(.title2).foregroundColor(RenewalTheme.action)
                    Text("renewal_favorite_empty").foregroundColor(RenewalTheme.secondary)
                }
                .frame(minHeight: 100)
                .renewalCard()
                .accessibilityIdentifier("renewal.favorite.empty")
            } else {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(model.favorites) { favorite in favoriteRow(favorite) }
                }
            }
        }
    }

    private func favoriteRow(_ favorite: FavoriteFood) -> some View {
        let isSelected = selected.contains(favorite.id)
        let displayName = Self.displayName(favorite)
        let amount = ProteinInput.format(centigrams: favorite.proteinCentigrams, decimalSeparator: model.decimalSeparator)
        let valid = FavoriteCollection.recordAmount(of: favorite) != nil
        return HStack(alignment: .center, spacing: 8) {
            // Selection area, edit and delete are three separate targets.
            Button { toggle(favorite) } label: {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundColor(isSelected ? RenewalTheme.action : RenewalTheme.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(displayName).font(.body.weight(.medium)).foregroundColor(RenewalTheme.ink)
                        Text(amount + " g").font(.subheadline).monospacedDigit()
                            .foregroundColor(valid ? RenewalTheme.secondary : RenewalTheme.danger)
                        if !valid {
                            Text("renewal_favorite_check_value").font(.footnote).foregroundColor(RenewalTheme.danger)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!AddSheetPolicy.canSelect(favorite, locked: locked))
            .accessibilityLabel(Text(RenewalStrings.format(isSelected ? "renewal_favorite_deselect" : "renewal_favorite_select", displayName)))
            .accessibilityValue(Text(valid ? amount + " g" : RenewalStrings.text("renewal_favorite_check_value")))
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            .accessibilityIdentifier("renewal.favorite.row.\(favorite.id)")
            Button { beginEdit(favorite) } label: {
                Image(systemName: "pencil").frame(width: 44, height: 44)
            }
            .disabled(locked)
            .accessibilityLabel(Text(RenewalStrings.format("renewal_favorite_edit", displayName)))
            .accessibilityIdentifier("renewal.favorite.edit.\(favorite.id)")
            Button { requestDelete(favorite) } label: {
                Image(systemName: "trash").frame(width: 44, height: 44)
            }
            .foregroundColor(RenewalTheme.danger)
            .disabled(locked)
            .accessibilityLabel(Text(RenewalStrings.format("renewal_favorite_delete_action", displayName)))
            .accessibilityIdentifier("renewal.favorite.delete.\(favorite.id)")
        }
        .opacity(locked ? 0.6 : 1)
        .renewalCard()
    }

    /// Whitespace-only names are shown as "Unnamed"; the stored value is untouched.
    static func displayName(_ favorite: FavoriteFood) -> String {
        let trimmed = favorite.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? RenewalStrings.text("renewal_favorite_unnamed") : favorite.name
    }

    private func toggle(_ favorite: FavoriteFood) {
        guard AddSheetPolicy.canSelect(favorite, locked: locked) else { return }
        if let index = selected.firstIndex(of: favorite.id) {
            selected.remove(at: index)
            snapshots[favorite.id] = nil
        } else {
            let recordID = AddSheetPolicy.recordID(for: favorite.id, in: &recordIDs) { UUID().uuidString }
            snapshots[favorite.id] = FavoriteSelection(favorite: favorite, recordID: recordID)
            selected.append(favorite.id)
        }
    }

    private var selectionBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(RenewalStrings.format("renewal_favorite_selected_summary", selected.count,
                                       totalCentigrams.map { ProteinInput.format(centigrams: $0, decimalSeparator: model.decimalSeparator) }
                                       ?? RenewalStrings.text("renewal_total_error")))
                .font(.subheadline).monospacedDigit()
                .accessibilityIdentifier("renewal.favorite.summary")
            Button { addSelected() } label: {
                Text(RenewalStrings.format("renewal_favorite_add_count", selected.count)).font(.headline)
            }
            .buttonStyle(RenewalPrimaryButtonStyle())
            .disabled(!canAdd)
            .accessibilityIdentifier("renewal.favorite.addSelected")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, RenewalTheme.pageInset)
        .padding(.vertical, 12)
        .background(RenewalTheme.canvas)
    }

    private func addSelected() {
        guard canAdd else { return }
        let batch = selections
        model.addFavoriteRecords(day: target.day, selections: batch) { result in
            switch result {
            case .success:
                dismiss()
            case .failure(.unconfirmed(let operationID)):
                sessionOperation = .favoriteBatch
                saveUnconfirmed = true
                showError(.unconfirmed(operationID: operationID))
            case .failure(.selectionChanged):
                // Nothing was written. Keep only the picks that still match
                // the list, so the user sees exactly what will be retried.
                pruneStaleSelections()
                showError(.selectionChanged)
            case .failure(let failure):
                showError(failure)
            }
        }
    }

    private func pruneStaleSelections() {
        selected = selected.filter { id in
            guard let snapshot = snapshots[id], let latest = model.favorites.first(where: { $0.id == id }) else { return false }
            return latest.name == snapshot.name && latest.proteinCentigrams == snapshot.proteinCentigrams
                && FavoriteCollection.recordAmount(of: latest) != nil
        }
        snapshots = snapshots.filter { selected.contains($0.key) }
    }

    // MARK: Favorite editing (in place)

    private func favoriteEditor(_ favorite: FavoriteFood) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("renewal_favorite_edit_title").font(.headline)
            TextField(RenewalStrings.text("renewal_favorite_name_placeholder"), text: $editName)
                .renewalInput()
                .disabled(locked)
                .opacity(locked ? 0.5 : 1)
                .accessibilityIdentifier("renewal.favorite.editName")
            TextField(RenewalStrings.text("renewal_protein_placeholder"), text: $editProtein)
                .renewalInput()
                .keyboardType(.decimalPad)
                .accessibilityLabel(Text("renewal_protein_placeholder"))
                .disabled(locked)
                .opacity(locked ? 0.5 : 1)
                .accessibilityIdentifier("renewal.favorite.editProtein")
            Text("renewal_favorite_edit_note").font(.footnote).foregroundColor(RenewalTheme.secondary)
            HStack(spacing: 12) {
                Button { cancelEdit() } label: { Text("renewal_cancel").frame(maxWidth: .infinity, minHeight: 44) }
                    .disabled(locked)
                    .accessibilityIdentifier("renewal.favorite.editCancel")
                Button { saveEdit(favorite) } label: { Text("renewal_save").frame(maxWidth: .infinity, minHeight: 44) }
                    .buttonStyle(RenewalPrimaryButtonStyle())
                    .disabled(locked)
                    .accessibilityIdentifier("renewal.favorite.editSave")
            }
        }
        .renewalCard()
    }

    private func beginEdit(_ favorite: FavoriteFood) {
        switch AddSheetPolicy.editDecision(isBusy: model.isBusy, hasPendingSave: hasPendingSave, selectionCount: selected.count) {
        case .blocked, .stay: break
        case .confirm: show(.discardSelection(favoriteID: favorite.id))
        case .switchNow: enterEdit(favorite)
        }
    }

    /// Shows the stored name and signed value verbatim; saving validates
    /// like a new entry.
    private func enterEdit(_ favorite: FavoriteFood) {
        selected = []
        snapshots = [:]
        editName = favorite.name
        editProtein = ProteinInput.format(centigrams: favorite.proteinCentigrams, decimalSeparator: model.decimalSeparator)
        editInitial = [editName, editProtein]
        editing = favorite
    }

    /// Not while a save of these values is running or unconfirmed: the
    /// reconfirm decides about them, and `.notApplied` must find them intact.
    private func cancelEdit() {
        guard !locked else { return }
        if editorDirty { show(.discardEdit) } else { editing = nil }
    }

    private func saveEdit(_ favorite: FavoriteFood) {
        model.updateFavorite(id: favorite.id, name: editName, proteinText: editProtein) { result in
            switch result {
            case .success:
                editing = nil
            case .failure(.unconfirmed(let operationID)):
                sessionOperation = .favoriteEdit
                saveUnconfirmed = true
                showError(.unconfirmed(operationID: operationID))
            case .failure(let failure):
                showError(failure)
            }
        }
    }

    // MARK: Favorite deletion

    private func requestDelete(_ favorite: FavoriteFood) {
        guard !locked else { return }
        show(.deleteFavorite(favorite))
    }

    /// Runs only from the delete confirmation, once per confirmation.
    private func performDelete(_ favorite: FavoriteFood) {
        guard EditorDismissPolicy.canDelete(isBusy: model.isBusy, hasPendingSave: hasPendingSave,
                                            deleteInFlight: deleteInFlight) else { return }
        deleteInFlight = true
        model.deleteFavorite(id: favorite.id) { result in
            deleteInFlight = false
            switch result {
            case .success:
                selected.removeAll { $0 == favorite.id }
                snapshots[favorite.id] = nil
            case .failure(.unconfirmed(let operationID)):
                sessionOperation = .favoriteDelete
                saveUnconfirmed = true
                showError(.unconfirmed(operationID: operationID))
            case .failure(let failure):
                showError(failure)
            }
        }
    }

    // MARK: Pending outcome, by operation

    /// A confirmed outcome means something different per operation: a record
    /// save closes the sheet, an edit returns to the list, a delete stays.
    private func confirmedPending() {
        saveUnconfirmed = false
        switch AddSheetPolicy.afterConfirmed(sessionOperation) {
        case .close:
            dismiss()
        case .leaveEdit:
            editing = nil
        case .stay:
            // A confirmed delete may have removed a selected favorite.
            pruneStaleSelections()
            // A confirmed language change takes effect now: results and
            // selection of the old language are dropped, the draft stays.
            // A confirmed history write or delete changes nothing here: no
            // re-search, no second write.
            if sessionOperation == .searchLanguage { search.applyLanguage(model.searchLanguage.resolved) }
        }
        sessionOperation = nil
    }

    // MARK: Closing and prompts

    private func requestClose() {
        let decision = closeDecision
        if decision == .close { return dismiss() }
        switch EditorDismissPolicy.prompt(for: decision) {
        case .discard: show(.discard)
        case .pendingClose: show(.pendingClose)
        case .delete, nil: break
        }
    }

    private func show(_ next: AddSheetPrompt) {
        guard error == nil, prompt == nil, !favoriteExistsNotice else { return }
        prompt = next
    }

    private func showError(_ failure: RecordHomeViewModel.ActionError) {
        prompt = nil
        error = failure
    }

    private func confirm(_ confirmed: AddSheetPrompt) {
        switch confirmed {
        case .discard, .pendingClose:
            let editorPrompt: EditorPrompt = confirmed == .discard ? .discard : .pendingClose
            switch EditorDismissPolicy.resolve(confirmed: editorPrompt, isBusy: model.isBusy,
                                               hasPendingSave: hasPendingSave, isDirty: currentTabDirty) {
            case .close: dismiss()
            case .blocked: break
            case .confirmDiscard, .confirmPendingClose:
                DispatchQueue.main.async { requestClose() }
            }
        case .switchTab(let value):
            guard !locked else { return }
            applySwitch(to: value)
        case .discardSelection(let favoriteID):
            guard !locked, let favorite = model.favorites.first(where: { $0.id == favoriteID }) else { return }
            enterEdit(favorite)
        case .deleteFavorite(let favorite):
            // After the alert has closed, so a following error alert is shown.
            DispatchQueue.main.async { performDelete(favorite) }
        case .discardEdit:
            guard !locked else { return }
            editing = nil
        case .discardSearch(let reason):
            // Agreeing drops the selection only through the action itself: a
            // language change keeps it until the new language is confirmed.
            DispatchQueue.main.async { performSearchAction(reason) }
        case .deleteSearchTerm(let term):
            DispatchQueue.main.async { performDeleteRecent(term) }
        case .copyNameToManual(let name):
            copyNameToManual(name)
        }
    }
}

// MARK: - Prompt presentation

@available(iOS 15.0, *)
extension View {
    func addSheetPromptAlert(_ prompt: Binding<AddSheetPrompt?>, decimalSeparator: String,
                             onConfirm: @escaping (AddSheetPrompt) -> Void) -> some View {
        alert(
            Text(prompt.wrappedValue.map(AddSheetPromptText.title) ?? ""),
            isPresented: Binding(get: { prompt.wrappedValue != nil }, set: { if !$0 { prompt.wrappedValue = nil } }),
            presenting: prompt.wrappedValue
        ) { current in
            Button(role: .cancel) {} label: { Text(AddSheetPromptText.keep(current)) }
            Button(role: AddSheetPromptText.isDestructive(current) ? .destructive : nil) { onConfirm(current) } label: {
                Text(AddSheetPromptText.confirm(current))
            }
        } message: { current in
            Text(AddSheetPromptText.message(current, decimalSeparator: decimalSeparator))
        }
    }
}

@available(iOS 15.0, *)
enum AddSheetPromptText {
    static func title(_ prompt: AddSheetPrompt) -> String {
        switch prompt {
        case .discard, .discardEdit: return RenewalStrings.text("renewal_discard_title")
        case .pendingClose: return RenewalStrings.text("renewal_pending_close_title")
        case .switchTab: return RenewalStrings.text("renewal_switch_tab_title")
        case .discardSelection: return RenewalStrings.text("renewal_favorite_discard_selection_title")
        case .deleteFavorite: return RenewalStrings.text("renewal_favorite_delete_title")
        case .discardSearch: return RenewalStrings.text("renewal_search_discard_title")
        case .deleteSearchTerm: return RenewalStrings.text("renewal_search_delete_recent_title")
        case .copyNameToManual: return RenewalStrings.text("renewal_search_copy_name_title")
        }
    }

    static func message(_ prompt: AddSheetPrompt, decimalSeparator: String) -> String {
        switch prompt {
        case .discard, .discardEdit: return RenewalStrings.text("renewal_discard_message")
        case .pendingClose: return RenewalStrings.text("renewal_pending_close_message")
        case .switchTab: return RenewalStrings.text("renewal_switch_tab_message")
        case .discardSelection: return RenewalStrings.text("renewal_favorite_discard_selection_message")
        case .deleteFavorite(let favorite):
            // The stored entry, never an unsaved field value.
            let amount = ProteinInput.format(centigrams: favorite.proteinCentigrams, decimalSeparator: decimalSeparator)
            return AddSheet.displayName(favorite) + " · " + amount + " g\n"
                + RenewalStrings.text("renewal_favorite_delete_message")
        case .discardSearch(let reason):
            switch reason {
            case .newSearch(let query):
                return RenewalStrings.text(SearchSessionModel.normalized(query) == nil
                                           ? "renewal_search_discard_clear_message" : "renewal_search_discard_new_message")
            case .recentSearch: return RenewalStrings.text("renewal_search_discard_recent_message")
            case .languageChange: return RenewalStrings.text("renewal_search_discard_language_message")
            }
        case .deleteSearchTerm(let term):
            // The stored term, shown as the list shows it.
            let label = SearchSessionModel.normalized(term.value) ?? RenewalStrings.text("renewal_search_recent_blank")
            return RenewalStrings.format("renewal_search_delete_recent_message", label)
        case .copyNameToManual: return RenewalStrings.text("renewal_search_copy_name_message")
        }
    }

    static func keep(_ prompt: AddSheetPrompt) -> String {
        switch prompt {
        case .discard, .discardEdit: return RenewalStrings.text("renewal_discard_keep")
        case .pendingClose: return RenewalStrings.text("renewal_pending_close_stay")
        case .switchTab: return RenewalStrings.text("renewal_switch_tab_stay")
        case .discardSelection, .deleteFavorite, .discardSearch, .deleteSearchTerm, .copyNameToManual:
            return RenewalStrings.text("renewal_cancel")
        }
    }

    static func confirm(_ prompt: AddSheetPrompt) -> String {
        switch prompt {
        case .discard, .discardEdit: return RenewalStrings.text("renewal_discard_confirm")
        case .pendingClose: return RenewalStrings.text("renewal_pending_close_confirm")
        case .switchTab: return RenewalStrings.text("renewal_switch_tab_confirm")
        case .discardSelection: return RenewalStrings.text("renewal_favorite_discard_selection_confirm")
        case .deleteFavorite: return RenewalStrings.text("renewal_favorite_delete_confirm")
        case .discardSearch: return RenewalStrings.text("renewal_search_discard_confirm")
        case .deleteSearchTerm: return RenewalStrings.text("renewal_search_delete_recent_confirm")
        case .copyNameToManual: return RenewalStrings.text("renewal_search_copy_name_confirm")
        }
    }

    /// Losing input or a stored favorite is destructive; the unconfirmed
    /// close is deliberately neutral.
    static func isDestructive(_ prompt: AddSheetPrompt) -> Bool {
        if case .pendingClose = prompt { return false }
        return true
    }
}
