import Foundation

/// A calendar date without a time zone. Persist this shape as `YYYY-MM-DD`.
///
/// Only proleptic Gregorian dates with ASCII digits and years 0001...9999 are
/// representable. A stored day never changes when the device time zone changes;
/// only `today(now:timeZone:)` depends on the current clock and zone.
public struct CalendarDay: Codable, Hashable, Comparable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    private static let utcGregorian: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    public init(year: Int, month: Int, day: Int) throws {
        guard (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day) else {
            throw RecordDomainError.invalidDay
        }
        let calendar = Self.utcGregorian
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day
        )
        guard let date = calendar.date(from: components) else {
            throw RecordDomainError.invalidDay
        }
        let normalized = calendar.dateComponents([.year, .month, .day], from: date)
        guard normalized.year == year, normalized.month == month, normalized.day == day else {
            throw RecordDomainError.invalidDay
        }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Strict `YYYY-MM-DD` parser: exactly ten characters, ASCII digits only,
    /// no signs, no whitespace, no localized digits.
    public init(iso8601 value: String) throws {
        let scalars = Array(value.unicodeScalars)
        guard scalars.count == 10, scalars[4] == "-", scalars[7] == "-" else {
            throw RecordDomainError.invalidDay
        }
        func digits(_ range: Range<Int>) throws -> Int {
            var result = 0
            for index in range {
                let scalar = scalars[index]
                guard scalar.isASCII, ("0"..."9").contains(scalar) else {
                    throw RecordDomainError.invalidDay
                }
                result = result * 10 + Int(scalar.value - 48)
            }
            return result
        }
        try self.init(year: digits(0..<4), month: digits(5..<7), day: digits(8..<10))
    }

    public var iso8601: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(iso8601: container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(iso8601)
    }

    public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    /// The Gregorian day containing `now` in `timeZone`, regardless of the
    /// device calendar setting.
    public static func today(now: Date, timeZone: TimeZone) -> CalendarDay? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        let components = calendar.dateComponents([.year, .month, .day], from: now)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return nil
        }
        return try? CalendarDay(year: year, month: month, day: day)
    }

    /// Pure calendar arithmetic; independent of the device time zone. nil
    /// when the result leaves the supported range (years 1–9999 CE): a day
    /// before 0001-01-01 is never reported as a wrapped-around BCE date.
    public func adding(days: Int) -> CalendarDay? {
        let calendar = Self.utcGregorian
        guard let base = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              let shifted = calendar.date(byAdding: .day, value: days, to: base) else {
            return nil
        }
        let components = calendar.dateComponents([.era, .year, .month, .day], from: shifted)
        guard components.era == 1, let year = components.year, let month = components.month, let day = components.day else {
            return nil
        }
        return try? CalendarDay(year: year, month: month, day: day)
    }

    /// Start of this day in `timeZone`, for UI date pickers only.
    public func startOfDay(in timeZone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    /// 1 = Sunday ... 7 = Saturday, Gregorian.
    public var weekdayIndex: Int {
        let calendar = Self.utcGregorian
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
            return 1
        }
        return calendar.component(.weekday, from: date)
    }
}

/// Protein is stored as integer centigrams so 0.01 g is exact on every platform.
public struct ProteinAmount: Codable, Hashable, Comparable, Sendable {
    public let centigrams: Int64

    public init(centigrams: Int64) throws {
        guard centigrams >= 0 else { throw RecordDomainError.negativeProtein }
        self.centigrams = centigrams
    }

    public static let zero = try! ProteinAmount(centigrams: 0)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(centigrams: container.decode(Int64.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(centigrams)
    }

    public static func < (lhs: ProteinAmount, rhs: ProteinAmount) -> Bool {
        lhs.centigrams < rhs.centigrams
    }
}

public enum ProteinInputError: Error, Equatable {
    case empty
    case notANumber
    case groupingSeparatorNotAllowed
    case tooManyFractionDigits
    case notPositive
    case overflow
}

/// Strict text-to-amount conversion for user input. The whole string must be
/// ASCII digits with at most one locale decimal separator; signs, exponents,
/// whitespace inside, NaN, infinity and grouping separators are rejected.
public enum ProteinInput {
    /// Food entry input: strictly positive.
    public static func parse(_ text: String, decimalSeparator: String = ".") throws -> ProteinAmount {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ProteinInputError.empty }
        let centigrams = try parseMagnitude(trimmed, decimalSeparator: decimalSeparator)
        guard centigrams > 0 else { throw ProteinInputError.notPositive }
        return try ProteinAmount(centigrams: centigrams)
    }

