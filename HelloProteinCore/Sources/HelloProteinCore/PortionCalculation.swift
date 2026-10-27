import Foundation

public enum PortionInputError: Error, Equatable {
    case empty
    /// Not a plain decimal: letters, exponents, NaN, infinity, signs, non-ASCII digits.
    case notANumber
    /// Both `.` and the locale separator, or the same separator twice.
    case mixedSeparators
    /// Spaces, apostrophes or other grouping marks inside the number.
    case groupingNotAllowed
    case negative
    case zero
    /// More than `PortionInput.maxIntegerDigits` digits before the separator.
    case tooManyIntegerDigits
    /// More than `PortionInput.maxFractionDigits` digits after the separator.
    case tooManyFractionDigits
}

/// A positive decimal number kept as its digit string: exact, locale free and
/// platform independent. `canonical` has no sign, no leading zeros in the
/// integer part (except a single `0`), no trailing zeros in the fraction and
/// no trailing separator, so equal values have equal text.
public struct PortionDecimal: Equatable, Sendable {
    public let canonical: String
    /// Integer digits, most significant first, without leading zeros (empty for `0.x`).
    let integerDigits: [UInt8]
    /// Fraction digits without trailing zeros.
    let fractionDigits: [UInt8]

    /// Parses a canonical positive decimal (`123`, `0.5`, `12.18`). Accepts
    /// the same shapes `FoodQuantity` stores (`.5`, `5.`, leading zeros) and
    /// canonicalizes them. No locale, no whitespace, no sign.
    public init(canonical text: String) throws {
        let scalars = Array(text.unicodeScalars)
        guard !scalars.isEmpty else { throw PortionInputError.empty }
        let parts = scalars.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count <= 2 else { throw PortionInputError.mixedSeparators }
        let integerPart = Array(parts[0])
        let fractionPart = parts.count == 2 ? Array(parts[1]) : []
        guard !integerPart.isEmpty || !fractionPart.isEmpty else { throw PortionInputError.notANumber }
        guard integerPart.allSatisfy(PortionDecimal.isASCIIDigit), fractionPart.allSatisfy(PortionDecimal.isASCIIDigit) else {
            throw PortionInputError.notANumber
        }
        var integer = integerPart.map { UInt8($0.value - 48) }
        var fraction = fractionPart.map { UInt8($0.value - 48) }
        while integer.first == 0 { integer.removeFirst() }
        while fraction.last == 0 { fraction.removeLast() }
        guard !integer.isEmpty || !fraction.isEmpty else { throw PortionInputError.zero }
        self.integerDigits = integer
        self.fractionDigits = fraction
        let integerText = integer.isEmpty ? "0" : integer.map(String.init).joined()
        self.canonical = fraction.isEmpty ? integerText : integerText + "." + fraction.map(String.init).joined()
    }

    public var integerDigitCount: Int { integerDigits.count }
    public var fractionDigitCount: Int { fractionDigits.count }

    /// Digits that carry information: all digits without leading zeros
    /// (`0.0012` has 2, `120.5` has 4). Trailing zeros of the integer part
    /// count because they fix the magnitude.
    public var significantDigitCount: Int {
        if integerDigits.isEmpty {
            var fraction = fractionDigits[...]
            while fraction.first == 0 { fraction = fraction.dropFirst() }
            return fraction.count
        }
        return integerDigits.count + fractionDigits.count
    }

    /// All digits as one integer (`12.18` → `1218`) with the number of fraction digits.
    var scaledDigits: [UInt8] { integerDigits + fractionDigits }

    static func isASCIIDigit(_ scalar: Unicode.Scalar) -> Bool {
        scalar.isASCII && ("0"..."9").contains(scalar)
    }
}

/// Strict user input for the amount eaten: positive, at most 9 integer and 3
/// fraction digits. The locale decimal separator and `.` are both accepted,
/// and one allowed separator always means the decimal point (`1.234` is one
/// point two three four in a comma locale, never 1234). Nothing is guessed
/// to be a grouping mark, nothing is truncated or rounded.
public enum PortionInput {
    public static let maxIntegerDigits = 9
    public static let maxFractionDigits = 3

