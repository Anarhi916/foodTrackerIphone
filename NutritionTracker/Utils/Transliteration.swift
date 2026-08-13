import Foundation

let cyrillicToLatin: [Character: String] = [
    "а": "a", "б": "b", "в": "v", "г": "g", "д": "d",
    "е": "e", "ё": "yo", "ж": "zh", "з": "z", "и": "i",
    "й": "y", "к": "k", "л": "l", "м": "m", "н": "n",
    "о": "o", "п": "p", "р": "r", "с": "s", "т": "t",
    "у": "u", "ф": "f", "х": "kh", "ц": "ts", "ч": "ch",
    "ш": "sh", "щ": "shch", "ъ": "", "ы": "y", "ь": "",
    "э": "e", "ю": "yu", "я": "ya"
]

func transliterateToLatin(_ text: String) -> String {
    text.lowercased().map { ch in
        cyrillicToLatin[ch] ?? String(ch)
    }.joined()
}

// Multi-char Latin expansions that diacritic folding does NOT split (ß has no
// decomposition; æ/œ/ø are single letters). Handled explicitly so German/French/Nordic
// input folds too.
private let latinLigatures: [Character: String] = [
    "ß": "ss", "æ": "ae", "œ": "oe", "ø": "o", "đ": "d", "ð": "d",
    "þ": "th", "ł": "l", "ı": "i"
]

/// Folds a string to a diacritic-free, lowercase form so search works across ALL Latin-script
/// languages the app supports (de/es/fr/it/pt/en), the same way transliteration makes it work
/// for Cyrillic (ru/uk). Examples: "Käse" → "kase", "jamón" → "jamon", "Straße" → "strasse".
func foldDiacritics(_ text: String) -> String {
    let expanded = String(text.lowercased().flatMap { latinLigatures[$0] ?? String($0) })
    return expanded.folding(options: .diacriticInsensitive, locale: nil)
}

/// Ranks saved-food suggestions so the best matches survive the top-N cap. Plain substring
/// matching + prefix(5) buried short names like "помидор"/"огурец" behind long dish names
/// that merely contain the word, so a whole-word product only appeared after typing almost
/// all of it.
///
/// Matching is script-agnostic: each field and the query are compared in three normalized
/// forms so ALL supported languages match as forgivingly as Russian —
///   1) raw lowercase (exact input, any script),
///   2) Cyrillic→Latin transliteration (ru/uk typed in Latin, e.g. "ogurec"),
///   3) diacritic-folded (de/es/fr/it/pt, e.g. "kase" finds "Käse").
///
/// Scoring (lower = better), best across all forms and both keys:
///   0 exact · 1 startsWith · 2 word-boundary prefix · 3 substring anywhere.
/// Ties break by shorter key (a bare "огурец" outranks a long salad name), then alphabetically.
func rankFoodSuggestions<T>(
    query: String,
    items: [T],
    keyOriginal: (T) -> String,
    keyEn: (T) -> String,
    limit: Int = 5
) -> [T] {
    let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    guard !q.isEmpty else { return [] }
    let needles = Array(Set([q, transliterateToLatin(q), foldDiacritics(q)].filter { !$0.isEmpty }))
    let separators = CharacterSet(charactersIn: " ,()\"/-")

    func score(_ field: String) -> Int {
        let forms = Array(Set([field.lowercased(), transliterateToLatin(field), foldDiacritics(field)]))
        var best = Int.max
        for f in forms {
            for needle in needles {
                if f == needle { return 0 }
                if f.hasPrefix(needle) { best = min(best, 1); continue }
                let tokens = f.components(separatedBy: separators)
                if tokens.contains(where: { $0.hasPrefix(needle) }) { best = min(best, 2); continue }
                if f.contains(needle) { best = min(best, 3) }
            }
        }
        return best
    }

    return items
        .compactMap { item -> (T, Int, Int)? in
            let s = min(score(keyOriginal(item)), score(keyEn(item)))
            return s == Int.max ? nil : (item, s, keyOriginal(item).count)
        }
        .sorted { a, b in
            if a.1 != b.1 { return a.1 < b.1 }
            if a.2 != b.2 { return a.2 < b.2 }
            return keyOriginal(a.0).lowercased() < keyOriginal(b.0).lowercased()
        }
        .prefix(limit)
        .map { $0.0 }
}
