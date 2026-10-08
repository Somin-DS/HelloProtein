import SwiftUI
import HelloProteinCore

@available(iOS 15.0, *)
struct FoodRow: View {
    let record: FoodRecord
    let decimalSeparator: String
    @Environment(\.sizeCategory) private var sizeCategory

    private var name: String { record.name ?? RenewalStrings.text("renewal_manual_entry") }
    private var amount: String { ProteinInput.format(centigrams: record.protein.centigrams, decimalSeparator: decimalSeparator) + " g" }
    /// The stored reference amount, e.g. "per 100 g", for search records.
    private var reference: String? { record.quantity.map(QuantityText.reference) }

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
        .accessibilityLabel(Text([name, amount, reference].compactMap { $0 }.joined(separator: ", ")))
        .accessibilityValue(Text(record.source == .legacy ? RenewalStrings.text("renewal_legacy_entry") : ""))
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name).font(.body.weight(.medium)).foregroundColor(RenewalTheme.ink)
                .lineLimit(sizeCategory.isAccessibilityCategory ? nil : 2)
                .multilineTextAlignment(.leading)
            if let reference {
                Text(reference).font(.caption).foregroundColor(RenewalTheme.secondary)
                    .multilineTextAlignment(.leading)
            }
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

/// Localized text for a stored `FoodQuantity`. The stored decimal string is
/// shown as is; only the unit is localized.
@available(iOS 15.0, *)
enum QuantityText {
    static func unit(_ unit: FoodQuantity.Unit) -> String {
        switch unit {
        case .gram: return RenewalStrings.text("renewal_unit_gram")
        case .ounce: return RenewalStrings.text("renewal_unit_ounce")
        case .milliliter: return RenewalStrings.text("renewal_unit_milliliter")
        case .serving: return RenewalStrings.text("renewal_unit_serving")
        case .piece: return RenewalStrings.text("renewal_unit_piece")
        }
    }

    /// "100 g", "1 serving".
    static func amount(_ quantity: FoodQuantity) -> String {
        quantity.value + " " + unit(quantity.unit)
    }

    /// "Per 100 g".
    static func reference(_ quantity: FoodQuantity) -> String {
        RenewalStrings.format("renewal_record_reference", amount(quantity))
    }
}
