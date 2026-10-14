import XCTest
@testable import HelloProteinCore

final class StatisticsSummaryTests: XCTestCase {
    private func day(_ iso: String) -> CalendarDay { try! CalendarDay(iso8601: iso) }

    private func record(_ id: String, on day: CalendarDay, centigrams: Int64) throws -> FoodRecord {
        try FoodRecord(id: id, day: day, name: "Food", quantity: nil, protein: ProteinAmount(centigrams: centigrams), source: .manual)
    }

    private func state(logs: [DailyLog], goals: [ProteinGoal] = [], goalNeedsReview: Bool = false) throws -> AppState {
        try AppState(logs: logs, favorites: [], searchHistory: [],
                     settings: AppSettings(searchLanguage: .interpret(raw: nil), legacyTargetRaw: goalNeedsReview ? "x" : nil,
                                           goalNeedsReview: goalNeedsReview),
                     goals: goals,
                     migration: MigrationRecord(origin: .freshInstall, migrationVersion: 1, completedAt: "2026-10-01T00:00:00Z",
                                                sourceFingerprint: nil, verification: nil))
    }

    // MARK: Period

    func testPeriodEndsAtMinOfAnchorAndTodayAndSpansConsecutiveDays() {
        let today = day("2026-10-14")
        let week = StatisticsPeriod(endingAt: day("2026-10-20"), today: today, length: .week)
        XCTAssertEqual(week.end, today, "a selected day after today is clamped")
        XCTAssertEqual(week.start, day("2026-10-08"))
        XCTAssertEqual(week.days.map(\.iso8601), ["2026-10-08", "2026-10-09", "2026-10-10", "2026-10-11", "2026-10-12", "2026-10-13", "2026-10-14"])
        XCTAssertEqual(week.dayCount, 7)
        XCTAssertFalse(week.isTruncated)

        let earlier = StatisticsPeriod(endingAt: day("2026-10-10"), today: today, length: .week)
        XCTAssertEqual(earlier.end, day("2026-10-10"), "a past selected day is kept")
        let month = earlier.withLength(.month, today: today)
        XCTAssertEqual(month.end, day("2026-10-10"), "switching length keeps the end day")
        XCTAssertEqual(month.start, day("2026-09-11"))
        XCTAssertEqual(month.dayCount, 30)
        XCTAssertTrue(month.contains(day("2026-09-11")))
        XCTAssertFalse(month.contains(day("2026-09-10")))
        XCTAssertFalse(month.contains(day("2026-10-11")))
    }

    func testPeriodCrossesMonthYearAndLeapBoundariesByCalendarArithmetic() {
        let leap = StatisticsPeriod(endingAt: day("2024-03-02"), today: day("2024-03-02"), length: .week)
        XCTAssertEqual(leap.days.map(\.iso8601), ["2024-02-25", "2024-02-26", "2024-02-27", "2024-02-28", "2024-02-29", "2024-03-01", "2024-03-02"])
        let nonLeap = StatisticsPeriod(endingAt: day("2023-03-02"), today: day("2023-03-02"), length: .week)
        XCTAssertEqual(nonLeap.start, day("2023-02-24"))
        let newYear = StatisticsPeriod(endingAt: day("2026-01-03"), today: day("2026-01-03"), length: .month)
        XCTAssertEqual(newYear.start, day("2025-12-05"))
        XCTAssertEqual(newYear.dayCount, 30)
        let century = StatisticsPeriod(endingAt: day("2100-03-01"), today: day("2100-03-01"), length: .week)
        XCTAssertEqual(century.start, day("2100-02-23"), "2100 is not a leap year")
    }

    func testPeriodIsCutAtTheSupportedLowerBoundAndReportsTheRealDayCount() {
        XCTAssertNil(day("0001-01-01").adding(days: -1), "no wrap into BCE dates")
        XCTAssertEqual(day("0001-01-01").adding(days: 1), day("0001-01-02"))
        XCTAssertNil(day("9999-12-31").adding(days: 1))
        let today = day("0001-01-05")
        let week = StatisticsPeriod(endingAt: today, today: today, length: .week)
        XCTAssertEqual(week.days.map(\.iso8601), ["0001-01-01", "0001-01-02", "0001-01-03", "0001-01-04", "0001-01-05"])
        XCTAssertEqual(week.dayCount, 5)
        XCTAssertTrue(week.isTruncated)
        XCTAssertNil(week.previous(today: today), "nothing before the supported range")
        XCTAssertNil(week.next(today: today), "already ends today")
    }

