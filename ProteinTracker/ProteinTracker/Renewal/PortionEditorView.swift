import SwiftUI
import HelloProteinCore

// MARK: - Pure decisions

/// What the amount field currently yields. Only `.valid` can be applied or
/// saved; a bad input never shows the previous good value as its result.
@available(iOS 15.0, *)
enum PortionPreview: Equatable {
    case valid(quantity: FoodQuantity, centigrams: Int64, rounded: Bool)
    case input(PortionInputError)
    case calculation(PortionCalculationError)

    var centigrams: Int64? {
        if case .valid(_, let centigrams, _) = self { return centigrams }
        return nil
    }

    var quantity: FoodQuantity? {
        if case .valid(let quantity, _, _) = self { return quantity }
        return nil
    }
}

/// Decisions of the amount editor, free of SwiftUI so they can be unit
/// tested: parsing in the user's separator, the exact calculation from the
/// basis, dirtiness and the apply rule. No store, no network.
@available(iOS 15.0, *)
enum PortionEditorPolicy {
    static func preview(basis: CalculationBasis, amountText: String, decimalSeparator: String) -> PortionPreview {
        let decimal: PortionDecimal
        do { decimal = try PortionInput.parseQuantity(amountText, decimalSeparator: decimalSeparator) }
        catch let error as PortionInputError { return .input(error) }
        catch { return .input(.notANumber) }
        let quantity: FoodQuantity
        do { quantity = try FoodQuantity(value: decimal.canonical, unit: basis.referenceQuantity.unit) }
        catch { return .input(.notANumber) }
        do {
            let result = try basis.protein(for: quantity)
            return .valid(quantity: quantity, centigrams: result.centigrams, rounded: result.rounded)
        } catch let error as PortionCalculationError {
            return .calculation(error)
        } catch {
            return .calculation(.invalidValue)
        }
    }

    /// Exact text comparison, like the other editors: a typed space counts.
    static func isDirty(initial: String, current: String) -> Bool { initial != current }

    static func canApply(_ preview: PortionPreview, locked: Bool) -> Bool { !locked && preview.centigrams != nil }

    /// The stored decimal in the user's separator, for the field's initial text.
    static func amountText(_ quantity: FoodQuantity, decimalSeparator: String) -> String {
        quantity.value.replacingOccurrences(of: ".", with: decimalSeparator)
    }

    /// The basis protein with its full stored precision (`1.005`, never a
    /// rounded `1.01`), in the user's separator.
    static func basisProteinText(_ basis: CalculationBasis, decimalSeparator: String) -> String {
        basis.proteinGramsText.replacingOccurrences(of: ".", with: decimalSeparator)
    }
}

@available(iOS 15.0, *)
extension SearchResultItem {
    /// The calculation basis a record from this row can carry, or nil when
    /// the row cannot be edited: the reference is outside the amount editor's
    /// range or the basis limits, or the exact calculation would not
    /// reproduce the verified value the row shows. Such rows are still added
    /// the old way, with the reference amount and no basis.
    var calculationBasis: CalculationBasis? {
        guard isSelectable, let reference, let centigrams = proteinCentigrams else { return nil }
        guard let basis = try? CalculationBasis.providerSnapshot(proteinGramsText: rawProtein, referenceQuantity: reference.quantity,
                                                                 providerID: providerID, dataVersion: dataVersion, itemID: itemID),
              basis.isReferenceEditable,
              (try? basis.protein(for: reference.quantity))?.centigrams == centigrams else { return nil }
        return basis
    }
}

// MARK: - Text

@available(iOS 15.0, *)
enum PortionText {
    /// "12.18 g protein per 100 g", or the user-defined wording for a basis
    /// the user entered.
    static func basis(_ basis: CalculationBasis, decimalSeparator: String) -> String {
        let line = RenewalStrings.format("renewal_search_reference",
                                         PortionEditorPolicy.basisProteinText(basis, decimalSeparator: decimalSeparator),
                                         QuantityText.amount(basis.referenceQuantity))
        switch basis.origin {
        case .providerSnapshot: return line
        case .userDefined: return RenewalStrings.text("renewal_amount_user_basis") + " · " + line
        }
    }

    /// "Amount eaten: 150 g".
    static func eaten(_ quantity: FoodQuantity) -> String {
        RenewalStrings.format("renewal_amount_eaten", QuantityText.amount(quantity))
    }

    /// "Protein to log: 18.27 g".
    static func preview(centigrams: Int64, decimalSeparator: String) -> String {
        RenewalStrings.format("renewal_amount_preview", ProteinInput.format(centigrams: centigrams, decimalSeparator: decimalSeparator))
    }