    /// Daily-total input for legacy days. Zero and a leading minus are allowed
    /// because imported totals of 0 and totals that went negative after a
    /// detail was deleted are legitimate stored states that must stay editable.
    public static func parseSignedTotal(_ text: String, decimalSeparator: String = ".") throws -> Int64 {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ProteinInputError.empty }
        let negative = trimmed.hasPrefix("-")
        let magnitudeText = negative ? String(trimmed.dropFirst()) : trimmed
        guard !magnitudeText.isEmpty, !magnitudeText.hasPrefix("-") else { throw ProteinInputError.notANumber }
        let magnitude = try parseMagnitude(magnitudeText, decimalSeparator: decimalSeparator)
        return negative ? -magnitude : magnitude
    }

    private static func parseMagnitude(_ trimmed: String, decimalSeparator: String) throws -> Int64 {
        let separator = decimalSeparator.isEmpty ? "." : decimalSeparator
        let otherSeparator = separator == "." ? "," : "."
        if trimmed.contains(otherSeparator) { throw ProteinInputError.groupingSeparatorNotAllowed }

        let parts = trimmed.components(separatedBy: separator)
        guard parts.count <= 2 else { throw ProteinInputError.notANumber }
        let integerPart = parts[0]
        let fractionPart = parts.count == 2 ? parts[1] : ""
        guard !integerPart.isEmpty || !fractionPart.isEmpty else { throw ProteinInputError.notANumber }
        guard integerPart.unicodeScalars.allSatisfy(Self.isASCIIDigit),
              fractionPart.unicodeScalars.allSatisfy(Self.isASCIIDigit) else {
            throw ProteinInputError.notANumber
        }
        guard fractionPart.count <= 2 else { throw ProteinInputError.tooManyFractionDigits }

        var grams: Int64 = 0
        for scalar in integerPart.unicodeScalars {
            let digit = Int64(scalar.value - 48)
            let (multiplied, overflow1) = grams.multipliedReportingOverflow(by: 10)
            let (added, overflow2) = multiplied.addingReportingOverflow(digit)
            guard !overflow1, !overflow2 else { throw ProteinInputError.overflow }
            grams = added
        }
        var fraction: Int64 = 0
        for scalar in fractionPart.unicodeScalars { fraction = fraction * 10 + Int64(scalar.value - 48) }
        if fractionPart.count == 1 { fraction *= 10 }

        let (scaled, overflow3) = grams.multipliedReportingOverflow(by: 100)
        let (centigrams, overflow4) = scaled.addingReportingOverflow(fraction)
        guard !overflow3, !overflow4 else { throw ProteinInputError.overflow }
        return centigrams
    }

    /// Locale-independent canonical text (`12`, `12.5`, `-3.25`).
    public static func format(centigrams: Int64, decimalSeparator: String = ".") -> String {
        let sign = centigrams < 0 ? "-" : ""
        let magnitude = centigrams.magnitude
        let whole = magnitude / 100
        let fraction = magnitude % 100
        if fraction == 0 { return "\(sign)\(whole)" }
        if fraction % 10 == 0 { return "\(sign)\(whole)\(decimalSeparator)\(fraction / 10)" }
        return "\(sign)\(whole)\(decimalSeparator)" + String(format: "%02llu", fraction)
    }

    private static func isASCIIDigit(_ scalar: Unicode.Scalar) -> Bool {
        scalar.isASCII && ("0"..."9").contains(scalar)
    }
}

public struct FoodQuantity: Codable, Equatable, Sendable {
    public enum Unit: String, Codable, Sendable {
        case gram
        case ounce
        case milliliter
        case serving
        case piece
    }