    func testPreviousAndNextMoveByTheLengthAndNextStopsAtToday() throws {
        let today = day("2026-10-14")
        let week = StatisticsPeriod(endingAt: today, today: today, length: .week)
        let previous = try XCTUnwrap(week.previous(today: today))
        XCTAssertEqual(previous.end, day("2026-10-07"))
        XCTAssertEqual(previous.start, day("2026-10-01"))
        XCTAssertEqual(previous.next(today: today), week, "forward by a full length lands back on today")
        let twoBack = try XCTUnwrap(previous.previous(today: today))
        XCTAssertEqual(twoBack.end, day("2026-09-30"))

        let partial = StatisticsPeriod(endingAt: day("2026-10-11"), today: today, length: .week)
        let next = try XCTUnwrap(partial.next(today: today))
        XCTAssertEqual(next.end, today, "never past today")
        XCTAssertEqual(next.start, day("2026-10-08"))
        XCTAssertNil(next.next(today: today))

        let month = StatisticsPeriod(endingAt: today, today: today, length: .month)
        XCTAssertEqual(month.previous(today: today)?.end, day("2026-09-14"))
        XCTAssertEqual(month.previous(today: today)?.start, day("2026-08-16"))

        // A clock set back: the period ends after the new today; next is unavailable
        // and "latest" moves to the new today.
        let later = StatisticsPeriod(endingAt: day("2026-10-20"), today: day("2026-10-20"), length: .week)
        XCTAssertNil(later.next(today: day("2026-10-18")))
        XCTAssertEqual(later.latest(today: day("2026-10-18")).end, day("2026-10-18"))
        XCTAssertEqual(week.latest(today: day("2026-10-15")).end, day("2026-10-15"))
    }

    func testTodayDependsOnTheTimeZoneButStoredDaysDoNot() throws {
        // 2026-10-14 23:30 UTC is already the 15th in Seoul and still the 14th in Los Angeles.
        let instant = ISO8601DateFormatter().date(from: "2026-10-14T23:30:00Z")!
        let seoul = try XCTUnwrap(CalendarDay.today(now: instant, timeZone: TimeZone(identifier: "Asia/Seoul")!))
        let losAngeles = try XCTUnwrap(CalendarDay.today(now: instant, timeZone: TimeZone(identifier: "America/Los_Angeles")!))
        XCTAssertEqual(seoul, day("2026-10-15"))
        XCTAssertEqual(losAngeles, day("2026-10-14"))
        let logged = try DailyLog(day: day("2026-10-14"), records: [record("r", on: day("2026-10-14"), centigrams: 1_000)])
        let state = try state(logs: [logged])
        // The same stored day is counted the same from either zone; only "today" moves.
        for today in [seoul, losAngeles] {
            let summary = StatisticsSummary.compute(state: state, period: StatisticsPeriod(endingAt: today, today: today, length: .week))
            XCTAssertEqual(summary.days.first { $0.day == day("2026-10-14") }?.totalCentigrams, 1_000)
            XCTAssertEqual(summary.period.end, today)
        }
        // A DST change inside the period does not add or drop a day (US fall back 2026-11-01).
        let dst = StatisticsPeriod(endingAt: day("2026-11-03"), today: day("2026-11-03"), length: .week)
        XCTAssertEqual(dst.days.map(\.iso8601), ["2026-10-28", "2026-10-29", "2026-10-30", "2026-10-31", "2026-11-01", "2026-11-02", "2026-11-03"])
        XCTAssertEqual(StatisticsPeriod(endingAt: day("2026-03-10"), today: day("2026-03-10"), length: .week).dayCount, 7)
    }

    // MARK: Day states and aggregate

