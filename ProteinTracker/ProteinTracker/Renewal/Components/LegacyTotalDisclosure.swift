import SwiftUI
import HelloProteinCore

@available(iOS 15.0, *)
struct LegacyTotalDisclosure: View {
    let log: DailyLog
    let total: Int64?
    let decimalSeparator: String
    let canEdit: Bool
    let onEdit: () -> Void
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 12) {
                if let original = log.legacyAggregate?.importedTotalCentigrams {
                    valueRow("renewal_original_total", value: format(original))
                }
                if let detailSum = try? log.recordSumCentigrams() {
                    valueRow("renewal_food_entries", value: format(detailSum))
                }
                if let adjustment = log.legacyAdjustmentCentigrams {
                    valueRow("renewal_legacy_adjustment", value: signed(adjustment))
                }
                if let total = total { valueRow("renewal_current_total", value: format(total)) }
                Text(LocalizedStringKey(log.detailState == .legacyTotalOnly ? "renewal_legacy_total_only" : "renewal_adjustment_explanation"))
                    .font(.footnote).foregroundColor(RenewalTheme.secondary)
                Button(action: onEdit) {
                    Text("renewal_edit_total").font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                }
                .disabled(!canEdit)
                .accessibilityIdentifier("renewal.editTotal")
            }
            .padding(.top, 12)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(log.detailState == .legacyTotalOnly && log.legacyAggregate != nil ? "renewal_legacy_total_label" : "renewal_legacy_section"))
                    .font(.subheadline.weight(.semibold))
                if log.detailState == .legacyTotalOnly, let original = log.legacyAggregate?.importedTotalCentigrams {
                    Text(format(original) + " g").font(.subheadline).monospacedDigit()
                } else if let adjustment = log.legacyAdjustmentCentigrams {
                    Text(signed(adjustment) + " g").font(.subheadline).monospacedDigit()
                }
            }
            .foregroundColor(RenewalTheme.ink)
            .frame(minHeight: 44)
        }
        .padding(16)
        .background(RenewalTheme.chip)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func valueRow(_ key: String, value: String) -> some View {
        // A vertical pair stays readable even for large signed totals at AX sizes.
        VStack(alignment: .leading, spacing: 2) {
            Text(LocalizedStringKey(key)).font(.caption).foregroundColor(RenewalTheme.secondary)
            Text(value + " g").font(.subheadline.weight(.medium)).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func format(_ value: Int64) -> String {
        ProteinInput.format(centigrams: value, decimalSeparator: decimalSeparator)
    }

    private func signed(_ value: Int64) -> String { value > 0 ? "+" + format(value) : format(value) }
}