    /// A decimal string is preserved for portable, lossless entry and display.
    public let value: String
    public let unit: Unit

    public init(value: String, unit: Unit) throws {
        guard Self.isCanonicalPositiveDecimal(value) else {
            throw RecordDomainError.invalidQuantity
        }
        self.value = value
        self.unit = unit
    }

    private enum CodingKeys: String, CodingKey { case value, unit }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            value: container.decode(String.self, forKey: .value),
            unit: container.decode(Unit.self, forKey: .unit)
        )
    }

    /// ASCII digits with at most one `.`; must be greater than zero.
    static func isCanonicalPositiveDecimal(_ text: String) -> Bool {
        let parts = text.components(separatedBy: ".")
        guard parts.count <= 2, !text.isEmpty else { return false }
        guard text.unicodeScalars.allSatisfy({ $0 == "." || ($0.isASCII && ("0"..."9").contains($0)) }) else {
            return false
        }
        guard !parts[0].isEmpty || (parts.count == 2 && !parts[1].isEmpty) else { return false }
        return text.unicodeScalars.contains { ("1"..."9").contains($0) }
    }
}


/// Limits for the values a calculation basis stores: positive decimals with
/// at most 18 significant and 9 fraction digits. Older `FoodQuantity` values
/// are not subject to these limits; only a basis is.
public enum CalculationBasisLimits {
    public static let maxSignificantDigits = 18
    public static let maxFractionDigits = 9

    static func check(_ text: String, field: String) throws -> PortionDecimal {
        let decimal: PortionDecimal
        do { decimal = try PortionDecimal(canonical: text) }
        catch { throw RecordDomainError.invalidBasis("\(field): not a positive decimal") }
        guard decimal.significantDigitCount <= maxSignificantDigits else {
            throw RecordDomainError.invalidBasis("\(field): more than \(maxSignificantDigits) significant digits")
        }
        guard decimal.fractionDigitCount <= maxFractionDigits else {
            throw RecordDomainError.invalidBasis("\(field): more than \(maxFractionDigits) fraction digits")
        }
        return decimal
    }
}

/// The immutable data a record's protein was computed from: the provider's
/// (or the user's) protein per reference amount. The amount eaten lives in
/// `FoodRecord.quantity`; changing it recomputes `protein` from this basis
/// and never from a previously rounded result. Never a health or accuracy
/// claim; a provider snapshot is what the provider said at the time.
public struct CalculationBasis: Codable, Equatable, Sendable {
    public enum Origin: String, Codable, Sendable {
        case providerSnapshot
        case userDefined
    }

    /// Provider identity of the row the snapshot came from. Identifiers only;
    /// never request URLs or keys.
    public struct ProviderReference: Codable, Equatable, Sendable {
        public let providerID: String
        public let dataVersion: String
        public let itemID: String

        public init(providerID: String, dataVersion: String, itemID: String) throws {
            for (name, value) in [("providerID", providerID), ("dataVersion", dataVersion), ("itemID", itemID)]
            where value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw RecordDomainError.invalidBasis("\(name) is empty")
            }
            self.providerID = providerID
            self.dataVersion = dataVersion
            self.itemID = itemID
        }