    func testSummaryCountsOnlyLoggedDaysAndKeepsSignedLegacyTotals() throws {
        let today = day("2026-10-14")
        let period = StatisticsPeriod(endingAt: today, today: today, length: .week)
        let d = period.days
        let logs = try [
            DailyLog(day: d[0], records: [record("a", on: d[0], centigrams: 2_000)]),
            DailyLog(day: d[1], records: [record("b", on: d[1], centigrams: 4_000)]),
            DailyLog(day: d[2], records: [record("c", on: d[2], centigrams: 1_000), record("d", on: d[2], centigrams: 5_000)]),
            DailyLog(day: d[3], records: [], legacyAdjustmentCentigrams: 0),
            DailyLog(day: d[4], records: [], legacyAdjustmentCentigrams: -1_000),
            DailyLog(day: d[5], records: []),
            // d[6] has no log at all.
        ]
        let summary = StatisticsSummary.compute(state: try state(logs: logs), period: period)
        XCTAssertNil(summary.failure)
        let aggregate = try XCTUnwrap(summary.aggregate)
        XCTAssertEqual(aggregate.loggedDayCount, 5, "an empty log and a missing log are not logged days")
        XCTAssertEqual(aggregate.totalCentigrams, 11_000)
        XCTAssertEqual(aggregate.averageCentigrams, 2_200, "110 g over 5 logged days, not over 7")
        XCTAssertTrue(aggregate.includesNegative)
        XCTAssertTrue(aggregate.includesLegacy)
        XCTAssertTrue(summary.includesNegative)
        XCTAssertTrue(summary.includesLegacy)
        XCTAssertEqual(summary.days.map(\.entry), [.detailed, .detailed, .detailed, .legacyOnly, .legacyOnly, .none, .none])
        XCTAssertEqual(summary.days.map(\.totalCentigrams), [2_000, 4_000, 6_000, 0, -1_000, nil, nil])
        XCTAssertEqual(summary.days[3].isLogged, true, "a recorded 0 g day is logged")
        XCTAssertEqual(summary.days[4].isNegative, true)
        XCTAssertEqual(summary.loggedDays.count, 5)
        XCTAssertEqual(summary.period.dayCount, 7)
    }

    func testMixedLegacyAndDetailsUsesTheLogsFinalTotalNotTheDetailSum() throws {
        let today = day("2026-10-14")
        let period = StatisticsPeriod(endingAt: today, today: today, length: .week)
        let mixed = try DailyLog(day: today, records: [record("a", on: today, centigrams: 3_000)], legacyAdjustmentCentigrams: 7_000)
        let summary = StatisticsSummary.compute(state: try state(logs: [mixed]), period: period)
        XCTAssertEqual(summary.days.last?.entry, .legacyWithDetails)
        XCTAssertEqual(summary.days.last?.totalCentigrams, 10_000)
        XCTAssertEqual(summary.aggregate?.totalCentigrams, 10_000)
        XCTAssertEqual(summary.aggregate?.averageCentigrams, 10_000)
        XCTAssertEqual(summary.aggregate?.includesLegacy, true)
        XCTAssertEqual(summary.aggregate?.includesNegative, false)
    }

    func testEmptyPeriodHasNoAverageAndZeroLoggedDays() throws {
        let today = day("2026-10-14")
        let period = StatisticsPeriod(endingAt: today, today: today, length: .month)
        let summary = StatisticsSummary.compute(state: try state(logs: []), period: period)
        let aggregate = try XCTUnwrap(summary.aggregate)
        XCTAssertEqual(aggregate.loggedDayCount, 0)
        XCTAssertEqual(aggregate.totalCentigrams, 0)
        XCTAssertNil(aggregate.averageCentigrams, "no logged day: no average, never 0")
        XCTAssertEqual(summary.days.count, 30)
        XCTAssertTrue(summary.days.allSatisfy { $0.entry == .none && $0.totalCentigrams == nil })
    }