    static func error(_ preview: PortionPreview) -> String? {
        switch preview {
        case .valid: return nil
        case .input(let error): return RenewalStrings.text(inputKey(error))
        case .calculation(let error): return RenewalStrings.text(calculationKey(error))
        }
    }

    static func inputKey(_ error: PortionInputError) -> String {
        switch error {
        case .empty: return "renewal_amount_error_empty"
        case .notANumber, .mixedSeparators: return "renewal_amount_error_number"
        case .groupingNotAllowed: return "renewal_error_input_grouping"
        case .negative, .zero: return "renewal_amount_error_positive"
        case .tooManyIntegerDigits, .tooManyFractionDigits: return "renewal_amount_error_digits"
        }
    }

    static func calculationKey(_ error: PortionCalculationError) -> String {
        switch error {
        case .roundsToZero: return "renewal_amount_error_rounds_to_zero"
        case .overflow: return "renewal_error_input_overflow"
        case .unitMismatch, .invalidValue: return "renewal_amount_error_invalid"
        }
    }
}

// MARK: - Amount editor (shared by the search editor and the record editor)

/// Basis line, amount field with a fixed unit, and the live result or the
/// validation message. Holds no state of its own: the owner keeps the text,
/// decides when to apply or save, and locks the field while a write runs.
@available(iOS 15.0, *)
struct PortionAmountEditor: View {
    let basis: CalculationBasis
    @Binding var amountText: String
    let decimalSeparator: String
    let locked: Bool
    var fieldIdentifier = "renewal.amount.field"
    /// Focus the field (keyboard and VoiceOver) when the editor is entered.
    var focusOnAppear = false
    @FocusState private var fieldFocused: Bool

    private var preview: PortionPreview {
        PortionEditorPolicy.preview(basis: basis, amountText: amountText, decimalSeparator: decimalSeparator)
    }
    private var unit: String { QuantityText.unit(basis.referenceQuantity.unit) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(PortionText.basis(basis, decimalSeparator: decimalSeparator))
                .font(.footnote).monospacedDigit().foregroundColor(RenewalTheme.secondary)
                .accessibilityIdentifier("renewal.amount.basis")
            Text(RenewalStrings.format("renewal_amount_input", unit)).font(.subheadline.weight(.semibold))
            HStack(spacing: 10) {
                TextField(RenewalStrings.format("renewal_amount_input", unit), text: $amountText)
                    .renewalInput()
                    .keyboardType(.decimalPad)
                    .accessibilityLabel(Text(RenewalStrings.format("renewal_amount_input", unit)))
                    .accessibilityIdentifier(fieldIdentifier)
                    .focused($fieldFocused)
                    .disabled(locked)
                    .opacity(locked ? 0.5 : 1)
                // The unit never moves or hides behind the keyboard.
                Text(unit).font(.body.weight(.semibold)).foregroundColor(RenewalTheme.ink)
                    .accessibilityHidden(true)
            }
            switch preview {
            case .valid(_, let centigrams, let rounded):
                Text(PortionText.preview(centigrams: centigrams, decimalSeparator: decimalSeparator))
                    .font(.body.weight(.semibold)).monospacedDigit().foregroundColor(RenewalTheme.action)
                    .accessibilityIdentifier("renewal.amount.preview")
                if rounded {
                    Text("renewal_search_rounded").font(.caption).foregroundColor(RenewalTheme.secondary)
                }
            case .input, .calculation:
                // Nothing is shown as the result: no dash that could be read
                // as a value, and never the previous good number.
                Text(PortionText.error(preview) ?? "").font(.footnote).foregroundColor(RenewalTheme.danger)
                    .accessibilityIdentifier("renewal.amount.error")
            }
        }
        .onAppear {
            // After the view is in the hierarchy; a synchronous set is dropped.
            guard focusOnAppear, !locked else { return }
            DispatchQueue.main.async { fieldFocused = true }
        }
    }
}

// MARK: - Search amount editor (inside the add sheet)

/// The in-sheet screen for one selected search result: food name, the
/// provider's basis, the amount eaten and the protein that would be logged.
/// Apply changes the session draft only; nothing is written here.
@available(iOS 15.0, *)
struct SearchAmountEditorView: View {
    let target: SearchSessionModel.AmountEditTarget
    @Binding var amountText: String
    let decimalSeparator: String
    let locked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(target.item.name).font(.headline).foregroundColor(RenewalTheme.ink)
                .accessibilityIdentifier("renewal.amount.name")
            PortionAmountEditor(basis: target.basis, amountText: $amountText, decimalSeparator: decimalSeparator, locked: locked,
                                focusOnAppear: true)
            Text("renewal_amount_apply_note").font(.footnote).foregroundColor(RenewalTheme.secondary)
        }
        .renewalCard()
    }
}
