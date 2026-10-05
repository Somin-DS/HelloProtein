/// Presentation arithmetic only. Totals still come from DailyLog's checked integer sum.
struct GoalProgressPresentation {
    let fraction: Double
    let excessCentigrams: Int64?
    let isReached: Bool

    init(total: Int64, goal: Int64) {
        guard goal > 0 else {
            fraction = 0
            excessCentigrams = nil
            isReached = false
            return
        }
        fraction = min(max(Double(total) / Double(goal), 0), 1)
        isReached = total >= goal
        // Both values are positive in this branch, so subtraction cannot overflow.
        excessCentigrams = total > goal ? total - goal : nil
    }
}
