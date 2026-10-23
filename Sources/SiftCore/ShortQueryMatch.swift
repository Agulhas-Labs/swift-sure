//
// Copyright © Agulhas Labs
//

import Foundation

/// How `strings` matches a short query: one of three characters or fewer (trimmed of whitespace) matches only as a whole word, since as a substring it lists whatever spells those letters inside other words (`OK` inside "Woke up").
struct ShortQueryMatch {
    /// The longest trimmed query read as a whole word.
    static var wordLimit: Int {
        3
    }

    /// Whether `query` is read as a whole word.
    static func isShort(_ query: String) -> Bool {
        let word = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return !word.isEmpty && word.count <= wordLimit
    }

    /// Whether `haystack` holds `query`: anywhere for a longer query, and for a short one only where no letter touches the match on either side (digits, `_`, punctuation, spaces and the string's ends are boundaries).
    static func contains(_ haystack: String, query: String, ignoringCase: Bool, locale: Locale = .current) -> Bool {
        firstRange(in: haystack, query: query, ignoringCase: ignoringCase, locale: locale) != nil
    }

    /// The first place `haystack` holds `query` by the rule of ``contains(_:query:ignoringCase:locale:)``; case is folded by `locale`'s rules, as ordinary literals are.
    static func firstRange(in haystack: String, query: String, ignoringCase: Bool, locale: Locale = .current) -> Range<String.Index>? {
        let options: String.CompareOptions = ignoringCase ? .caseInsensitive : []
        let word = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isShort(query) else {
            return haystack.range(of: query, options: options, range: nil, locale: locale)
        }
        var searched = haystack.startIndex ..< haystack.endIndex
        while let found = haystack.range(of: word, options: options, range: searched, locale: locale) {
            let before = found.lowerBound > haystack.startIndex ? haystack[haystack.index(before: found.lowerBound)] : nil
            let after = found.upperBound < haystack.endIndex ? haystack[found.upperBound] : nil
            if before?.isLetter != true, after?.isLetter != true {
                return found
            }
            guard found.lowerBound < haystack.endIndex else { break }
            searched = haystack.index(after: found.lowerBound) ..< haystack.endIndex
        }
        return nil
    }
}
