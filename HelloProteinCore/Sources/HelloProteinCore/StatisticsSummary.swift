import Foundation

/// A run of consecutive calendar days ending on `end`, never later than the
/// given "today". Built only with `CalendarDay.adding(days:)`; it is cut at
/// the start of the supported date range, in which case `days.count` is the
/// real day count M the summary divides by.
public struct StatisticsPeriod: Equatable, Sendable {
    public enum Length: Int, CaseIterable, Codable, Sendable {
        case week = 7
        case month = 30
    }

    public let length: Length
    /// Ascending, consecutive, `end` last; at most `length.rawValue` days.
    public let days: [CalendarDay]

    public var start: CalendarDay { days[0] }
    public var end: CalendarDay { days[days.count - 1] }
    public var dayCount: Int { days.count }
    /// True when the supported date range cut the period short.
    public var isTruncated: Bool { days.count < length.rawValue }

    /// The period ending on `min(anchor, today)`.
    public init(endingAt anchor: CalendarDay, today: CalendarDay, length: Length) {
        let end = min(anchor, today)
        var days = [end]
        while days.count < length.rawValue, let previous = days[days.count - 1].adding(days: -1) {
            days.append(previous)
        }
        self.length = length
        self.days = days.reversed()
    }

    public func contains(_ day: CalendarDay) -> Bool { start <= day && day <= end }

    /// The other length with the same end day.
    public func withLength(_ length: Length, today: CalendarDay) -> StatisticsPeriod {
        StatisticsPeriod(endingAt: end, today: today, length: length)
    }

    /// Moves back by the period length; nil when the supported range ends.
    public func previous(today: CalendarDay) -> StatisticsPeriod? {
        guard let end = end.adding(days: -length.rawValue) else { return nil }
        return StatisticsPeriod(endingAt: end, today: today, length: length)
    }

    /// Moves forward by the period length, never past today; nil when the
    /// period already ends today (or later, after a clock change backwards).
    public func next(today: CalendarDay) -> StatisticsPeriod? {
        guard end < today else { return nil }
        let shifted = end.adding(days: length.rawValue) ?? today
        return StatisticsPeriod(endingAt: min(shifted, today), today: today, length: length)
    }

    /// The period ending today with the same length.
    public func latest(today: CalendarDay) -> StatisticsPeriod {
        StatisticsPeriod(endingAt: today, today: today, length: length)
    }
}

/// What a day in the period holds, in the same terms as `DailyLog.detailState`.
public enum DayEntryState: String, Equatable, Sendable {
    /// No log, or an empty log without a legacy adjustment: not a logged day.
    case none
    case detailed
    case legacyOnly
    case legacyWithDetails
}

/// The goal in effect on one day, with the same priority as the home screen.
public enum DayGoal: Equatable, Sendable {
    case goal(ProteinAmount)
    /// Goal history exists but starts after this day.
    case noHistory
    case notSet
    /// No history and the migrated value is still under review.
    case needsReview
    case integrityError(String)
}

public enum GoalComparison: Equatable, Sendable {
    case reached
    case below
    /// No goal, no entry, a negative total or an unsummable day: no verdict.
    case notApplicable
}

public struct DayStatistic: Equatable, Sendable, Identifiable {
    public var id: CalendarDay { day }
    public let day: CalendarDay
    public let entry: DayEntryState
    /// The day's final signed total (`DailyLog.totalProteinCentigrams`), nil
    /// for a day without an entry or whose log could not be summed.
    public let totalCentigrams: Int64?
    public let goal: DayGoal

    public var isLogged: Bool { entry != .none }
    public var hasLegacy: Bool { entry == .legacyOnly || entry == .legacyWithDetails }
    public var isNegative: Bool { (totalCentigrams ?? 0) < 0 }
    /// A logged day with a goal and a non-negative total is compared; nothing else is.
    public var comparison: GoalComparison {
        guard let total = totalCentigrams, total >= 0, case .goal(let goal) = goal else { return .notApplicable }
        return total >= goal.centigrams ? .reached : .below
    }
}

public enum StatisticsFailure: Error, Equatable, Sendable {
    /// The checked sum of the logged days' totals does not fit.
    case arithmeticOverflow
    /// A logged day's own total could not be computed.
    case dayTotalUnavailable(CalendarDay)
}

