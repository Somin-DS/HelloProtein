import SwiftUI
import HelloProteinCore

/// Actions the search tab hands back to the add sheet, which owns every
/// confirmation and every write.
@available(iOS 15.0, *)
struct SearchTabActions {
    let search: (String) -> Void
    let recent: (SearchTerm) -> Void
    let deleteRecent: (SearchTerm) -> Void
    let pickLanguage: (SearchLanguage) -> Void
    let useName: (SearchResultItem) -> Void
}

/// The search tab's content: language, query, recent searches or results.
/// Pure presentation of `SearchSessionModel` and the view model's mirrors.
@available(iOS 15.0, *)
struct SearchTab: View {
    @ObservedObject var session: SearchSessionModel
    @ObservedObject var model: RecordHomeViewModel
    let targetDay: CalendarDay
    /// A write is running or unconfirmed: nothing may change.
    let locked: Bool
    /// The last executed search's term could not be recorded.
    let historyNotSaved: Bool
    let actions: SearchTabActions
    @FocusState private var queryFocused: Bool

    var body: some View {
        Text(RenewalStrings.format("renewal_search_target_day", RecordHomeView.longDate(targetDay)))
            .font(.subheadline).foregroundColor(RenewalTheme.secondary)
        languageCard
        queryCard
        if historyNotSaved {
            Text("renewal_search_history_not_saved").font(.footnote).foregroundColor(RenewalTheme.secondary)
                .accessibilityIdentifier("renewal.search.historyNotSaved")
        }
        switch session.status {
        case .idle: recentCard
        case .searching:
            HStack(spacing: 10) {
                ProgressView()
                Text("renewal_search_searching").foregroundColor(RenewalTheme.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .renewalCard()
            .accessibilityIdentifier("renewal.search.searching")
        case .results: resultsSection
        case .empty: emptyCard
        case .failed(let error): failureCard(error)
        case .unavailable: unavailableCard
        }
    }

    // MARK: Language

    private var languageCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("renewal_search_language").font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                languageButton(.korean, key: "renewal_search_language_korean")
                languageButton(.english, key: "renewal_search_language_english")
            }
        }
        .renewalCard()
    }

    private func languageButton(_ language: SearchLanguage, key: String) -> some View {
        let isCurrent = model.searchLanguage.resolved == language && !model.searchLanguage.isFallback
        return Button { actions.pickLanguage(language) } label: {
            Text(LocalizedStringKey(key))
                .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(isCurrent ? RenewalTheme.action.opacity(0.15) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(isCurrent ? RenewalTheme.action : RenewalTheme.secondary.opacity(0.4)))
        }
        .buttonStyle(.plain)
        .disabled(locked || session.isSearching)
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
        .accessibilityIdentifier("renewal.search.language.\(language.rawValue)")
    }

    // MARK: Query

    private var queryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField(RenewalStrings.text("renewal_search_placeholder"), text: $session.queryDraft)
                    .renewalInput()
                    .focused($queryFocused)
                    .submitLabel(.search)
                    .onSubmit { submit() }
                    .disabled(locked)
                    .opacity(locked ? 0.5 : 1)
                    .accessibilityIdentifier("renewal.search.query")
                if !session.queryDraft.isEmpty || session.executedQuery != nil {
                    // Back to the recent list: no history write, no request.
                    // Asks first when a selection would be lost.
                    Button { actions.search("") } label: {
                        Image(systemName: "xmark.circle.fill").font(.title3).frame(width: 44, height: 44)
                    }
                    .foregroundColor(RenewalTheme.secondary)
                    .disabled(locked || session.isSearching)
                    .accessibilityLabel(Text("renewal_search_clear"))
                    .accessibilityIdentifier("renewal.search.clear")
                }
            }
            Button { submit() } label: {
                Text("renewal_search_button").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(RenewalPrimaryButtonStyle())
            .disabled(locked || SearchSessionModel.normalized(session.queryDraft) == nil)
            .accessibilityIdentifier("renewal.search.run")
            if let executed = session.executedQuery {
                Text(RenewalStrings.format("renewal_search_results_for", executed)).font(.footnote).foregroundColor(RenewalTheme.secondary)
                    .accessibilityIdentifier("renewal.search.executed")
                Text(RenewalStrings.format("renewal_search_results_language", languageName(session.language)))
                    .font(.footnote).foregroundColor(RenewalTheme.secondary)
            }
        }
        .renewalCard()
    }

    private func submit() {
        guard !locked, let query = SearchSessionModel.normalized(session.queryDraft) else { return }
        queryFocused = false
        actions.search(query)
    }

    private func languageName(_ language: SearchLanguage) -> String {
        RenewalStrings.text(language == .korean ? "renewal_search_language_korean" : "renewal_search_language_english")
    }

    // MARK: Recent searches

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("renewal_search_recent").font(.subheadline.weight(.semibold)).accessibilityAddTraits(.isHeader)
            if model.searchHistory.isEmpty {
                Text("renewal_search_recent_empty").foregroundColor(RenewalTheme.secondary)
                    .accessibilityIdentifier("renewal.search.recent.empty")
            } else {
                ForEach(model.searchHistory) { term in recentRow(term) }
            }
        }
        .renewalCard()
    }

    private func recentRow(_ term: SearchTerm) -> some View {
        let normalized = SearchSessionModel.normalized(term.value)
        let label = normalized ?? RenewalStrings.text("renewal_search_recent_blank")
        return HStack(spacing: 8) {
            Button { actions.recent(term) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath").foregroundColor(RenewalTheme.secondary)
                    Text(label).foregroundColor(normalized == nil ? RenewalTheme.secondary : RenewalTheme.ink)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(locked || normalized == nil)
            .accessibilityLabel(Text(RenewalStrings.format("renewal_search_recent_action", label)))
            .accessibilityIdentifier("renewal.search.recent.\(term.id)")
            Button { actions.deleteRecent(term) } label: {
                Image(systemName: "xmark").frame(width: 44, height: 44)
            }
            .foregroundColor(RenewalTheme.secondary)
            .disabled(locked)
            .accessibilityLabel(Text(RenewalStrings.format("renewal_search_delete_recent_action", label)))
            .accessibilityIdentifier("renewal.search.recentDelete.\(term.id)")
        }
    }

    // MARK: Results

    @ViewBuilder private var resultsSection: some View {
        if !session.droppedSelectionIDs.isEmpty {
            Text("renewal_search_dropped").font(.footnote).foregroundColor(RenewalTheme.danger)
        }
        LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(session.results) { item in resultRow(item) }
        }
        if session.nextPage != nil {
            if let pageError = session.pageError {
                Text(Self.message(for: pageError, more: true)).font(.footnote).foregroundColor(RenewalTheme.danger)
            }
            Button { session.loadMore() } label: {
                Text("renewal_search_more").frame(maxWidth: .infinity, minHeight: 44)
            }
            .disabled(locked || session.isLoadingMore)
            .accessibilityIdentifier("renewal.search.more")
        }
    }

    private func resultRow(_ item: SearchResultItem) -> some View {
        let isSelected = session.isSelected(item)
        let amount = item.proteinCentigrams.map { ProteinInput.format(centigrams: $0, decimalSeparator: model.decimalSeparator) }
        let referenceText = item.reference.map { QuantityText.amount($0.quantity) }
        let detail: String = {
            if let amount, let referenceText { return RenewalStrings.format("renewal_search_reference", amount, referenceText) }
            return item.rawProtein + " g"
        }()
        let note = item.unavailability.map(Self.unavailabilityKey).map(RenewalStrings.text)
        return VStack(alignment: .leading, spacing: 8) {
            Button { session.toggle(item) } label: {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundColor(item.isSelectable ? (isSelected ? RenewalTheme.action : RenewalTheme.secondary) : RenewalTheme.secondary.opacity(0.4))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name).font(.body.weight(.medium)).foregroundColor(RenewalTheme.ink)
                            .multilineTextAlignment(.leading)
                        Text(detail).font(.subheadline).monospacedDigit()
                            .foregroundColor(item.isSelectable ? RenewalTheme.secondary : RenewalTheme.danger)
                        if item.isSelectable {
                            Text("renewal_search_adds_shown").font(.caption).foregroundColor(RenewalTheme.secondary)
                        }
                        if item.rounded {
                            Text("renewal_search_rounded").font(.caption).foregroundColor(RenewalTheme.secondary)
                        }
                        Text(LocalizedStringKey(item.sourceKey)).font(.caption).foregroundColor(RenewalTheme.secondary)
                        if let note {
                            Text(note).font(.footnote).foregroundColor(RenewalTheme.danger)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(locked || !item.isSelectable)
            .accessibilityLabel(Text(RenewalStrings.format(isSelected ? "renewal_favorite_deselect" : "renewal_favorite_select", item.name)))
            .accessibilityValue(Text([detail,
                                      item.isSelectable ? RenewalStrings.text("renewal_search_adds_shown") : nil,
                                      item.rounded ? RenewalStrings.text("renewal_search_rounded") : nil,
                                      RenewalStrings.text(item.sourceKey),
                                      note].compactMap { $0 }.joined(separator: ", ")))
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            .accessibilityIdentifier("renewal.search.result.\(item.itemID)")
            if !item.isSelectable {
                Button { actions.useName(item) } label: {
                    Text("renewal_search_use_name").font(.subheadline).frame(minHeight: 44)
                }
                .disabled(locked)
                .accessibilityLabel(Text(RenewalStrings.format("renewal_search_use_name_action", item.name)))
                .accessibilityIdentifier("renewal.search.useName.\(item.itemID)")
            }
        }
        .opacity(locked ? 0.6 : 1)
        .renewalCard()
    }

    static func unavailabilityKey(_ reason: SearchItemUnavailability) -> String {
        switch reason {
        case .unknownReference: return "renewal_search_unknown_reference"
        case .invalidProtein: return "renewal_search_invalid_protein"
        case .negativeProtein: return "renewal_search_negative_protein"
        case .proteinOutOfRange: return "renewal_search_protein_out_of_range"
        case .zeroProtein: return "renewal_search_zero_protein"
        }
    }

    // MARK: States

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "magnifyingglass").font(.title2).foregroundColor(RenewalTheme.action)
            Text("renewal_search_empty").foregroundColor(RenewalTheme.secondary)
                .accessibilityIdentifier("renewal.search.empty")
            Text("renewal_search_empty_hint").font(.footnote).foregroundColor(RenewalTheme.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
        .renewalCard()
    }

    private func failureCard(_ error: SearchProviderError) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "exclamationmark.triangle").font(.title2).foregroundColor(RenewalTheme.danger)
            Text(Self.message(for: error, more: false)).foregroundColor(RenewalTheme.ink)
                .accessibilityIdentifier("renewal.search.failed")
            Button { session.retry() } label: {
                Text("renewal_search_retry").frame(minHeight: 44)
            }
            .disabled(locked)
            .accessibilityIdentifier("renewal.search.retry")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .renewalCard()
    }

    private var unavailableCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "wifi.slash").font(.title2).foregroundColor(RenewalTheme.secondary)
            Text("renewal_search_unavailable").foregroundColor(RenewalTheme.ink)
                .accessibilityIdentifier("renewal.search.unavailable")
            if session.language == .korean {
                Text("renewal_search_unavailable_korean").font(.footnote).foregroundColor(RenewalTheme.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .renewalCard()
    }

    /// A local catalog failure is not a network failure, and a further-page
    /// failure keeps what is shown.
    static func message(for error: SearchProviderError, more: Bool) -> String {
        switch error {
        case .localData: return RenewalStrings.text("renewal_search_local_failed")
        case .notConfigured: return RenewalStrings.text("renewal_search_unavailable")
        case .network, .timeout, .invalidResponse, .service, .cancelled:
            return RenewalStrings.text(more ? "renewal_search_more_failed" : "renewal_search_failed")
        }
    }
}