        private enum CodingKeys: String, CodingKey { case providerID, dataVersion, itemID }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                providerID: container.decode(String.self, forKey: .providerID),
                dataVersion: container.decode(String.self, forKey: .dataVersion),
                itemID: container.decode(String.self, forKey: .itemID)
            )
        }
    }

    /// Protein in grams per `referenceQuantity`, as a verified decimal string
    /// with its full precision (`1.005`, not a pre-rounded `1.01`).
    public let proteinGramsText: String
    public let referenceQuantity: FoodQuantity
    public let origin: Origin
    /// Present exactly when `origin` is `providerSnapshot`.
    public let provider: ProviderReference?

    public init(proteinGramsText: String, referenceQuantity: FoodQuantity, origin: Origin, provider: ProviderReference?) throws {
        let protein = try CalculationBasisLimits.check(proteinGramsText, field: "proteinGramsText")
        let reference = try CalculationBasisLimits.check(referenceQuantity.value, field: "referenceQuantity")
        switch origin {
        case .providerSnapshot:
            guard provider != nil else { throw RecordDomainError.invalidBasis("providerSnapshot without provider") }
        case .userDefined:
            guard provider == nil else { throw RecordDomainError.invalidBasis("userDefined with provider") }
        }
        self.proteinGramsText = protein.canonical
        self.referenceQuantity = try FoodQuantity(value: reference.canonical, unit: referenceQuantity.unit)
        self.origin = origin
        self.provider = provider
    }

    public static func providerSnapshot(proteinGramsText: String, referenceQuantity: FoodQuantity,
                                        providerID: String, dataVersion: String, itemID: String) throws -> CalculationBasis {
        try CalculationBasis(proteinGramsText: proteinGramsText, referenceQuantity: referenceQuantity, origin: .providerSnapshot,
                             provider: ProviderReference(providerID: providerID, dataVersion: dataVersion, itemID: itemID))
    }

    public static func userDefined(proteinGramsText: String, referenceQuantity: FoodQuantity) throws -> CalculationBasis {
        try CalculationBasis(proteinGramsText: proteinGramsText, referenceQuantity: referenceQuantity, origin: .userDefined, provider: nil)
    }

    /// The protein this basis yields for `quantity`; throws on unit mismatch,
    /// a result that rounds to zero, or overflow.
    public func protein(for quantity: FoodQuantity) throws -> PortionCalculation.Result {
        try PortionCalculation.centigrams(proteinGramsText: proteinGramsText, referenceQuantity: referenceQuantity, actualQuantity: quantity)
    }

    /// True when the amount editor can start from the reference amount as is.
    public var isReferenceEditable: Bool { PortionInput.isEditableQuantityValue(referenceQuantity.value) }

    private enum CodingKeys: String, CodingKey { case proteinGramsText, referenceQuantity, origin, provider }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            proteinGramsText: container.decode(String.self, forKey: .proteinGramsText),
            referenceQuantity: container.decode(FoodQuantity.self, forKey: .referenceQuantity),
            origin: container.decode(Origin.self, forKey: .origin),
            provider: container.decodeIfPresent(ProviderReference.self, forKey: .provider)
        )
    }
}

/// An immutable food entry. Change it only through the `with…` methods, which
/// keep the identity, day and source and re-validate the result.
///
/// With a `calculationBasis` (schema 3 search records) `quantity` is the
/// amount actually eaten and `protein` is exactly what the basis yields for
/// it; the invariants are checked on construction and on decode, and a
/// mismatch is a corrupt record, never silently repaired.
public struct FoodRecord: Codable, Equatable, Identifiable, Sendable {
    public enum Source: String, Codable, Sendable {
        case manual
        case favorite
        case search
        case labelScan
        case naturalLanguage
        case legacy
    }

    public let id: String
    public let day: CalendarDay
    public let name: String?
    public let quantity: FoodQuantity?
    public let protein: ProteinAmount
    public let source: Source
    /// Original identity in the old store, e.g. a Realm ObjectId string.
    public let legacySourceID: String?
    /// nil for every record written before schema 3 and for manual, favorite
    /// and legacy records; those keep their stored quantity and protein as is.
    public let calculationBasis: CalculationBasis?

