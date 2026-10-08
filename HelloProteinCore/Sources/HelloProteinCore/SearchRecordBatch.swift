import Foundation

public enum ProteinGramsTextError: Error, Equatable {
    /// Not a plain decimal number: signs other than a leading minus, exponents,
    /// NaN, infinity, grouping separators, whitespace or non-ASCII digits.
    case notANumber
    case negative
    case overflow
}

/// Lossless conversion of a provider's gram value, given as decimal text, to
/// centigrams. Never goes through a binary floating-point value. Half-up
/// rounding on the third fraction digit: `1.005` → 101 (rounded), `0.004` → 0.
public enum ProteinGramsText {
    public struct Conversion: Equatable, Sendable {
        public let centigrams: Int64
        /// True when fraction digits beyond the second were dropped or rounded.
        public let rounded: Bool
    }

    public static func centigrams(_ text: String) throws -> Conversion {
        var scalars = Array(text.unicodeScalars)
        guard !scalars.isEmpty else { throw ProteinGramsTextError.notANumber }
        var negative = false
        if scalars.first == "-" {
            negative = true
            scalars.removeFirst()
        }
        guard !scalars.isEmpty else { throw ProteinGramsTextError.notANumber }
        let parts = scalars.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count <= 2 else { throw ProteinGramsTextError.notANumber }
        let integerPart = Array(parts[0])
        let fractionPart = parts.count == 2 ? Array(parts[1]) : []
        guard !integerPart.isEmpty || !fractionPart.isEmpty else { throw ProteinGramsTextError.notANumber }
        guard integerPart.allSatisfy(isASCIIDigit), fractionPart.allSatisfy(isASCIIDigit) else {
            throw ProteinGramsTextError.notANumber
        }

        var centigrams: Int64 = 0
        for scalar in integerPart {
            let (times, o1) = centigrams.multipliedReportingOverflow(by: 10)
            let (plus, o2) = times.addingReportingOverflow(Int64(scalar.value - 48))
            guard !o1, !o2 else { throw ProteinGramsTextError.overflow }
            centigrams = plus
        }
        let (scaled, o3) = centigrams.multipliedReportingOverflow(by: 100)
        guard !o3 else { throw ProteinGramsTextError.overflow }
        centigrams = scaled

        var fraction: Int64 = 0
        let kept = fractionPart.prefix(2)
        for scalar in kept { fraction = fraction * 10 + Int64(scalar.value - 48) }
        if kept.count == 1 { fraction *= 10 }
        let (withFraction, o4) = centigrams.addingReportingOverflow(fraction)
        guard !o4 else { throw ProteinGramsTextError.overflow }
        centigrams = withFraction

        var rounded = false
        if fractionPart.count > 2 {
            rounded = fractionPart.dropFirst(2).contains { $0 != "0" }
            if fractionPart[2].value - 48 >= 5 {
                let (up, o5) = centigrams.addingReportingOverflow(1)
                guard !o5 else { throw ProteinGramsTextError.overflow }
                centigrams = up
            }
        }
        // "-0" and "-0.00" are zero; any non-zero digit after a minus is a negative value.
        if negative && (integerPart + fractionPart).contains(where: { $0 != "0" }) { throw ProteinGramsTextError.negative }
        return Conversion(centigrams: centigrams, rounded: rounded)
    }

    private static func isASCIIDigit(_ scalar: Unicode.Scalar) -> Bool {
        scalar.isASCII && ("0"..."9").contains(scalar)
    }
}

/// One search result picked for a batch add, exactly as the user saw it. The
/// amount and the reference quantity are the verified values the record will
/// carry; `recordID` is fixed for the session so a retry never adds twice.
public struct SearchSelection: Equatable, Sendable {
    /// Provider-scoped identity of the result row, for duplicate detection only.
    public let itemKey: String
    public let recordID: String
    public let name: String
    public let proteinCentigrams: Int64
    public let quantity: FoodQuantity

    public init(itemKey: String, recordID: String, name: String, proteinCentigrams: Int64, quantity: FoodQuantity) {
        self.itemKey = itemKey
        self.recordID = recordID
        self.name = name
        self.proteinCentigrams = proteinCentigrams
        self.quantity = quantity
    }
}

public enum SearchBatchError: Error, Equatable {
    case emptySelection
    case duplicateSelection(String)
    case duplicateRecordID(String)
    case invalidAmount(String)
    case arithmeticOverflow
}

/// Builds the records for a multi-result add from search. Pure: no provider
/// is consulted, the snapshot the user confirmed is what gets written, and
/// either every selection becomes a record or none does.
public enum SearchRecordBatch {
    /// Checked sum of the selected amounts, for the summary and the write.
    public static func totalCentigrams(_ selections: [SearchSelection]) throws -> Int64 {
        var sum: Int64 = 0
        for selection in selections {
            let (next, overflow) = sum.addingReportingOverflow(selection.proteinCentigrams)
            guard !overflow else { throw SearchBatchError.arithmeticOverflow }
            sum = next
        }
        return sum
    }

    /// Records for `day`, one per selection, in selection order, with
    /// `source: .search` and the verified reference quantity.
    public static func records(for selections: [SearchSelection], on day: CalendarDay) throws -> [FoodRecord] {
        guard !selections.isEmpty else { throw SearchBatchError.emptySelection }
        var itemKeys = Set<String>()
        var recordIDs = Set<String>()
        var records: [FoodRecord] = []
        for selection in selections {
            guard itemKeys.insert(selection.itemKey).inserted else {
                throw SearchBatchError.duplicateSelection(selection.itemKey)
            }
            guard recordIDs.insert(selection.recordID).inserted else {
                throw SearchBatchError.duplicateRecordID(selection.recordID)
            }
            guard selection.proteinCentigrams > 0, let amount = try? ProteinAmount(centigrams: selection.proteinCentigrams) else {
                throw SearchBatchError.invalidAmount(selection.itemKey)
            }
            records.append(try FoodRecord(id: selection.recordID, day: day, name: selection.name,
                                          quantity: selection.quantity, protein: amount, source: .search))
        }
        _ = try totalCentigrams(selections)
        return records
    }
}