    public static func parseQuantity(_ text: String, decimalSeparator: String = ".") throws -> PortionDecimal {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PortionInputError.empty }
        let separator = decimalSeparator.isEmpty ? "." : decimalSeparator
        var separatorCount = 0
        var normalized = ""
        var remaining = Substring(trimmed)
        while let first = remaining.first {
            if remaining.hasPrefix(separator) {
                separatorCount += 1
                normalized.append(".")
                remaining = remaining.dropFirst(separator.count)
                continue
            }
            if first == "." {
                separatorCount += 1
                normalized.append(".")
                remaining = remaining.dropFirst()
                continue
            }
            if first == "-" || first == "+" || first == "\u{2212}" {
                // A sign anywhere is not an amount; a leading minus is reported as negative.
                if normalized.isEmpty && first != "+" { throw PortionInputError.negative }
                throw PortionInputError.notANumber
            }
            if first == " " || first == "\u{00A0}" || first == "\u{202F}" || first == "'" || first == "’" || first == "_" {
                throw PortionInputError.groupingNotAllowed
            }
            if first == "," || first == "·" || first == "٫" {
                // Any other separator-like character: a grouping mark or a foreign decimal mark.
                throw separatorCount > 0 ? PortionInputError.mixedSeparators : PortionInputError.groupingNotAllowed
            }
            guard first.unicodeScalars.count == 1, let scalar = first.unicodeScalars.first,
                  PortionDecimal.isASCIIDigit(scalar) else {
                throw PortionInputError.notANumber
            }
            normalized.append(first)
            remaining = remaining.dropFirst()
        }
        guard separatorCount <= 1 else { throw PortionInputError.mixedSeparators }
        let decimal = try PortionDecimal(canonical: normalized)
        guard decimal.integerDigitCount <= maxIntegerDigits else { throw PortionInputError.tooManyIntegerDigits }
        guard decimal.fractionDigitCount <= maxFractionDigits else { throw PortionInputError.tooManyFractionDigits }
        return decimal
    }

    /// True when a stored quantity value can be shown and edited in the amount
    /// editor as is (within the 9/3 digit limits).
    public static func isEditableQuantityValue(_ value: String) -> Bool {
        guard let decimal = try? PortionDecimal(canonical: value) else { return false }
        return decimal.integerDigitCount <= maxIntegerDigits && decimal.fractionDigitCount <= maxFractionDigits
    }
}

public enum PortionCalculationError: Error, Equatable {
    /// The basis protein, reference or actual amount is not a positive decimal.
    case invalidValue
    /// Actual amount and reference amount are in different units.
    case unitMismatch
    /// The exact result rounds to 0.00 g: nothing to log.
    case roundsToZero
    /// The result does not fit the centigram store (Int64).
    case overflow
}

/// Exact proportional protein: `basisProtein × actual ÷ reference`, with one
/// half-up rounding at the third fraction digit to centigrams. Integer digit
/// arithmetic only; no `Double`, no `Decimal`, no epsilon.
public enum PortionCalculation {
    public struct Result: Equatable, Sendable {
        public let centigrams: Int64
        /// True when digits beyond the second fraction place were dropped or rounded.
        public let rounded: Bool
    }

    public static func centigrams(proteinGramsText: String, referenceQuantity: FoodQuantity,
                                  actualQuantity: FoodQuantity) throws -> Result {
        guard referenceQuantity.unit == actualQuantity.unit else { throw PortionCalculationError.unitMismatch }
        let protein: PortionDecimal, reference: PortionDecimal, actual: PortionDecimal
        do {
            protein = try PortionDecimal(canonical: proteinGramsText)
            reference = try PortionDecimal(canonical: referenceQuantity.value)
            actual = try PortionDecimal(canonical: actualQuantity.value)
        } catch { throw PortionCalculationError.invalidValue }
        return try centigrams(protein: protein, actual: actual, reference: reference)
    }

