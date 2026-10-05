import SwiftUI
import HelloProteinCore

@available(iOS 15.0, *)
struct DaySummary: View {
    let total: Int64?
    let goalState: RecordHomeViewModel.GoalState
    let decimalSeparator: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("renewal_daily_protein").font(.subheadline).foregroundColor(RenewalTheme.secondary)
            if let total = total {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(format(total)).font(RenewalTheme.amountFont)
                        .lineLimit(1).minimumScaleFactor(0.5)
                    Text("g").font(.title3).foregroundColor(RenewalTheme.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("renewal.dailyTotal")
                goalView(total: total)
            } else {
                Label { Text("renewal_total_error") } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                    .foregroundColor(RenewalTheme.danger)
            }
        }
        .renewalCard()
    }

    @ViewBuilder private func goalView(total: Int64) -> some View {
        switch goalState {
        case .goal(let goal):
            let progress = GoalProgressPresentation(total: total, goal: goal.centigrams)
            ProgressView(value: progress.fraction)
                .tint(RenewalTheme.action)
                .accessibilityLabel(Text("renewal_goal_completion"))
            Text(RenewalStrings.format("renewal_goal_progress", format(goal.centigrams)))
                .font(.subheadline).foregroundColor(RenewalTheme.secondary)
            if progress.isReached {
                Label { Text("renewal_goal_reached") } icon: { Image(systemName: "checkmark.circle.fill") }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(RenewalTheme.action)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(RenewalTheme.mint).clipShape(Capsule())
            }
            if let excess = progress.excessCentigrams {
                Text(RenewalStrings.format("renewal_goal_excess", format(excess)))
                    .font(.footnote).foregroundColor(RenewalTheme.secondary)
            }
        case .notSet:
            Text("renewal_goal_not_set").font(.subheadline).foregroundColor(RenewalTheme.secondary)
        case .noHistory:
            Text("renewal_goal_no_history").font(.subheadline).foregroundColor(RenewalTheme.secondary)
        case .needsReview(let raw):
            Label { Text(RenewalStrings.format("renewal_goal_needs_review", raw ?? "")) }
                icon: { Image(systemName: "exclamationmark.triangle") }
                .font(.footnote).foregroundColor(RenewalTheme.ink)
        case .integrityError(let detail):
            Text(RenewalStrings.format("renewal_goal_error", detail))
                .font(.footnote).foregroundColor(RenewalTheme.danger)
        }
    }

    private func format(_ value: Int64) -> String {
        ProteinInput.format(centigrams: value, decimalSeparator: decimalSeparator)
    }
}