    public init(
        id: String,
        day: CalendarDay,
        name: String?,
        quantity: FoodQuantity?,
        protein: ProteinAmount,
        source: Source,
        legacySourceID: String? = nil,
        calculationBasis: CalculationBasis? = nil
    ) throws {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RecordDomainError.emptyID
        }
        guard protein > .zero else { throw RecordDomainError.zeroProtein }
        if let basis = calculationBasis {
            guard source == .search else { throw RecordDomainError.invalidBasis("source \(source.rawValue) cannot carry a basis") }
            guard let quantity else { throw RecordDomainError.invalidBasis("basis without quantity") }
            guard quantity.unit == basis.referenceQuantity.unit else {
                throw RecordDomainError.invalidBasis("quantity unit \(quantity.unit.rawValue) differs from reference \(basis.referenceQuantity.unit.rawValue)")
            }
            guard PortionInput.isEditableQuantityValue(quantity.value) else {
                throw RecordDomainError.invalidBasis("quantity \(quantity.value) outside the amount input range")
            }
            let computed: PortionCalculation.Result
            do { computed = try basis.protein(for: quantity) }
            catch { throw RecordDomainError.invalidBasis("protein cannot be computed: \(error)") }
            guard computed.centigrams == protein.centigrams else {
                throw RecordDomainError.invalidBasis("protein \(protein.centigrams) differs from computed \(computed.centigrams)")
            }
        }
        let normalizedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = id
        self.day = day
        self.name = normalizedName?.isEmpty == true ? nil : normalizedName
        self.quantity = quantity
        self.protein = protein
        self.source = source
        self.legacySourceID = legacySourceID
        self.calculationBasis = calculationBasis
    }

    /// A search record computed from `basis` for `quantity`: the protein is
    /// derived here, so it can never disagree with the basis.
    public init(id: String, day: CalendarDay, name: String?, quantity: FoodQuantity, basis: CalculationBasis) throws {
        let computed: PortionCalculation.Result
        do { computed = try basis.protein(for: quantity) }
        catch let error as PortionCalculationError { throw RecordDomainError.portion(error) }
        try self.init(id: id, day: day, name: name, quantity: quantity, protein: ProteinAmount(centigrams: computed.centigrams),
                      source: .search, legacySourceID: nil, calculationBasis: basis)
    }

    /// Returns a validated copy with only the given fields changed. A protein
    /// change on a record with a basis is refused: a provider snapshot cannot
    /// stay attached to a value it did not produce, and dropping it is an
    /// explicit decision (`withDirectProtein`). The same protein and a name
    /// change keep the basis untouched.
    public func withChanges(name: String?? = nil, protein: ProteinAmount? = nil) throws -> FoodRecord {
        if let protein, protein != self.protein, calculationBasis != nil {
            // Never silently: the caller decides between `withQuantity` and
            // the explicit `withDirectProtein`, which replaces the basis.
            throw RecordDomainError.proteinLockedByBasis
        }
        return try FoodRecord(
            id: id,
            day: day,
            name: name ?? self.name,
            quantity: quantity,
            protein: protein ?? self.protein,
            source: source,
            legacySourceID: legacySourceID,
            calculationBasis: calculationBasis
        )
    }

    /// Changes the amount eaten and recomputes the protein from the stored
    /// basis. Only records with a basis can do this; older records keep
    /// their saved reference amount.
    public func withQuantity(_ quantity: FoodQuantity, name: String?? = nil) throws -> FoodRecord {
        guard let basis = calculationBasis else { throw RecordDomainError.quantityNotEditable }
        guard quantity.unit == basis.referenceQuantity.unit else { throw RecordDomainError.portion(.unitMismatch) }
        guard PortionInput.isEditableQuantityValue(quantity.value) else { throw RecordDomainError.invalidQuantity }
        let computed: PortionCalculation.Result
        do { computed = try basis.protein(for: quantity) }
        catch let error as PortionCalculationError { throw RecordDomainError.portion(error) }
        return try FoodRecord(id: id, day: day, name: name ?? self.name, quantity: quantity,
                              protein: ProteinAmount(centigrams: computed.centigrams), source: source,
                              legacySourceID: legacySourceID, calculationBasis: basis)
    }

    /// The explicit "enter the protein yourself" edit for a record with a
    /// basis: the current quantity is kept and becomes the reference of a new
    /// user-defined basis whose protein is the entered value. Provider
    /// identifiers are dropped. Without a basis this is a plain protein edit.
    public func withDirectProtein(_ protein: ProteinAmount, name: String?? = nil) throws -> FoodRecord {
        guard calculationBasis != nil, let quantity else {
            return try FoodRecord(id: id, day: day, name: name ?? self.name, quantity: quantity, protein: protein,
                                  source: source, legacySourceID: legacySourceID, calculationBasis: nil)
        }
        let basis = try CalculationBasis.userDefined(proteinGramsText: ProteinInput.format(centigrams: protein.centigrams),
                                                     referenceQuantity: quantity)
        return try FoodRecord(id: id, day: day, name: name ?? self.name, quantity: quantity, protein: protein,
                              source: source, legacySourceID: legacySourceID, calculationBasis: basis)
    }

    private enum CodingKeys: String, CodingKey {
        case id, day, name, quantity, protein, source, legacySourceID, calculationBasis
    }

    /// Set by a schema-2 reader so a document that claims schema 2 but carries
    /// a basis is reported as corrupt instead of silently accepted.
    public static let decodingSchemaVersionKey = CodingUserInfoKey(rawValue: "HelloProteinCore.decodingSchemaVersion")!

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let version = decoder.userInfo[Self.decodingSchemaVersionKey] as? Int, version < 3,
           container.contains(.calculationBasis) {
            throw DecodingError.dataCorrupted(.init(codingPath: container.codingPath,
                                                    debugDescription: "calculationBasis is not part of schema \(version)"))
        }
        try self.init(
            id: container.decode(String.self, forKey: .id),
            day: container.decode(CalendarDay.self, forKey: .day),
            name: container.decodeIfPresent(String.self, forKey: .name),
            quantity: container.decodeIfPresent(FoodQuantity.self, forKey: .quantity),
            protein: container.decode(ProteinAmount.self, forKey: .protein),
            source: container.decode(Source.self, forKey: .source),
            legacySourceID: container.decodeIfPresent(String.self, forKey: .legacySourceID),
            calculationBasis: container.decodeIfPresent(CalculationBasis.self, forKey: .calculationBasis)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(day, forKey: .day)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(quantity, forKey: .quantity)
        try container.encode(protein, forKey: .protein)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(legacySourceID, forKey: .legacySourceID)
        try container.encodeIfPresent(calculationBasis, forKey: .calculationBasis)
    }
}

