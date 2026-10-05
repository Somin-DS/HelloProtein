import SwiftUI
import HelloProteinCore

@available(iOS 15.0, *)
struct FoodRow: View {
    let record: FoodRecord
    let decimalSeparator: String
    @Environment(\.sizeCategory) private var sizeCategory

    private var name: String { record.name ?? RenewalStrings.text("renewal_manual_entry") }
    private var amount: String { ProteinInput.format(centigrams: record.protein.centigrams, decimalSeparator: decimalSeparator) + " g" }

    var body: some View {
        Group {
            if sizeCategory.isAccessibilityCategory {
                VStack(alignment: .leading, spacing: 8) { title; quantity }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    title
                    Spacer(minLength: 0)
                    quantity
                }
            }
        }
        .renewalCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(name + ", " + amount))
        .accessibilityValue(Text(record.source == .legacy ? RenewalStrings.text("renewal_legacy_entry") : ""))
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name).font(.body.weight(.medium)).foregroundColor(RenewalTheme.ink)
                .lineLimit(sizeCategory.isAccessibilityCategory ? nil : 2)
                .multilineTextAlignment(.leading)
            if record.source == .legacy {
                Text("renewal_legacy_entry").font(.caption).foregroundColor(RenewalTheme.secondary)
                    .multilineTextAlignment(.leading)
            }
        }
    }

    private var quantity: some View {
        Text(amount).font(.body.weight(.semibold)).monospacedDigit()
            .foregroundColor(RenewalTheme.action).fixedSize(horizontal: false, vertical: true)
    }
}
