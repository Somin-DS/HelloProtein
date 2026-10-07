import SwiftUI
import HelloProteinCore

/// Fixed at presentation time: the day the goal will apply from (today when
/// the sheet opened) and the goal ID every save attempt of this session uses.
@available(iOS 15.0, *)
struct GoalEditorTarget: Identifiable {
    let id = UUID()
    let day: CalendarDay
    let goalID = UUID().uuidString
}

/// Sets or changes the daily protein goal that applies from today. Earlier
/// days keep their goals; saving twice on one day replaces that day's entry.
/// The history below the input is read-only and shows the last confirmed
/// state, never an optimistic preview.
@available(iOS 15.0, *)
struct GoalEditorSheet: View {
    let target: GoalEditorTarget
    @ObservedObject var model: RecordHomeViewModel
    @Environment(\.dismiss) private var dismiss
    /// The day the goal applies from. It never moves by itself; the user
    /// updates it explicitly after a refused save.
    @State private var targetDay: CalendarDay
    @State private var text: String
    @State private var initial: [String]
    @State private var error: RecordHomeViewModel.ActionError?
    @State private var prompt: EditorPrompt?
    @State private var saveUnconfirmed = false
    @State private var historyExpanded = false

    init(target: GoalEditorTarget, model: RecordHomeViewModel) {
        self.target = target
        self.model = model
        _targetDay = State(initialValue: target.day)
        let text = Self.prefill(model: model, day: target.day)
        _text = State(initialValue: text)
        _initial = State(initialValue: [text])
    }

    /// The goal in effect on `day`, formatted; empty when there is none or
    /// the migrated value still needs review. Never an invented number.
    static func prefill(model: RecordHomeViewModel, day: CalendarDay) -> String {
        guard !model.goalReview.needsReview, let goal = try? model.goal(on: day) else { return "" }
        return ProteinInput.format(centigrams: goal.amount.centigrams, decimalSeparator: model.decimalSeparator)
    }

    // MARK: Derived state