/// Audit information for a legacy daily total that was imported as a signed
/// adjustment. It separates what the old app stored from what the user later
/// changed. It is never presented as a food record.
public struct LegacyAggregate: Codable, Equatable, Sendable {
    public let sourceID: String
    public let importedTotalCentigrams: Int64
    public let importedDetailSumCentigrams: Int64
    public let originalLabel: String?
    public let originalInstant: String?
    /// Set when the user replaced the day's total after migration.
    public private(set) var userEditedTotalCentigrams: Int64?

    public init(
        sourceID: String,
        importedTotalCentigrams: Int64,
        importedDetailSumCentigrams: Int64,
        originalLabel: String?,
        originalInstant: String?,
        userEditedTotalCentigrams: Int64? = nil
    ) throws {
        guard !sourceID.isEmpty else { throw RecordDomainError.emptyID }
        self.sourceID = sourceID
        self.importedTotalCentigrams = importedTotalCentigrams
        self.importedDetailSumCentigrams = importedDetailSumCentigrams
        self.originalLabel = originalLabel
        self.originalInstant = originalInstant
        self.userEditedTotalCentigrams = userEditedTotalCentigrams
    }

    fileprivate mutating func markUserEdited(total: Int64) {
        userEditedTotalCentigrams = total
    }

    private enum CodingKeys: String, CodingKey {
        case sourceID, importedTotalCentigrams, importedDetailSumCentigrams
        case originalLabel, originalInstant, userEditedTotalCentigrams
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            sourceID: container.decode(String.self, forKey: .sourceID),
            importedTotalCentigrams: container.decode(Int64.self, forKey: .importedTotalCentigrams),
            importedDetailSumCentigrams: container.decode(Int64.self, forKey: .importedDetailSumCentigrams),
            originalLabel: container.decodeIfPresent(String.self, forKey: .originalLabel),
            originalInstant: container.decodeIfPresent(String.self, forKey: .originalInstant),
            userEditedTotalCentigrams: container.decodeIfPresent(Int64.self, forKey: .userEditedTotalCentigrams)
        )
    }
}

public struct DailyLog: Codable, Equatable, Sendable {
    public enum DetailState: String, Codable, Sendable {
        case empty
        case detailed
        case legacyTotalOnly
        case legacyTotalWithNewDetails
    }

    public let day: CalendarDay
    public private(set) var records: [FoodRecord]

