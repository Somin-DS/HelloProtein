import SwiftUI
import HelloProteinCore

@available(iOS 15.0, *)
struct RecordHomeView: View {
    @StateObject private var model: RecordHomeViewModel
    @State private var editorTarget: EditorTarget?
    @State private var legacyTotalTarget: LegacyTotalTarget?
    @State private var showingDatePicker = false
    @State private var homeError: RecordHomeViewModel.ActionError?
    @Environment(\.scenePhase) private var scenePhase

    init(model: RecordHomeViewModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                dayStrip
                if model.pendingSave != nil { pendingBanner }
                summary
                recordList
            }
            .navigationTitle(Text("renewal_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { model.selectToday() } label: { Text("renewal_today") }
                        .disabled(model.selectedDay == model.today)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingDatePicker = true } label: {
                        Image(systemName: "calendar")
                            .accessibilityLabel(Text("renewal_pick_date"))
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    editorTarget = EditorTarget(day: model.selectedDay, record: nil)
                } label: {
                    Label { Text("renewal_add") } icon: { Image(systemName: "plus") }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.pendingSave != nil)
                .padding(.horizontal, 24)
                .background(.ultraThinMaterial)
            }
            .actionErrorAlert($homeError)
            .sheet(item: $editorTarget) { target in
                RecordEditorSheet(target: target, model: model)
            }
            .sheet(item: $legacyTotalTarget) { target in
                LegacyTotalSheet(target: target, model: model)
            }
            .sheet(isPresented: $showingDatePicker) {
                DatePickerSheet(initial: model.selectedDay, timeZone: model.timeZone) { date in
                    model.select(date: date)
                }
            }
        }
        .navigationViewStyle(.stack)
        .onChange(of: scenePhase) { phase in
            if phase == .active { model.refreshToday() }
        }
    }

    // MARK: Unconfirmed save

    /// Shown while a save's outcome is unknown. No write is accepted until the
    /// store has been re-read; the user triggers that explicitly.
    private var pendingBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label { Text("renewal_pending_banner") } icon: { Image(systemName: "exclamationmark.arrow.circlepath") }
                .font(.footnote)
            Button {
                model.reconfirm { result in
                    // `.notApplied` is shown too: the entry the user typed was
                    // never stored and the banner is about to disappear.
                    if case .failure(let failure) = result { homeError = failure }
                }
            } label: { Text("renewal_reconfirm").font(.footnote.weight(.semibold)) }
            .disabled(model.isBusy)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.orange.opacity(0.15))
        .accessibilityElement(children: .contain)
    }

    // MARK: Day strip

    private var dayStrip: some View {
        HStack(spacing: 6) {
            Button { model.shift(days: -7) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel(Text("renewal_previous_week"))
            ForEach(model.visibleDays, id: \.self) { day in
                Button { model.select(day) } label: {
                    VStack(spacing: 4) {
                        Text(Self.weekdaySymbol(day))
                            .font(.caption2)
                        Text("\(day.day)")
                            .font(.subheadline.weight(.semibold))
                        Circle()
                            .fill(day == model.today ? Color.accentColor : Color.clear)
                            .frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .foregroundStyle(day == model.selectedDay ? .white : .primary)
                    .background(day == model.selectedDay ? Color.green : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityLabel(Text(Self.longDate(day)))
                .accessibilityAddTraits(day == model.selectedDay ? .isSelected : [])
            }
            Button { model.shift(days: 7) } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel(Text("renewal_next_week"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: Summary

    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Self.longDate(model.selectedDay))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let total = model.totalCentigrams {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(ProteinInput.format(centigrams: total, decimalSeparator: model.decimalSeparator))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text("g").font(.title3).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                goalView(total: total)
            } else {
                Label { Text("renewal_total_error") } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
            if model.log.hasLegacyTotal {
                legacySection
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color(.secondarySystemBackground))
    }

    @ViewBuilder
    private func goalView(total: Int64) -> some View {
        switch model.goalState {
        case .goal(let goal):
            let fraction = goal.centigrams > 0 ? Double(total) / Double(goal.centigrams) : 0
            ProgressView(value: min(max(fraction, 0), 1)).tint(.green)
            Text(RenewalStrings.format("renewal_goal_progress",
                                       ProteinInput.format(centigrams: goal.centigrams, decimalSeparator: model.decimalSeparator)))
                .font(.caption).foregroundStyle(.secondary)
        case .notSet:
            Text("renewal_goal_not_set").font(.caption).foregroundStyle(.secondary)
        case .noHistory:
            Text("renewal_goal_no_history").font(.caption).foregroundStyle(.secondary)
        case .needsReview(let raw):
            Text(RenewalStrings.format("renewal_goal_needs_review", raw ?? "")).font(.caption).foregroundStyle(.orange)
        case .integrityError(let detail):
            Text(RenewalStrings.format("renewal_goal_error", detail)).font(.caption).foregroundStyle(.red)
        }
    }

    private var legacySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("renewal_legacy_section").font(.caption.weight(.semibold))
            if let adjustment = model.log.legacyAdjustmentCentigrams {
                HStack {
                    Text(LocalizedStringKey(model.log.detailState == .legacyTotalOnly ? "renewal_legacy_total_label" : "renewal_legacy_adjustment"))
                        .font(.caption)
                    Spacer()
                    Text(signed(adjustment) + "g")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(adjustment < 0 ? .red : .primary)
                }
            }
            if let aggregate = model.log.legacyAggregate {
                Text(RenewalStrings.format("renewal_legacy_imported", format(aggregate.importedTotalCentigrams)))
                    .font(.caption2).foregroundStyle(.secondary)
                if let edited = aggregate.userEditedTotalCentigrams {
                    Text(RenewalStrings.format("renewal_legacy_user_edited", format(edited)))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            if model.log.detailState == .legacyTotalOnly {
                Text("renewal_legacy_total_only").font(.caption2).foregroundStyle(.secondary)
            }
            Button {
                legacyTotalTarget = LegacyTotalTarget(day: model.selectedDay, currentTotal: model.totalCentigrams)
            } label: {
                Text("renewal_edit_total").font(.caption.weight(.semibold))
            }
            .disabled(model.totalCentigrams == nil || model.pendingSave != nil)
        }
        .padding(.top, 6)
    }

    // MARK: Records

    private var recordList: some View {
        List {
            if model.log.records.isEmpty {
                Text(LocalizedStringKey(model.log.detailState == .legacyTotalOnly ? "renewal_legacy_add_hint" : "renewal_empty"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                ForEach(model.log.records) { record in
                    Button {
                        editorTarget = EditorTarget(day: model.selectedDay, record: record)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.name ?? RenewalStrings.text("renewal_manual_entry"))
                                    .foregroundStyle(.primary)
                                if record.source == .legacy {
                                    Text("renewal_legacy_entry").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(format(record.protein.centigrams) + "g")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .accessibilityHint(Text("renewal_edit"))
                    // No editor opens while a save is unconfirmed: its Save
                    // would only be refused with another operation's ID.
                    .disabled(model.pendingSave != nil)
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: Formatting

    private func format(_ centigrams: Int64) -> String {
        ProteinInput.format(centigrams: centigrams, decimalSeparator: model.decimalSeparator)
    }

    private func signed(_ centigrams: Int64) -> String {
        centigrams > 0 ? "+" + format(centigrams) : format(centigrams)
    }

    static func longDate(_ day: CalendarDay) -> String {
        "\(day.year).\(String(format: "%02d", day.month)).\(String(format: "%02d", day.day))"
    }

    static func weekdaySymbol(_ day: CalendarDay) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .autoupdatingCurrent
        return calendar.veryShortWeekdaySymbols[day.weekdayIndex - 1]
    }
}

// MARK: - Sheet targets (fixed at presentation time)

@available(iOS 15.0, *)
struct EditorTarget: Identifiable {
    let id = UUID()
    let day: CalendarDay
    let record: FoodRecord?
    /// Record ID used by every save attempt of this editing session, so a retry
    /// after a failed or unconfirmed save can never add a second record.
    let newRecordID = UUID().uuidString
}

@available(iOS 15.0, *)
struct LegacyTotalTarget: Identifiable {
    let id = UUID()
    let day: CalendarDay
    let currentTotal: Int64?
}

// MARK: - Editor

@available(iOS 15.0, *)
private struct RecordEditorSheet: View {
    let target: EditorTarget
    @ObservedObject var model: RecordHomeViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var protein: String
    @State private var error: RecordHomeViewModel.ActionError?
    /// Set when this sheet's own save ended unconfirmed; saving stays disabled
    /// until the store has been re-read.
    @State private var saveUnconfirmed = false

    init(target: EditorTarget, model: RecordHomeViewModel) {
        self.target = target
        self.model = model
        _name = State(initialValue: target.record?.name ?? "")
        _protein = State(initialValue: target.record.map {
            ProteinInput.format(centigrams: $0.protein.centigrams, decimalSeparator: model.decimalSeparator)
        } ?? "")
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Text(RecordHomeView.longDate(target.day)).foregroundStyle(.secondary)
                    TextField(RenewalStrings.text("renewal_name_placeholder"), text: $name)
                    TextField(RenewalStrings.text("renewal_protein_placeholder"), text: $protein)
                        .keyboardType(.decimalPad)
                        .accessibilityLabel(Text("renewal_protein_placeholder"))
                }
                if saveUnconfirmed {
                    PendingSaveSection(model: model, onConfirmed: { dismiss() }, onNotApplied: {
                        saveUnconfirmed = false
                        error = .notApplied
                    }, onError: { error = $0 })
                }
                if target.record != nil {
                    Section {
                        Button(role: .destructive) { delete() } label: { Text("renewal_delete") }
                            .disabled(model.isBusy || saveUnconfirmed)
                    }
                }
            }
            .navigationTitle(Text(LocalizedStringKey(target.record == nil ? "renewal_add" : "renewal_edit")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Cancel is unavailable while a save is running so the sheet
                    // cannot close with a write still in flight behind it.
                    Button { dismiss() } label: { Text("renewal_cancel") }
                        .disabled(model.isBusy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: { Text("renewal_save") }
                        .disabled(model.isBusy || saveUnconfirmed)
                }
            }
            .interactiveDismissDisabled(model.isBusy)
            .actionErrorAlert($error)
        }
    }

    private func handle(_ result: Result<Void, RecordHomeViewModel.ActionError>) {
        switch result {
        case .success:
            dismiss()
        case .failure(.unconfirmed(let operationID)):
            saveUnconfirmed = true
            error = .unconfirmed(operationID: operationID)
        case .failure(let failure):
            error = failure
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let record = target.record {
            model.updateRecord(day: target.day, id: record.id, name: trimmed.isEmpty ? nil : trimmed,
                               proteinText: protein, completion: handle)
        } else {
            model.addRecord(day: target.day, id: target.newRecordID, name: trimmed.isEmpty ? nil : trimmed,
                            proteinText: protein, completion: handle)
        }
    }

    private func delete() {
        guard let record = target.record else { return }
        model.deleteRecord(day: target.day, id: record.id, completion: handle)
    }
}

/// Form section offered while a save's outcome is unknown: explains the state
/// and lets the user re-read the store. It never retries the write by itself.
@available(iOS 15.0, *)
private struct PendingSaveSection: View {
    @ObservedObject var model: RecordHomeViewModel
    let onConfirmed: () -> Void
    let onNotApplied: () -> Void
    let onError: (RecordHomeViewModel.ActionError) -> Void

    var body: some View {
        Section {
            Text("renewal_pending_sheet").font(.footnote).foregroundStyle(.secondary)
            Button {
                model.reconfirm { result in
                    switch result {
                    case .success: onConfirmed()
                    case .failure(.notApplied): onNotApplied()
                    case .failure(let failure): onError(failure)
                    }
                }
            } label: { Text("renewal_reconfirm") }
            .disabled(model.isBusy)
        }
    }
}

@available(iOS 15.0, *)
private struct LegacyTotalSheet: View {
    let target: LegacyTotalTarget
    @ObservedObject var model: RecordHomeViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var total: String
    @State private var error: RecordHomeViewModel.ActionError?
    @State private var saveUnconfirmed = false

    init(target: LegacyTotalTarget, model: RecordHomeViewModel) {
        self.target = target
        self.model = model
        _total = State(initialValue: target.currentTotal.map {
            ProteinInput.format(centigrams: $0, decimalSeparator: model.decimalSeparator)
        } ?? "")
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Text(RecordHomeView.longDate(target.day)).foregroundStyle(.secondary)
                    TextField(RenewalStrings.text("renewal_total_placeholder"), text: $total)
                        .keyboardType(.decimalPad)
                        .accessibilityLabel(Text("renewal_total_placeholder"))
                } footer: {
                    Text("renewal_edit_total_footer")
                }
                if saveUnconfirmed {
                    PendingSaveSection(model: model, onConfirmed: { dismiss() }, onNotApplied: {
                        saveUnconfirmed = false
                        error = .notApplied
                    }, onError: { error = $0 })
                }
            }
            .navigationTitle(Text("renewal_edit_total"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("renewal_cancel") }
                        .disabled(model.isBusy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        model.setLegacyTotal(day: target.day, totalText: total) { result in
                            switch result {
                            case .success: dismiss()
                            case .failure(.unconfirmed(let operationID)):
                                saveUnconfirmed = true
                                error = .unconfirmed(operationID: operationID)
                            case .failure(let failure): error = failure
                            }
                        }
                    } label: { Text("renewal_save") }
                    .disabled(model.isBusy || saveUnconfirmed)
                }
            }
            .interactiveDismissDisabled(model.isBusy)
            .actionErrorAlert($error)
        }
    }
}

@available(iOS 15.0, *)
private struct DatePickerSheet: View {
    let initial: CalendarDay
    let timeZone: TimeZone
    let onPick: (Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date

    /// Bounds match `CalendarDay` (years 1...9999) so a pick can never be silently rejected.
    static func selectableRange(in timeZone: TimeZone) -> ClosedRange<Date> {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let lower = calendar.date(from: DateComponents(year: 1, month: 1, day: 1)) ?? .distantPast
        let upper = calendar.date(from: DateComponents(year: 9999, month: 12, day: 31)) ?? .distantFuture
        return lower...upper
    }

    init(initial: CalendarDay, timeZone: TimeZone, onPick: @escaping (Date) -> Void) {
        self.initial = initial
        self.timeZone = timeZone
        self.onPick = onPick
        _date = State(initialValue: initial.startOfDay(in: timeZone) ?? Date())
    }

    var body: some View {
        NavigationView {
            VStack {
                DatePicker("", selection: $date, in: Self.selectableRange(in: timeZone), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .environment(\.timeZone, timeZone)
                    .labelsHidden()
                Spacer()
            }
            .padding()
            .navigationTitle(Text("renewal_pick_date"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("renewal_cancel") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { onPick(date); dismiss() } label: { Text("renewal_done") }
                }
            }
        }
    }
}

// MARK: - Error presentation

@available(iOS 15.0, *)
extension View {
    func actionErrorAlert(_ error: Binding<RecordHomeViewModel.ActionError?>) -> some View {
        alert(
            Text(error.wrappedValue.map(ActionErrorText.title) ?? ""),
            isPresented: Binding(get: { error.wrappedValue != nil }, set: { if !$0 { error.wrappedValue = nil } })
        ) {
            Button { error.wrappedValue = nil } label: { Text("renewal_ok") }
        } message: {
            Text(error.wrappedValue.map(ActionErrorText.message) ?? "")
        }
    }
}

@available(iOS 15.0, *)
enum ActionErrorText {
    static func title(_ error: RecordHomeViewModel.ActionError) -> String {
        switch error {
        case .input: return RenewalStrings.text("renewal_error_input_title")
        case .storage: return RenewalStrings.text("renewal_error_storage_title")
        case .integrity, .notFound: return RenewalStrings.text("renewal_error_integrity_title")
        case .busy: return RenewalStrings.text("renewal_error_busy_title")
        case .unconfirmed: return RenewalStrings.text("renewal_error_unconfirmed_title")
        case .notApplied: return RenewalStrings.text("renewal_error_not_applied_title")
        }
    }

    static func message(_ error: RecordHomeViewModel.ActionError) -> String {
        switch error {
        case .input(let input):
            switch input {
            case .empty: return RenewalStrings.text("renewal_error_input_empty")
            case .notANumber: return RenewalStrings.text("renewal_error_input_number")
            case .groupingSeparatorNotAllowed: return RenewalStrings.text("renewal_error_input_grouping")
            case .tooManyFractionDigits: return RenewalStrings.text("renewal_error_input_fraction")
            case .notPositive: return RenewalStrings.text("renewal_error_input_positive")
            case .overflow: return RenewalStrings.text("renewal_error_input_overflow")
            }
        case .storage(let detail): return RenewalStrings.format("renewal_error_storage_message", detail)
        case .integrity(let detail): return RenewalStrings.format("renewal_error_integrity_message", detail)
        case .notFound: return RenewalStrings.text("renewal_error_not_found")
        case .busy: return RenewalStrings.text("renewal_error_busy")
        case .unconfirmed: return RenewalStrings.text("renewal_error_unconfirmed_message")
        case .notApplied: return RenewalStrings.text("renewal_error_not_applied_message")
        }
    }
}