    func testFutureAndOutOfPeriodDaysAreIgnored() throws {
        let today = day("2026-10-14")
        let period = StatisticsPeriod(endingAt: today, today: today, length: .week)
        let logs = try [
            DailyLog(day: day("2026-10-15"), records: [record("f", on: day("2026-10-15"), centigrams: 9_900)]),
            DailyLog(day: day("2026-10-07"), records: [record("p", on: day("2026-10-07"), centigrams: 9_900)]),
            DailyLog(day: day("2026-10-08"), records: [record("s", on: day("2026-10-08"), centigrams: 100)]),
        ]
        let summary = StatisticsSummary.compute(state: try state(logs: logs), period: period)
        XCTAssertEqual(summary.aggregate?.loggedDayCount, 1)
        XCTAssertEqual(summary.aggregate?.totalCentigrams, 100)
        XCTAssertFalse(summary.days.contains { $0.day == day("2026-10-15") })
    }

    func testOverflowReportsAFailureInsteadOfZeroOrAPartialSum() throws {
        let today = day("2026-10-14")
        let period = StatisticsPeriod(endingAt: today, today: today, length: .week)
        let d = period.days
        let logs = try [
            DailyLog(day: d[0], records: [], legacyAdjustmentCentigrams: Int64.max),
            DailyLog(day: d[1], records: [record("x", on: d[1], centigrams: 1)]),
            DailyLog(day: d[2], records: [record("y", on: d[2], centigrams: 500)]),
        ]
        let summary = StatisticsSummary.compute(state: try state(logs: logs), period: period)
        XCTAssertEqual(summary.failure, .arithmeticOverflow)
        XCTAssertNil(summary.aggregate, "no partial sum, no zero")
        XCTAssertTrue(summary.includesLegacy, "period warnings survive a failed aggregate")
        XCTAssertFalse(summary.includesNegative)
        XCTAssertEqual(summary.days[0].totalCentigrams, Int64.max, "the day list stays available")
        XCTAssertEqual(summary.days[2].totalCentigrams, 500)
        XCTAssertEqual(summary.loggedDays.count, 3)
    }

    func testAverageRoundsTheSignedHalfAwayFromZeroWithoutOverflow() {
        XCTAssertEqual(StatisticsAggregate.roundedAverage(sum: 11_000, count: 5), 2_200)
        XCTAssertEqual(StatisticsAggregate.roundedAverage(sum: 10, count: 4), 3, "2.5 → 3")
        XCTAssertEqual(StatisticsAggregate.roundedAverage(sum: -10, count: 4), -3, "-2.5 → -3")
        XCTAssertEqual(StatisticsAggregate.roundedAverage(sum: 7, count: 3), 2, "2.33 → 2")
        XCTAssertEqual(StatisticsAggregate.roundedAverage(sum: 8, count: 3), 3, "2.67 → 3")
        XCTAssertEqual(StatisticsAggregate.roundedAverage(sum: -7, count: 3), -2)
        XCTAssertEqual(StatisticsAggregate.roundedAverage(sum: -8, count: 3), -3)
        XCTAssertEqual(StatisticsAggregate.roundedAverage(sum: 1, count: 2), 1, "0.5 → 1")
        XCTAssertEqual(StatisticsAggregate.roundedAverage(sum: -1, count: 2), -1)
        XCTAssertEqual(StatisticsAggregate.roundedAverage(sum: 0, count: 7), 0)
        XCTAssertEqual(StatisticsAggregate.roundedAverage(sum: Int64.min, count: 1), Int64.min)
        XCTAssertEqual(StatisticsAggregate.roundedAverage(sum: Int64.min, count: 2), Int64.min / 2)
        XCTAssertEqual(StatisticsAggregate.roundedAverage(sum: Int64.min, count: 3), -3_074_457_345_618_258_603)
        XCTAssertEqual(StatisticsAggregate.roundedAverage(sum: Int64.max, count: 2), 4_611_686_018_427_387_904, "…903.5 → …904")
        XCTAssertEqual(StatisticsAggregate.roundedAverage(sum: Int64.max, count: 30), 307_445_734_561_825_860)
    }

    // MARK: Goals per day

