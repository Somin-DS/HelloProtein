import SwiftUI
import HelloProteinCore

/// Read-only summary of the last 7 or 30 days, pushed from the home screen.
/// Everything shown is computed from the view model's confirmed state; the
/// screen never writes and never loads the file by itself. The end day is
/// fixed while the screen is open; "latest" moves it to today.
@available(iOS 15.0, *)
struct StatisticsView: View {
    @ObservedObject var model: RecordHomeViewModel
    /// The 7/30 choice outlives the screen for the session (owned by home).
    @Binding var length: StatisticsPeriod.Length
    /// Picks a day on the home screen; the caller closes this screen.
    let onPickDay: (CalendarDay) -> Void
    @Environment(\.sizeCategory) private var sizeCategory
    @State private var period: StatisticsPeriod
    @State private var error: RecordHomeViewModel.ActionError?

    init(model: RecordHomeViewModel, length: Binding<StatisticsPeriod.Length>, onPickDay: @escaping (CalendarDay) -> Void) {
        _model = ObservedObject(wrappedValue: model)
        _length = length
        self.onPickDay = onPickDay
        _period = State(initialValue: StatisticsPeriod(endingAt: model.selectedDay, today: model.today,
                                                        length: length.wrappedValue))
    }

    private var today: CalendarDay { model.today }