/// The period's totals over logged days only. Never a partial or zeroed
/// replacement: when they cannot be computed the summary carries a failure
/// instead of an aggregate.
public struct StatisticsAggregate: Equatable, Sendable {
    public let loggedDayCount: Int
    /// Checked sum of the logged days' signed totals.
    public let totalCentigrams: Int64
    public let includesNegative: Bool
    public let includesLegacy: Bool

    /// Total over logged days, rounded half away from zero to a centigram;
    /// nil without a logged day. Display only; nothing is computed from it.
    public var averageCentigrams: Int64? {
        guard loggedDayCount > 0 else { return nil }
        return StatisticsAggregate.roundedAverage(sum: totalCentigrams, count: loggedDayCount)
    }

    /// Integer division with the signed half rounded away from zero; safe for
    /// `Int64.min` (no `abs`, no negation of the sum).
    public static func roundedAverage(sum: Int64, count: Int) -> Int64 {
        precondition(count > 0)
        let divisor = Int64(count)
        let quotient = sum / divisor
        let remainder = sum % divisor
        guard remainder.magnitude * 2 >= divisor.magnitude else { return quotient }
        return sum < 0 ? quotient - 1 : quotient + 1
    }
}

/// Read-only summary of a confirmed `AppState` over a period. Days without a
/// log are reported, never materialised into the state; no file is touched.
public struct StatisticsSummary: Equatable, Sendable {
    public let period: StatisticsPeriod
    public let days: [DayStatistic]
    public let aggregate: StatisticsAggregate?
    public let failure: StatisticsFailure?

    public var loggedDays: [DayStatistic] { days.filter(\.isLogged) }
    /// Present even when the aggregate could not be computed, so the period
    /// warnings do not disappear with the totals.
    public var includesNegative: Bool { days.contains { $0.isNegative } }
    public var includesLegacy: Bool { days.contains { $0.hasLegacy } }

    public static func compute(state: AppState, period: StatisticsPeriod) -> StatisticsSummary {
        let goalLookup = GoalResolver(state: state)
        var days: [DayStatistic] = []
        var sum: Int64 = 0
        var loggedCount = 0
        var includesNegative = false
        var includesLegacy = false
        var failure: StatisticsFailure?
        for day in period.days {
            let log = state.log(for: day)
            let entry = Self.entryState(of: log)
            var total: Int64?
            if entry != .none, let log {
                total = try? log.totalProteinCentigrams()
                if let total {
                    let (partial, overflow) = sum.addingReportingOverflow(total)
                    if overflow { failure = failure ?? .arithmeticOverflow } else { sum = partial }
                    if total < 0 { includesNegative = true }
                } else {
                    failure = failure ?? .dayTotalUnavailable(day)
                }
                loggedCount += 1
                if log.hasLegacyTotal { includesLegacy = true }
            }
            days.append(DayStatistic(day: day, entry: entry, totalCentigrams: total, goal: goalLookup.goal(on: day)))
        }
        let aggregate = failure == nil
            ? StatisticsAggregate(loggedDayCount: loggedCount, totalCentigrams: sum,
                                  includesNegative: includesNegative, includesLegacy: includesLegacy)
            : nil
        return StatisticsSummary(period: period, days: days, aggregate: aggregate, failure: failure)
    }

    static func entryState(of log: DailyLog?) -> DayEntryState {
        guard let log else { return .none }
        switch log.detailState {
        case .empty: return .none
        case .detailed: return .detailed
        case .legacyTotalOnly: return .legacyOnly
        case .legacyTotalWithNewDetails: return .legacyWithDetails
        }
    }

    /// Goal history validated once; the same priority as the home screen's
    /// goal state, so the two never disagree about a day.
    private struct GoalResolver {
        let goals: [ProteinGoal]
        let needsReview: Bool
        let historyError: String?

        init(state: AppState) {
            goals = state.goals
            needsReview = state.settings.goalNeedsReview
            do { try GoalHistory.validate(state.goals); historyError = nil }
            catch { historyError = String(describing: error) }
        }

        func goal(on day: CalendarDay) -> DayGoal {
            if goals.isEmpty { return needsReview ? .needsReview : .notSet }
            if let historyError { return .integrityError(historyError) }
            guard let goal = goals.filter({ $0.effectiveFrom <= day }).max(by: { $0.effectiveFrom < $1.effectiveFrom }) else {
                return .noHistory
            }
            return .goal(goal.amount)
        }
    }
}