    private var locked: Bool { model.isBusy || saveUnconfirmed }
    private var hasPendingSave: Bool { saveUnconfirmed || model.pendingSave != nil }
    private var isDirty: Bool { EditorDismissPolicy.isDirty(initial: initial, current: [text]) }
    private var closeDecision: EditorCloseDecision {
        EditorDismissPolicy.decision(isBusy: model.isBusy, hasPendingSave: hasPendingSave, isDirty: isDirty)
    }
    /// The clock moved past midnight since the sheet opened (or since the last
    /// explicit update). Nothing is saved until the user updates the day.
    private var isStale: Bool { targetDay != model.today }
    /// The goal in effect on `targetDay`; `.failure` when the history is
    /// unreadable, which the current card reports instead of "no goal yet".
    /// (`try?` would flatten the inner optional and hide the error.)
    private var currentGoalResult: Result<ProteinGoal?, Error> { Result { try model.goal(on: targetDay) } }
    private var currentGoal: ProteinGoal? { (try? currentGoalResult.get()) ?? nil }
    private var sameDayGoalExists: Bool { model.goals.contains { $0.effectiveFrom == targetDay } }
    private var parsed: ProteinAmount? { try? ProteinInput.parse(text, decimalSeparator: model.decimalSeparator) }
    /// Saving the value already in effect would only add a history entry; it
    /// is allowed only when the review flag still has to be cleared.
    private var isUnchangedValue: Bool {
        guard !model.goalReview.needsReview, let goal = currentGoal, let parsed else { return false }
        return goal.amount == parsed
    }
    private var canSave: Bool { !locked && !isUnchangedValue }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    currentCard
                    inputCard
                    if saveUnconfirmed {
                        PendingSaveSection(model: model, onConfirmed: { dismiss() }, onNotApplied: {
                            saveUnconfirmed = false
                            showError(.notApplied)
                        }, onError: { showError($0) })
                    }
                    historyCard
                }
                .padding(RenewalTheme.pageInset)
                .editorPromptAlert($prompt, deleteSummary: nil, onConfirm: confirm)
                .background(SheetDismissAdapter(shouldDismiss: { closeDecision == .close },
                                                onAttemptToDismiss: { requestClose() }))
            }
            .background(RenewalTheme.canvas)
            .navigationTitle(Text("renewal_goal_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { requestClose() } label: { Text("renewal_cancel").frame(minWidth: 44, minHeight: 44) }
                        .disabled(model.isBusy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: { Text("renewal_save").frame(minWidth: 44, minHeight: 44) }
                        .disabled(!canSave)
                        .opacity(canSave ? 1 : 0.5)
                        .accessibilityIdentifier("renewal.goal.save")
                }
            }
            .interactiveDismissDisabled(model.isBusy)
            .actionErrorAlert($error)
        }
        .navigationViewStyle(.stack)
        .tint(RenewalTheme.action)
        .preferredColorScheme(.light)
    }

    // MARK: Sections

    private var currentCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch currentGoalResult {
            case .success(.some(let goal)):
                Text(RenewalStrings.format("renewal_goal_current_value", format(goal.amount.centigrams)))
                    .font(.headline)
                    .accessibilityIdentifier("renewal.goal.current")
                Text(RenewalStrings.format("renewal_goal_applies_from", RecordHomeView.longDate(goal.effectiveFrom)))
                    .font(.subheadline).foregroundColor(RenewalTheme.secondary)
            case .success(.none):
                Text("renewal_goal_none_yet").font(.headline).accessibilityIdentifier("renewal.goal.current")
            case .failure(let error):
                Text(RenewalStrings.format("renewal_goal_error", String(describing: error)))
                    .font(.footnote).foregroundColor(RenewalTheme.danger)
            }
            if model.goalReview.needsReview {
                // The old value is shown verbatim as data, never interpreted.
                Label { Text(verbatim: reviewNotice) } icon: { Image(systemName: "exclamationmark.triangle") }
                    .font(.footnote).foregroundColor(RenewalTheme.ink)
                    .accessibilityIdentifier("renewal.goal.review")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .renewalCard()
    }

    private var reviewNotice: String {
        switch model.goalReview.raw {
        case nil: return RenewalStrings.text("renewal_goal_review_missing")
        case .some(let raw) where raw.isEmpty: return RenewalStrings.text("renewal_goal_review_empty")
        case .some(let raw): return RenewalStrings.format("renewal_goal_needs_review", raw)
        }
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("renewal_goal_placeholder").font(.subheadline.weight(.semibold))
            TextField(RenewalStrings.text("renewal_goal_placeholder"), text: $text)
                .renewalInput()
                .keyboardType(.decimalPad)
                .accessibilityLabel(Text("renewal_goal_placeholder"))
                .disabled(locked)
                .opacity(locked ? 0.5 : 1)
            Text(RenewalStrings.format("renewal_goal_applies_from", RecordHomeView.longDate(targetDay)))
                .font(.subheadline)
                .accessibilityIdentifier("renewal.goal.appliesFrom")
            if isStale {
                // The general "from today" copy would be wrong now: say what to do instead.
                Label { Text("renewal_goal_date_changed_message") } icon: { Image(systemName: "calendar.badge.exclamationmark") }
                    .font(.footnote).foregroundColor(RenewalTheme.ink)
                Button { updateStartDay() } label: {
                    Text("renewal_goal_update_date").font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                }
                .disabled(locked)
                .accessibilityIdentifier("renewal.goal.updateDate")
            } else {
                Text("renewal_goal_apply_note").font(.footnote).foregroundColor(RenewalTheme.secondary)
                if sameDayGoalExists {
                    Text("renewal_goal_replace_note").font(.footnote).foregroundColor(RenewalTheme.secondary)
                }
            }
        }
        .renewalCard()
    }

    private var historyCard: some View {
        DisclosureGroup(isExpanded: $historyExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                if model.goals.isEmpty {
                    Text("renewal_goal_history_empty").font(.subheadline).foregroundColor(RenewalTheme.secondary)
                } else {
                    let active = currentGoal
                    ForEach(model.goals.sorted { $0.effectiveFrom > $1.effectiveFrom }) { goal in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(RecordHomeView.longDate(goal.effectiveFrom)).font(.subheadline)
                                if goal.id == active?.id {
                                    Text("renewal_goal_current").font(.caption.weight(.semibold)).foregroundColor(RenewalTheme.action)
                                }
                            }
                            Spacer(minLength: 8)
                            Text(format(goal.amount.centigrams) + " g").font(.subheadline.weight(.medium)).monospacedDigit()
                        }
                        .frame(minHeight: 44)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("renewal.goal.history.\(goal.effectiveFrom.iso8601)")
                    }
                }
            }
            .padding(.top, 12)
        } label: {
            // The identifier sits on the label only: on the group it would
            // propagate to every row and hide the per-day row identifiers.
            Text("renewal_goal_history").font(.subheadline.weight(.semibold))
                .foregroundColor(RenewalTheme.ink)
                .frame(minHeight: 44)
                .accessibilityIdentifier("renewal.goal.history")
        }
        .padding(16)
        .background(RenewalTheme.chip)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func format(_ centigrams: Int64) -> String {
        ProteinInput.format(centigrams: centigrams, decimalSeparator: model.decimalSeparator)
    }

    // MARK: Closing (same contract as the record and total sheets)

    private func requestClose() {
        let decision = closeDecision
        if decision == .close { return dismiss() }
        if let next = EditorDismissPolicy.prompt(for: decision) { show(next) }
    }

    private func show(_ next: EditorPrompt) {
        guard error == nil, prompt == nil else { return }
        prompt = next
    }

    private func showError(_ failure: RecordHomeViewModel.ActionError) {
        prompt = nil
        error = failure
    }

    private func confirm(_ confirmed: EditorPrompt) {
        guard confirmed != .delete else { return }
        switch EditorDismissPolicy.resolve(confirmed: confirmed, isBusy: model.isBusy,
                                           hasPendingSave: hasPendingSave, isDirty: isDirty) {
        case .close: dismiss()
        case .blocked: break
        case .confirmDiscard, .confirmPendingClose:
            DispatchQueue.main.async { requestClose() }
        }
    }

    // MARK: Saving

    /// Only the session's start day moves; the input and its dirty baseline stay.
    private func updateStartDay() {
        guard !locked else { return }
        model.refreshToday()
        targetDay = model.today
    }

    private func save() {
        guard canSave else { return }
        model.setGoal(day: targetDay, id: target.goalID, proteinText: text) { result in
            switch result {
            case .success:
                dismiss()
            case .failure(.unconfirmed(let operationID)):
                saveUnconfirmed = true
                showError(.unconfirmed(operationID: operationID))
            case .failure(let failure):
                showError(failure)
            }
        }
    }
}