    var body: some View {
        // Computed once per render from the confirmed state.
        let summary = model.statistics(for: period)
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                periodCard
                if model.pendingSave != nil { pendingBanner }
                summaryCard(summary)
                chartCard(summary)
                dayList(summary)
            }
            .padding(RenewalTheme.pageInset)
        }
        .background(RenewalTheme.canvas)
        .navigationTitle(Text("renewal_statistics"))
        .navigationBarTitleDisplayMode(.inline)
        .actionErrorAlert($error)
        .onChange(of: length) { newValue in period = period.withLength(newValue, today: today) }
    }

    // MARK: Period

    private var periodCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(StatisticsText.range(period)).font(.subheadline.weight(.semibold)).foregroundColor(RenewalTheme.ink)
                .accessibilityIdentifier("renewal.statistics.range")
            Picker("renewal_statistics_length", selection: $length) {
                Text("renewal_statistics_7").tag(StatisticsPeriod.Length.week)
                Text("renewal_statistics_30").tag(StatisticsPeriod.Length.month)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("renewal.statistics.length")
            HStack(spacing: 8) {
                navigationButton("renewal_statistics_previous", systemImage: "chevron.left", id: "renewal.statistics.previous",
                                 enabled: period.previous(today: today) != nil) {
                    if let previous = period.previous(today: today) { period = previous }
                }
                navigationButton("renewal_statistics_next", systemImage: "chevron.right", id: "renewal.statistics.next",
                                 enabled: period.next(today: today) != nil) {
                    if let next = period.next(today: today) { period = next }
                }
                Spacer(minLength: 0)
                Button { period = period.latest(today: today) } label: {
                    Text("renewal_statistics_latest").font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                }
                .disabled(period.end == today)
                .accessibilityIdentifier("renewal.statistics.latest")
            }
            if period.isTruncated {
                Text("renewal_statistics_truncated").font(.footnote).foregroundColor(RenewalTheme.secondary)
            }
        }
        .renewalCard()
    }

    private func navigationButton(_ key: String, systemImage: String, id: String, enabled: Bool,
                                  action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage).frame(width: 44, height: 44)
        }
        .disabled(!enabled)
        .accessibilityLabel(Text(LocalizedStringKey(key)))
        .accessibilityIdentifier(id)
    }

    // MARK: Unconfirmed save

    /// The numbers shown are the last confirmed ones. The action is the view
    /// model's reconfirm (a read), shown as "checking" only while it runs.
    private var pendingBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label { Text("renewal_statistics_pending") } icon: { Image(systemName: "exclamationmark.arrow.circlepath") }
                .font(.footnote)
            Button {
                model.reconfirm { result in
                    if case .failure(let failure) = result { error = failure }
                }
            } label: {
                Text(model.isBusy ? "renewal_statistics_confirming" : "renewal_reconfirm")
                    .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
            }
            .disabled(model.isBusy)
            .accessibilityIdentifier("renewal.reconfirm.statistics")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RenewalTheme.warning)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("renewal.statistics.pendingBanner")
    }

    // MARK: Summary

    @ViewBuilder private func summaryCard(_ summary: StatisticsSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let failure = summary.failure {
                Label { Text(StatisticsText.failure(failure)) } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                    .font(.footnote).foregroundColor(RenewalTheme.danger)
                    .accessibilityIdentifier("renewal.statistics.failure")
            }
            // Without a logged day both the total and the average are "—":
            // an empty period is not a recorded 0 g. A failed aggregate is "—" too.
            let aggregate = summary.aggregate.flatMap { $0.loggedDayCount > 0 ? $0 : nil }
            summaryRow("renewal_statistics_total", value: aggregate.map { format($0.totalCentigrams) + " g" },
                       id: "renewal.statistics.total")
            summaryRow("renewal_statistics_average", value: aggregate?.averageCentigrams.map { format($0) + " g" },
                       id: "renewal.statistics.average")
            summaryRow("renewal_statistics_days_logged_label",
                       value: RenewalStrings.format("renewal_statistics_days_logged", String(summary.loggedDays.count), String(summary.period.dayCount)),
                       id: "renewal.statistics.daysLogged")
            if summary.failure == nil, summary.loggedDays.isEmpty {
                Text("renewal_statistics_empty").font(.footnote).foregroundColor(RenewalTheme.secondary)
                    .accessibilityIdentifier("renewal.statistics.empty")
            }
            if summary.includesNegative {
                Label { Text("renewal_statistics_negative_note") } icon: { Image(systemName: "exclamationmark.triangle") }
                    .font(.footnote).foregroundColor(RenewalTheme.ink)
                    .accessibilityIdentifier("renewal.statistics.negativeNote")
            }
            if summary.includesLegacy {
                Text("renewal_statistics_legacy_note").font(.footnote).foregroundColor(RenewalTheme.secondary)
                    .accessibilityIdentifier("renewal.statistics.legacyNote")
            }
        }
        .renewalCard()
    }

    /// A summary line; a nil value shows "—" (the number could not be
    /// computed, or there is no logged day).
    private func summaryRow(_ key: String, value: String?, id: String) -> some View {
        let shown = value ?? "—"
        return Group {
            if sizeCategory.isAccessibilityCategory {
                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedStringKey(key)).font(.subheadline).foregroundColor(RenewalTheme.secondary)
                    Text(shown).font(.title3.weight(.semibold)).monospacedDigit().foregroundColor(RenewalTheme.ink)
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text(LocalizedStringKey(key)).font(.subheadline).foregroundColor(RenewalTheme.secondary)
                    Spacer(minLength: 8)
                    Text(shown).font(.title3.weight(.semibold)).monospacedDigit().foregroundColor(RenewalTheme.ink)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }

    // MARK: Chart (decorative; the list below carries every value)

    private func chartCard(_ summary: StatisticsSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("renewal_statistics_chart").font(.headline)
            StatisticsChart(days: summary.days, today: today, compact: period.length == .month)
                .frame(height: 180)
                // Axis labels have a fixed band; the list carries the values at any size.
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            Text("renewal_statistics_chart_note").font(.caption).foregroundColor(RenewalTheme.secondary)
        }
        .renewalCard()
        .accessibilityHidden(true)
    }

    // MARK: Day list

    private func dayList(_ summary: StatisticsSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("renewal_statistics_days").font(.headline).accessibilityAddTraits(.isHeader)
            ForEach(summary.days) { day in
                Button { onPickDay(day.day) } label: { dayRow(day) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(StatisticsText.rowAccessibility(day, today: today, decimalSeparator: model.decimalSeparator)))
                    .accessibilityHint(Text("renewal_statistics_day_hint"))
                    .accessibilityIdentifier("renewal.statistics.day.\(day.day.iso8601)")
            }
        }
    }

    private func dayRow(_ day: DayStatistic) -> some View {
        let value = StatisticsText.value(day, decimalSeparator: model.decimalSeparator)
        let detail = StatisticsText.detail(day, today: today, decimalSeparator: model.decimalSeparator)
        return Group {
            if sizeCategory.isAccessibilityCategory {
                VStack(alignment: .leading, spacing: 6) {
                    Text(StatisticsText.shortDate(day.day)).font(.body.weight(.medium)).foregroundColor(RenewalTheme.ink)
                    Text(value).font(.body.weight(.semibold)).monospacedDigit()
                        .foregroundColor(day.isLogged ? (day.isNegative ? RenewalTheme.danger : RenewalTheme.action) : RenewalTheme.secondary)
                    Text(detail).font(.caption).foregroundColor(RenewalTheme.secondary)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(StatisticsText.shortDate(day.day)).font(.body.weight(.medium)).foregroundColor(RenewalTheme.ink)
                        Text(detail).font(.caption).foregroundColor(RenewalTheme.secondary).multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Text(value).font(.body.weight(.semibold)).monospacedDigit()
                        .foregroundColor(day.isLogged ? (day.isNegative ? RenewalTheme.danger : RenewalTheme.action) : RenewalTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .renewalCard()
    }

    private func format(_ centigrams: Int64) -> String {
        ProteinInput.format(centigrams: centigrams, decimalSeparator: model.decimalSeparator)
    }
}

/// Bars per day with a per-day goal tick. Only coordinates are `Double`;
/// nothing here feeds a number back into the summary. Negative days are
/// drawn below the zero line and are never clamped; no entry is a hollow
/// marker, a recorded 0 g a flat solid line.
@available(iOS 15.0, *)
struct StatisticsChart: View {
    let days: [DayStatistic]
    let today: CalendarDay
    let compact: Bool

    private var hasNegative: Bool { days.contains { $0.isNegative } }
    /// The largest magnitude among totals and goals, at least 1 centigram.
    private var scale: UInt64 {
        var largest: UInt64 = 1
        for day in days {
            if let total = day.totalCentigrams { largest = max(largest, total.magnitude) }
            if case .goal(let goal) = day.goal { largest = max(largest, goal.centigrams.magnitude) }
        }
        return largest
    }

    var body: some View {
        GeometryReader { geometry in
            let labelHeight: CGFloat = compact ? 16 : 30
            let plotHeight = max(geometry.size.height - labelHeight - 4, 10)
            let zeroY = hasNegative ? plotHeight / 2 : plotHeight
            let unit = (hasNegative ? plotHeight / 2 : plotHeight) / CGFloat(Double(scale))
            let columnWidth = geometry.size.width / CGFloat(max(days.count, 1))
            let barWidth = max(min(columnWidth * (compact ? 0.55 : 0.5), 28), 3)
            ZStack(alignment: .topLeading) {
                Rectangle().fill(RenewalTheme.line).frame(height: 1).offset(y: zeroY)
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    let centerX = columnWidth * (CGFloat(index) + 0.5)
                    column(day, centerX: centerX, zeroY: zeroY, unit: unit, barWidth: barWidth, index: index)
                }
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    if let label = label(for: day.day, index: index) {
                        Text(label)
                            .font(.caption2).monospacedDigit()
                            .foregroundColor(day.day == today ? RenewalTheme.action : RenewalTheme.secondary)
                            .frame(width: columnWidth)
                            .multilineTextAlignment(.center)
                            .offset(x: columnWidth * CGFloat(index), y: plotHeight + 4)
                    }
                }
            }
        }
    }

    @ViewBuilder private func column(_ day: DayStatistic, centerX: CGFloat, zeroY: CGFloat, unit: CGFloat,
                                     barWidth: CGFloat, index: Int) -> some View {
        if let total = day.totalCentigrams {
            let height = CGFloat(Double(total.magnitude)) * unit
            if total == 0 {
                Rectangle().fill(RenewalTheme.action).frame(width: barWidth, height: 2)
                    .offset(x: centerX - barWidth / 2, y: zeroY - 2)
            } else if total > 0 {
                RoundedRectangle(cornerRadius: 3).fill(RenewalTheme.action).frame(width: barWidth, height: max(height, 2))
                    .offset(x: centerX - barWidth / 2, y: zeroY - max(height, 2))
            } else {
                RoundedRectangle(cornerRadius: 3).fill(RenewalTheme.danger).frame(width: barWidth, height: max(height, 2))
                    .offset(x: centerX - barWidth / 2, y: zeroY)
            }
        } else if day.isLogged {
            // Logged but unsummable: a solid warning marker, never read as "no entry" or 0.
            Image(systemName: "exclamationmark.triangle.fill").font(.caption2).foregroundColor(RenewalTheme.danger)
                .frame(width: barWidth + 6, height: 12)
                .offset(x: centerX - barWidth / 2 - 3, y: zeroY - 12)
        } else {
            RoundedRectangle(cornerRadius: 2)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                .foregroundColor(RenewalTheme.secondary)
                .frame(width: barWidth, height: 6)
                .offset(x: centerX - barWidth / 2, y: zeroY - 6)
        }
        if case .goal(let goal) = day.goal {
            let goalY = zeroY - CGFloat(Double(goal.centigrams.magnitude)) * unit
            Rectangle().fill(RenewalTheme.ink).frame(width: barWidth + 6, height: 2)
                .offset(x: centerX - barWidth / 2 - 3, y: goalY - 1)
        }
    }

    /// Every day in the 7-day chart; a few axis labels in the 30-day chart.
    private func label(for day: CalendarDay, index: Int) -> String? {
        if !compact { return RecordHomeView.weekdaySymbol(day) + "\n" + String(day.day) }
        guard index % 7 == 0 || index == days.count - 1 else { return nil }
        return String(day.day)
    }
}

/// Localized text for the statistics screen.
@available(iOS 15.0, *)
enum StatisticsText {
    static func range(_ period: StatisticsPeriod) -> String {
        RenewalStrings.format("renewal_statistics_range", RecordHomeView.longDate(period.start), RecordHomeView.longDate(period.end))
    }

    /// "Oct 14 (Wed)" in the current locale, for the day list. One formatter
    /// per locale; it follows locale changes (autoupdating locale).
    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.setLocalizedDateFormatFromTemplate("MMMdEEE")
        return formatter
    }()

    static func shortDate(_ day: CalendarDay) -> String {
        guard let date = day.startOfDay(in: TimeZone(secondsFromGMT: 0)!) else { return day.iso8601 }
        return shortDateFormatter.string(from: date)
    }

    static func value(_ day: DayStatistic, decimalSeparator: String) -> String {
        guard day.isLogged else { return RenewalStrings.text("renewal_statistics_no_entry") }
        guard let total = day.totalCentigrams else { return "—" }
        return ProteinInput.format(centigrams: total, decimalSeparator: decimalSeparator) + " g"
    }

    /// Goal, verdict and provenance of one day, in that order.
    static func detail(_ day: DayStatistic, today: CalendarDay, decimalSeparator: String) -> String {
        var parts: [String] = []
        switch day.goal {
        case .goal(let goal):
            parts.append(RenewalStrings.format("renewal_goal_progress", ProteinInput.format(centigrams: goal.centigrams, decimalSeparator: decimalSeparator)))
            switch day.comparison {
            case .reached: parts.append(RenewalStrings.text("renewal_goal_reached"))
            case .below: parts.append(RenewalStrings.text("renewal_statistics_below"))
            case .notApplicable: break
            }
            if day.isLogged, day.day == today, day.comparison != .notApplicable {
                parts.append(RenewalStrings.text("renewal_statistics_recording"))
            }
        case .noHistory: parts.append(RenewalStrings.text("renewal_statistics_goal_no_history"))
        case .notSet: parts.append(RenewalStrings.text("renewal_goal_not_set"))
        case .needsReview: parts.append(RenewalStrings.text("renewal_statistics_goal_review"))
        case .integrityError: parts.append(RenewalStrings.text("renewal_statistics_goal_error"))
        }
        if day.isLogged, day.totalCentigrams == nil { parts.append(RenewalStrings.text("renewal_total_error")) }
        if day.isNegative { parts.append(RenewalStrings.text("renewal_statistics_negative_day")) }
        if day.hasLegacy { parts.append(RenewalStrings.text("renewal_statistics_legacy_day")) }
        return parts.joined(separator: " · ")
    }

    static func rowAccessibility(_ day: DayStatistic, today: CalendarDay, decimalSeparator: String) -> String {
        [shortDate(day.day), value(day, decimalSeparator: decimalSeparator), detail(day, today: today, decimalSeparator: decimalSeparator)]
            .filter { !$0.isEmpty }.joined(separator: ", ")
    }

    static func failure(_ failure: StatisticsFailure) -> String {
        switch failure {
        case .arithmeticOverflow: return RenewalStrings.text("renewal_statistics_failure_overflow")
        case .dayTotalUnavailable(let day): return RenewalStrings.format("renewal_statistics_failure_day", shortDate(day))
        }
    }
}
