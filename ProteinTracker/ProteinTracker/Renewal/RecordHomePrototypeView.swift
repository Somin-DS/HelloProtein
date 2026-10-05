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
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    DayStrip(days: model.visibleDays, selected: model.selectedDay, today: model.today,
                             recordedDays: recordedDays, onSelect: model.select, onShift: model.shift)
                    if model.pendingSave != nil { pendingBanner }
                    DaySummary(total: model.totalCentigrams, goalState: model.goalState,
                               decimalSeparator: model.decimalSeparator)
                    if model.log.hasLegacyTotal {
                        LegacyTotalDisclosure(log: model.log, total: model.totalCentigrams,
                                              decimalSeparator: model.decimalSeparator,
                                              canEdit: model.totalCentigrams != nil && model.pendingSave == nil) {
                            legacyTotalTarget = LegacyTotalTarget(day: model.selectedDay, currentTotal: model.totalCentigrams)
                        }
                        .id(model.selectedDay)
                    }
                    recordList
                }
                .padding(RenewalTheme.pageInset)
            }
            .background(RenewalTheme.canvas)
            .navigationTitle(Text("renewal_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { model.selectToday() } label: { Text("renewal_today").frame(minWidth: 44, minHeight: 44) }
                        .disabled(model.selectedDay == model.today)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingDatePicker = true } label: {
                        Image(systemName: "calendar").frame(width: 44, height: 44)
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
                }
                .buttonStyle(RenewalPrimaryButtonStyle())
                .disabled(model.pendingSave != nil)
                .accessibilityLabel(Text(RenewalStrings.format("renewal_add_on_date", Self.longDate(model.selectedDay))))
                .accessibilityIdentifier("renewal.add")
                .padding(.horizontal, RenewalTheme.pageInset)
                .padding(.vertical, 12)
                .background(RenewalTheme.canvas)
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
        .tint(RenewalTheme.action)
        .preferredColorScheme(.light)
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
            } label: { Text("renewal_reconfirm").font(.subheadline.weight(.semibold)).frame(minHeight: 44) }
            .disabled(model.isBusy)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RenewalTheme.warning)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }

    private var recordedDays: Set<CalendarDay> {
        Set(model.visibleDays.filter { day in
            guard let log = model.state.log(for: day) else { return false }
            return log.hasLegacyTotal || !log.records.isEmpty
        })
    }

    private var recordList: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            Text("renewal_food_entries").font(.headline).accessibilityAddTraits(.isHeader)
            if model.log.records.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "fork.knife").font(.title2).foregroundColor(RenewalTheme.action)
                    Text(LocalizedStringKey(model.log.detailState == .legacyTotalOnly ? "renewal_legacy_add_hint" :
                                            (model.selectedDay == model.today ? "renewal_empty" : "renewal_empty_past")))
                        .foregroundColor(RenewalTheme.secondary)
                }
                .frame(minHeight: 100)
                .renewalCard()
            } else {
                ForEach(model.log.records) { record in
                    Button {
                        editorTarget = EditorTarget(day: model.selectedDay, record: record)
                    } label: {
                        FoodRow(record: record, decimalSeparator: model.decimalSeparator)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("renewal_edit"))
                    .disabled(model.pendingSave != nil)
                    .opacity(model.pendingSave == nil ? 1 : 0.45)
                }
            }
        }
    }

    // MARK: Formatting

    static func longDate(_ day: CalendarDay) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateStyle = .long
        guard let date = day.startOfDay(in: formatter.timeZone) else { return day.iso8601 }
        return formatter.string(from: date)
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
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(RecordHomeView.longDate(target.day)).foregroundStyle(.secondary)
                        // Input is locked while a save is running or unconfirmed:
                        // the reconfirm decides about the values that were sent,
                        // so an edit typed in the meantime would be lost with the
                        // sheet. The fields unlock again on `.notApplied`.
                        TextField(RenewalStrings.text("renewal_name_placeholder"), text: $name)
                            .renewalInput()
                            .disabled(model.isBusy || saveUnconfirmed)
                            .opacity(model.isBusy || saveUnconfirmed ? 0.5 : 1)
                        TextField(RenewalStrings.text("renewal_protein_placeholder"), text: $protein)
                            .renewalInput()
                            .keyboardType(.decimalPad)
                            .accessibilityLabel(Text("renewal_protein_placeholder"))
                            .disabled(model.isBusy || saveUnconfirmed)
                            .opacity(model.isBusy || saveUnconfirmed ? 0.5 : 1)
                    }
                    .renewalCard()
                    if saveUnconfirmed {
                        PendingSaveSection(model: model, onConfirmed: { dismiss() }, onNotApplied: {
                            saveUnconfirmed = false
                            error = .notApplied
                        }, onError: { error = $0 })
                    }
                    if target.record != nil {
                        Button(role: .destructive) { delete() } label: {
                            Text("renewal_delete").frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .foregroundColor(RenewalTheme.danger)
                        .disabled(model.isBusy || saveUnconfirmed)
                        .opacity(model.isBusy || saveUnconfirmed ? 0.5 : 1)
                    }
                }
                .padding(RenewalTheme.pageInset)
            }
            .background(RenewalTheme.canvas)
            .navigationTitle(Text(LocalizedStringKey(target.record == nil ? "renewal_add" : "renewal_edit")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Cancel is unavailable while a save is running so the sheet
                    // cannot close with a write still in flight behind it.
                    Button { dismiss() } label: { Text("renewal_cancel").frame(minWidth: 44, minHeight: 44) }
                        .disabled(model.isBusy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: { Text("renewal_save").frame(minWidth: 44, minHeight: 44) }
                        .disabled(model.isBusy || saveUnconfirmed)
                        .opacity(model.isBusy || saveUnconfirmed ? 0.5 : 1)
                }
            }
            .interactiveDismissDisabled(model.isBusy)
            .actionErrorAlert($error)
        }
        .navigationViewStyle(.stack)
        .tint(RenewalTheme.action)
        .preferredColorScheme(.light)
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
        VStack(alignment: .leading, spacing: 12) {
            Label { Text("renewal_pending_sheet") } icon: { Image(systemName: "exclamationmark.triangle") }
                .font(.subheadline)
            Text("renewal_pending_close_notice").font(.footnote)
            Button {
                model.reconfirm { result in
                    switch result {
                    case .success: onConfirmed()
                    case .failure(.notApplied): onNotApplied()
                    case .failure(let failure): onError(failure)
                    }
                }
            } label: { Text("renewal_reconfirm").frame(minHeight: 44) }
            .disabled(model.isBusy)
        }
        .padding(16)
        .background(RenewalTheme.warning)
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(RecordHomeView.longDate(target.day)).foregroundStyle(.secondary)
                        TextField(RenewalStrings.text("renewal_total_placeholder"), text: $total)
                            .renewalInput()
                            .keyboardType(.decimalPad)
                            .accessibilityLabel(Text("renewal_total_placeholder"))
                            .disabled(model.isBusy || saveUnconfirmed)
                            .opacity(model.isBusy || saveUnconfirmed ? 0.5 : 1)
                        Text("renewal_edit_total_footer").font(.footnote).foregroundColor(RenewalTheme.secondary)
                    }
                    .renewalCard()
                    if saveUnconfirmed {
                        PendingSaveSection(model: model, onConfirmed: { dismiss() }, onNotApplied: {
                            saveUnconfirmed = false
                            error = .notApplied
                        }, onError: { error = $0 })
                    }
                }
                .padding(RenewalTheme.pageInset)
            }
            .background(RenewalTheme.canvas)
            .navigationTitle(Text("renewal_edit_total"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("renewal_cancel").frame(minWidth: 44, minHeight: 44) }
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
                    } label: { Text("renewal_save").frame(minWidth: 44, minHeight: 44) }
                    .disabled(model.isBusy || saveUnconfirmed)
                    .opacity(model.isBusy || saveUnconfirmed ? 0.5 : 1)
                }
            }
            .interactiveDismissDisabled(model.isBusy)
            .actionErrorAlert($error)
        }
        .navigationViewStyle(.stack)
        .tint(RenewalTheme.action)
        .preferredColorScheme(.light)
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
            .background(RenewalTheme.canvas)
            .navigationTitle(Text("renewal_pick_date"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("renewal_cancel").frame(minWidth: 44, minHeight: 44) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { onPick(date); dismiss() } label: { Text("renewal_done").frame(minWidth: 44, minHeight: 44) }
                }
            }
        }
        .navigationViewStyle(.stack)
        .tint(RenewalTheme.action)
        .preferredColorScheme(.light)
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