    /// result = (P × A × 10^rs) / (R × 10^(ps + as)) grams, where each value is
    /// `digits / 10^scale`. The quotient is taken in milligrams so the third
    /// fraction digit decides the rounding; everything after it only affects
    /// `rounded`.
    static func centigrams(protein: PortionDecimal, actual: PortionDecimal, reference: PortionDecimal) throws -> Result {
        let numerator = DigitArithmetic.multiply(protein.scaledDigits, actual.scaledDigits)
        // Long division keeps `remainder × 10 + digit` in UInt64 only while the
        // divisor stays below 10^18; basis limits guarantee that, a raw caller
        // does not.
        guard let divisor = DigitArithmetic.uint64(reference.scaledDigits), divisor < DigitArithmetic.maxDivisor else {
            throw PortionCalculationError.invalidValue
        }
        // Shift so that the integer quotient is in milligrams (3 fraction digits).
        let exponent = reference.fractionDigitCount + 3 - protein.fractionDigitCount - actual.fractionDigitCount
        var scaledNumerator = numerator
        if exponent >= 0 {
            scaledNumerator += [UInt8](repeating: 0, count: exponent)
        }
        let division = DigitArithmetic.divide(scaledNumerator, by: divisor)
        var quotient = division.quotient
        var inexact = division.remainder != 0
        if exponent < 0 {
            // floor(floor(N / R) / 10^k) == floor(N / (R × 10^k)); the dropped
            // digits are exact fraction digits of the quotient.
            let drop = -exponent
            let dropped = Array(quotient.suffix(drop))
            quotient = quotient.count <= drop ? [] : Array(quotient.dropLast(drop))
            if dropped.contains(where: { $0 != 0 }) { inexact = true }
        }
        // The last quotient digit is the third fraction digit; the rest are centigrams.
        let thirdDigit = quotient.last ?? 0
        guard let magnitude = DigitArithmetic.uint64(Array(quotient.dropLast())), magnitude <= UInt64(Int64.max) else {
            throw PortionCalculationError.overflow
        }
        var centigrams = Int64(magnitude)
        if thirdDigit >= 5 {
            let (up, overflow) = centigrams.addingReportingOverflow(1)
            guard !overflow else { throw PortionCalculationError.overflow }
            centigrams = up
        }
        let rounded = thirdDigit != 0 || inexact
        guard centigrams > 0 else { throw PortionCalculationError.roundsToZero }
        return Result(centigrams: centigrams, rounded: rounded)
    }
}

/// Schoolbook arithmetic on base-10 digit arrays (most significant first).
/// Sizes here are tiny (tens of digits), so clarity wins over speed.
enum DigitArithmetic {
    static func multiply(_ lhs: [UInt8], _ rhs: [UInt8]) -> [UInt8] {
        guard !lhs.isEmpty, !rhs.isEmpty else { return [] }
        var product = [Int](repeating: 0, count: lhs.count + rhs.count)
        for (i, a) in lhs.reversed().enumerated() {
            for (j, b) in rhs.reversed().enumerated() {
                product[i + j] += Int(a) * Int(b)
            }
        }
        var carry = 0
        for index in product.indices {
            let value = product[index] + carry
            product[index] = value % 10
            carry = value / 10
        }
        var digits = product.reversed().map { UInt8($0) }
        while digits.first == 0 { digits.removeFirst() }
        return digits
    }

    /// Long division by a non-zero `UInt64`. The running remainder stays below
    /// the divisor, so `remainder × 10 + digit` fits comfortably in `UInt64`
    /// for any divisor below 10^18 (basis values have at most 18 digits).
    /// Divisors must stay below this (10^18) so the running remainder never overflows.
    static let maxDivisor: UInt64 = 1_000_000_000_000_000_000

    static func divide(_ digits: [UInt8], by divisor: UInt64) -> (quotient: [UInt8], remainder: UInt64) {
        precondition(divisor > 0 && divisor < maxDivisor)
        var quotient: [UInt8] = []
        var remainder: UInt64 = 0
        for digit in digits {
            let (times, o1) = remainder.multipliedReportingOverflow(by: 10)
            let (current, o2) = times.addingReportingOverflow(UInt64(digit))
            precondition(!o1 && !o2, "divisor exceeds the supported digit count")
            quotient.append(UInt8(current / divisor))
            remainder = current % divisor
        }
        while quotient.first == 0 { quotient.removeFirst() }
        return (quotient, remainder)
    }

    /// nil when the value does not fit.
    static func uint64(_ digits: [UInt8]) -> UInt64? {
        var value: UInt64 = 0
        for digit in digits {
            let (times, o1) = value.multipliedReportingOverflow(by: 10)
            let (plus, o2) = times.addingReportingOverflow(UInt64(digit))
            guard !o1, !o2 else { return nil }
            value = plus
        }
        return value
    }
}
