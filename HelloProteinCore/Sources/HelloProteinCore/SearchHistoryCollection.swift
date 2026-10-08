import Foundation

public enum SearchHistoryError: Error, Equatable {
    /// The query is empty after trimming; nothing is recorded.
    case blankQuery
    case notFound(String)
    case duplicateID(String)
}

/// Pure rules for the recent-searches list. Display order is the `position`
/// field; the stored array order is not significant. Entries are what the
/// user explicitly searched for: IDs, stored values (including empty or
/// untrimmed legacy values) and legacy identities are never touched except
/// where a function says so.
public enum SearchHistoryCollection {
    /// Display order: lowest position first.
    public static func ordered(_ terms: [SearchTerm]) -> [SearchTerm] {
        terms.sorted { $0.position < $1.position }
    }

    /// Trimmed query, or nil when only whitespace remains.
    public static func normalizedQuery(_ query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The entry an executed search reuses: the first (lowest position) term
    /// whose trimmed stored value equals the trimmed query. Case, synonyms
    /// and inner whitespace are not normalised.
    public static func existing(query: String, in terms: [SearchTerm]) -> SearchTerm? {
        guard let wanted = normalizedQuery(query) else { return nil }
        return ordered(terms).first { $0.value.trimmingCharacters(in: .whitespacesAndNewlines) == wanted }
    }

    /// Records an executed search. An existing exact match moves to the front
    /// and keeps its ID, stored value and legacy identity; otherwise a new
    /// entry with the trimmed query and `newID` is inserted at the front.
    /// The rest keep their relative order and every entry is renumbered
    /// 0... so positions stay contiguous. Other duplicates are left alone.
    public static func recording(query: String, newID: String, in terms: [SearchTerm]) throws -> [SearchTerm] {
        guard let trimmed = normalizedQuery(query) else { throw SearchHistoryError.blankQuery }
        var remaining = ordered(terms)
        let front: SearchTerm
        if let match = existing(query: trimmed, in: terms) {
            remaining.removeAll { $0.id == match.id }
            front = match
        } else {
            guard !terms.contains(where: { $0.id == newID }) else { throw SearchHistoryError.duplicateID(newID) }
            front = try SearchTerm(id: newID, value: trimmed, position: 0)
        }
        return try renumbered([front] + remaining)
    }

    /// Removes exactly one entry by ID. Other entries and positions stay.
    public static func removing(id: String, from terms: [SearchTerm]) throws -> [SearchTerm] {
        guard terms.contains(where: { $0.id == id }) else { throw SearchHistoryError.notFound(id) }
        return terms.filter { $0.id != id }
    }

    /// Positions 0... in the given order; every other field is kept.
    static func renumbered(_ terms: [SearchTerm]) throws -> [SearchTerm] {
        try terms.enumerated().map { offset, term in
            try SearchTerm(id: term.id, value: term.value, position: offset, legacySourceID: term.legacySourceID)
        }
    }
}

extension SearchLanguageSetting {
    /// The raw value the old app stored for a language, which `interpret`
    /// reads back. Writing any other text would make the setting a fallback.
    public static func raw(for language: SearchLanguage) -> String {
        switch language {
        case .korean: return "Korean(한글)"
        case .english: return "English(영어)"
        }
    }

    /// A confirmed (non-fallback) setting for `language`.
    public static func confirmed(_ language: SearchLanguage) -> SearchLanguageSetting {
        interpret(raw: raw(for: language))
    }
}

extension AppState {
    /// Replaces the recent-searches list and re-validates the whole document,
    /// rolling back on failure.
    public mutating func setSearchHistory(_ terms: [SearchTerm]) throws {
        let previous = searchHistory
        searchHistory = terms
        do { try validate() }
        catch {
            searchHistory = previous
            throw error
        }
    }
}