    /// Signed adjustment preserved from the old app. For aggregate-only days it
    /// is the whole legacy total; for surviving details it is old total minus
    /// their sum. It is never presented as a food record.
    public private(set) var legacyAdjustmentCentigrams: Int64?

    /// Present when the adjustment came from a migration; nil for schema 1
    /// files that only stored the adjustment.
    public private(set) var legacyAggregate: LegacyAggregate?

    public init(
        day: CalendarDay,
        records: [FoodRecord] = [],
        legacyAdjustmentCentigrams: Int64? = nil,
        legacyAggregate: LegacyAggregate? = nil
    ) throws {
        if legacyAggregate != nil && legacyAdjustmentCentigrams == nil {
            throw RecordDomainError.legacyAggregateWithoutAdjustment
        }
        self.day = day
        self.records = []
        self.legacyAdjustmentCentigrams = legacyAdjustmentCentigrams
        self.legacyAggregate = legacyAggregate
        for record in records { try add(record) }
        _ = try totalProteinCentigrams()
    }

    private enum CodingKeys: String, CodingKey {
        case day, records, legacyAdjustmentCentigrams, legacyAggregate
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            day: container.decode(CalendarDay.self, forKey: .day),
            records: container.decode([FoodRecord].self, forKey: .records),
            legacyAdjustmentCentigrams: container.decodeIfPresent(
                Int64.self,
                forKey: .legacyAdjustmentCentigrams
            ),
            legacyAggregate: container.decodeIfPresent(LegacyAggregate.self, forKey: .legacyAggregate)
        )
    }

    public var detailState: DetailState {
        switch (legacyAdjustmentCentigrams, records.isEmpty) {
        case (nil, true): return .empty
        case (nil, false): return .detailed
        case (.some, true): return .legacyTotalOnly
        case (.some, false): return .legacyTotalWithNewDetails
        }
    }

    public var hasLegacyTotal: Bool { legacyAdjustmentCentigrams != nil }

    public func record(id: String) -> FoodRecord? {
        records.first { $0.id == id }
    }

    public mutating func add(_ record: FoodRecord) throws {
        guard record.day == day else { throw RecordDomainError.dayMismatch }
        guard !records.contains(where: { $0.id == record.id }) else {
            throw RecordDomainError.duplicateRecordID
        }
        records.append(record)
        do { _ = try totalProteinCentigrams() }
        catch {
            records.removeLast()
            throw error
        }
    }

    public mutating func update(_ record: FoodRecord) throws {
        guard record.day == day else { throw RecordDomainError.dayMismatch }
        guard let index = records.firstIndex(where: { $0.id == record.id }) else {
            throw RecordDomainError.recordNotFound
        }
        let previous = records[index]
        records[index] = record
        do { _ = try totalProteinCentigrams() }
        catch {
            records[index] = previous
            throw error
        }
    }

    @discardableResult
    public mutating func delete(id: String) throws -> FoodRecord {
        guard let index = records.firstIndex(where: { $0.id == id }) else {
            throw RecordDomainError.recordNotFound
        }
        return records.remove(at: index)
    }

    public mutating func setLegacyAdjustment(_ centigrams: Int64?) throws {
        if centigrams == nil && legacyAggregate != nil {
            throw RecordDomainError.legacyAggregateWithoutAdjustment
        }
        let previous = legacyAdjustmentCentigrams
        legacyAdjustmentCentigrams = centigrams
        do { _ = try totalProteinCentigrams() }
        catch {
            legacyAdjustmentCentigrams = previous
            throw error
        }
    }

    /// Replaces the day's total by recomputing the legacy adjustment as
    /// `total - sum(records)`. Only allowed on days that carry a legacy total.
    public mutating func setLegacyDailyTotal(_ totalCentigrams: Int64) throws {
        guard legacyAdjustmentCentigrams != nil else { throw RecordDomainError.noLegacyTotal }
        let detailSum = try recordSumCentigrams()
        let (adjustment, overflow) = totalCentigrams.subtractingReportingOverflow(detailSum)
        guard !overflow else { throw RecordDomainError.arithmeticOverflow }
        let previousAdjustment = legacyAdjustmentCentigrams
        let previousAggregate = legacyAggregate
        legacyAdjustmentCentigrams = adjustment
        legacyAggregate?.markUserEdited(total: totalCentigrams)
        do { _ = try totalProteinCentigrams() }
        catch {
            legacyAdjustmentCentigrams = previousAdjustment
            legacyAggregate = previousAggregate
            throw error
        }
    }

    public func recordSumCentigrams() throws -> Int64 {
        var sum: Int64 = 0
        for record in records {
            let result = sum.addingReportingOverflow(record.protein.centigrams)
            guard !result.overflow else { throw RecordDomainError.arithmeticOverflow }
            sum = result.partialValue
        }
        return sum
    }

    public func totalProteinCentigrams() throws -> Int64 {
        let sum = try recordSumCentigrams()
        let result = (legacyAdjustmentCentigrams ?? 0).addingReportingOverflow(sum)
        guard !result.overflow else { throw RecordDomainError.arithmeticOverflow }
        return result.partialValue
    }
}