    func testGoalsAreResolvedPerDayWithTheHomeScreensPriority() throws {
        let today = day("2026-10-14")
        let period = StatisticsPeriod(endingAt: today, today: today, length: .week)
        let d = period.days // 10-08 … 10-14
        let goals = try [
            ProteinGoal(id: "g1", effectiveFrom: day("2026-10-10"), amount: ProteinAmount(centigrams: 10_000)),
            ProteinGoal(id: "g2", effectiveFrom: day("2026-10-12"), amount: ProteinAmount(centigrams: 12_000)),
        ]
        let logs = try [
            DailyLog(day: d[3], records: [record("a", on: d[3], centigrams: 10_000)]),   // 10-11: 100 g vs 100 g goal
            DailyLog(day: d[4], records: [record("b", on: d[4], centigrams: 10_000)]),   // 10-12: 100 g vs 120 g goal
            DailyLog(day: d[5], records: [], legacyAdjustmentCentigrams: -500),         // 10-13: negative, no verdict
        ]
        let summary = StatisticsSummary.compute(state: try state(logs: logs, goals: goals), period: period)
        XCTAssertEqual(summary.days[0].goal, .noHistory, "before the first goal: not filled with the current goal")
        XCTAssertEqual(summary.days[2].goal, .goal(try ProteinAmount(centigrams: 10_000)))
        XCTAssertEqual(summary.days[3].goal, .goal(try ProteinAmount(centigrams: 10_000)))
        XCTAssertEqual(summary.days[4].goal, .goal(try ProteinAmount(centigrams: 12_000)))
        XCTAssertEqual(summary.days[6].goal, .goal(try ProteinAmount(centigrams: 12_000)))
        XCTAssertEqual(summary.days[3].comparison, .reached)
        XCTAssertEqual(summary.days[4].comparison, .below)
        XCTAssertEqual(summary.days[5].comparison, .notApplicable, "negative totals get no verdict")
        XCTAssertEqual(summary.days[2].comparison, .notApplicable, "no entry: no verdict")
        XCTAssertEqual(summary.days[0].comparison, .notApplicable)

        let unset = StatisticsSummary.compute(state: try state(logs: logs), period: period)
        XCTAssertTrue(unset.days.allSatisfy { $0.goal == .notSet })
        let review = StatisticsSummary.compute(state: try state(logs: logs, goalNeedsReview: true), period: period)
        XCTAssertTrue(review.days.allSatisfy { $0.goal == .needsReview })
        let reviewWithHistory = StatisticsSummary.compute(state: try state(logs: logs, goals: goals, goalNeedsReview: true), period: period)
        XCTAssertEqual(reviewWithHistory.days[6].goal, .goal(try ProteinAmount(centigrams: 12_000)),
                       "the global review flag does not hide a real per-day goal")
        XCTAssertEqual(reviewWithHistory.days[0].goal, .noHistory)
    }

    func testGoalComparisonUsesTheDaysOwnGoalAndRecomputesAfterEdits() throws {
        let today = day("2026-10-14")
        let period = StatisticsPeriod(endingAt: today, today: today, length: .week)
        let goals = try [ProteinGoal(id: "g", effectiveFrom: day("2026-01-01"), amount: ProteinAmount(centigrams: 2_000))]
        var appState = try state(logs: [DailyLog(day: today, records: [record("a", on: today, centigrams: 1_827)])], goals: goals)
        var summary = StatisticsSummary.compute(state: appState, period: period)
        XCTAssertEqual(summary.days.last?.totalCentigrams, 1_827)
        XCTAssertEqual(summary.days.last?.comparison, .below)

        // Editing the stored record changes the same period's numbers at once.
        var log = try XCTUnwrap(appState.log(for: today))
        try log.update(try XCTUnwrap(log.record(id: "a")).withChanges(protein: ProteinAmount(centigrams: 2_436)))
        try appState.upsert(log)
        summary = StatisticsSummary.compute(state: appState, period: period)
        XCTAssertEqual(summary.days.last?.totalCentigrams, 2_436)
        XCTAssertEqual(summary.days.last?.comparison, .reached)
        XCTAssertEqual(summary.aggregate?.averageCentigrams, 2_436)

        _ = try log.delete(id: "a")
        try appState.upsert(log)
        summary = StatisticsSummary.compute(state: appState, period: period)
        XCTAssertEqual(summary.days.last?.entry, DayEntryState.none, "an emptied log without legacy total is no longer a logged day")
        XCTAssertEqual(summary.aggregate?.loggedDayCount, 0)
        XCTAssertNil(summary.aggregate?.averageCentigrams)
    }
}