public struct ProteinGoal: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let effectiveFrom: CalendarDay
    public let amount: ProteinAmount

    public init(id: String, effectiveFrom: CalendarDay, amount: ProteinAmount) throws {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RecordDomainError.emptyID
        }
        guard amount > .zero else { throw RecordDomainError.zeroProtein }
        self.id = id
        self.effectiveFrom = effectiveFrom
        self.amount = amount
    }

    private enum CodingKeys: String, CodingKey { case id, effectiveFrom, amount }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(String.self, forKey: .id),
            effectiveFrom: container.decode(CalendarDay.self, forKey: .effectiveFrom),
            amount: container.decode(ProteinAmount.self, forKey: .amount)
        )
    }
}

public enum GoalHistory {
    /// Goals must have unique IDs and unique effective days. Two goals on the
    /// same day are ambiguous and are rejected instead of picked by ID order.
    public static func validate(_ goals: [ProteinGoal]) throws {
        var ids = Set<String>()
        var days = Set<CalendarDay>()
        for goal in goals {
            guard ids.insert(goal.id).inserted else { throw RecordDomainError.duplicateGoalID(goal.id) }
            guard days.insert(goal.effectiveFrom).inserted else {
                throw RecordDomainError.duplicateGoalEffectiveDate(goal.effectiveFrom)
            }
        }
    }

    /// The goal in effect on `day`, or nil when no goal history covers it.
    public static func goal(on day: CalendarDay, from goals: [ProteinGoal]) throws -> ProteinGoal? {
        try validate(goals)
        return goals
            .filter { $0.effectiveFrom <= day }
            .max { $0.effectiveFrom < $1.effectiveFrom }
    }

    /// A user change replaces any goal that already starts on the same day.
    public static func replacingGoal(on day: CalendarDay, with goal: ProteinGoal, in goals: [ProteinGoal]) throws -> [ProteinGoal] {
        guard goal.effectiveFrom == day else { throw RecordDomainError.dayMismatch }
        var result = goals.filter { $0.effectiveFrom != day }
        result.append(goal)
        result.sort { $0.effectiveFrom < $1.effectiveFrom }
        try validate(result)
        return result
    }
}

public enum RecordDomainError: Error, Equatable {
    case invalidDay
    case emptyID
    case zeroProtein
    case negativeProtein
    case invalidQuantity
    case dayMismatch
    case duplicateRecordID
    case recordNotFound
    case arithmeticOverflow
    case noLegacyTotal
    case legacyAggregateWithoutAdjustment
    case duplicateGoalID(String)
    case duplicateGoalEffectiveDate(CalendarDay)
    /// A calculation basis, or a record carrying one, breaks its invariants.
    case invalidBasis(String)
    /// The amount eaten cannot be changed on a record without a basis.
    case quantityNotEditable
    /// The protein of a record with a basis is a computed value; it changes
    /// through the amount or through the explicit direct-protein edit.
    case proteinLockedByBasis
    case portion(PortionCalculationError)
}

public protocol RecordRepository {
    func log(for day: CalendarDay) throws -> DailyLog
    func save(_ log: DailyLog) throws
}
