//
//  WholeWord.swift
//  TextOps
//
//  Building the `\b`-anchored pattern for a "whole word" search, without the trap.
//
//  Created by David Sherlock on 8/5/26.
//

import Foundation

/// Whole-word search patterns.
///
/// The trap this exists for: `\b` is a boundary between a word character and a non-word
/// character, so putting it next to a NON-word character inverts its meaning. `\b==\b`
/// cannot match ` a == b ` — both sides of `==` are spaces, so there is no boundary there
/// to find. A naive `"\\b" + escaped + "\\b"` therefore compiles a perfectly valid regex
/// that matches nothing, and a search reports "no results" for `==`, `->`, `+=` or `!`
/// while a replace-all reports success having changed nothing.
///
/// The fix is to anchor only the ends that are actually word characters, so a fully
/// non-word needle degrades to a literal search instead of an unmatchable one.
public enum WholeWord {

    /// True for the characters `\b` treats as word characters (`\w`): letters, digits, `_`.
    public static func isWordCharacter(_ c: Character?) -> Bool {
        guard let c else { return false }
        return c == "_" || c.isLetter || c.isNumber
    }

    /// A whole-word regex pattern for `query`.
    ///
    /// - Parameters:
    ///   - query: The needle.
    ///   - isRegex: True when `query` is already a user-authored pattern. Then the ends are
    ///     anchored unconditionally — the caller's metacharacters make "is this end a word
    ///     character?" unanswerable, and a user writing their own regex can place their own
    ///     boundaries. False escapes `query` as a literal first.
    /// - Returns: A pattern that matches nothing only when the query genuinely appears
    ///   nowhere — or `nil` for an empty query, which has no meaningful whole-word pattern
    ///   (an empty regex does not compile, so returning one would just move the trap).
    public static func pattern(for query: String, isRegex: Bool = false) -> String? {
        guard !query.isEmpty else { return nil }
        if isRegex {
            // The non-capturing group is REQUIRED: alternation binds loosest, so
            // `\bfoo|bar\b` parses as `(\bfoo)|(bar\b)` and silently drops the anchors.
            return "\\b(?:" + query + ")\\b"
        }
        let escaped = NSRegularExpression.escapedPattern(for: query)
        let leading = isWordCharacter(query.first) ? "\\b" : ""
        let trailing = isWordCharacter(query.last) ? "\\b" : ""
        return leading + escaped + trailing
    }

    /// Every whole-word match of `word` in `ns`, left to right, non-overlapping — via
    /// `pattern(for:)`, so a non-word needle (`==`) still finds itself. Empty for an empty word.
    public static func matches(of word: String, in ns: NSString) -> [NSRange] {
        guard let pattern = pattern(for: word), let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        return re.matches(in: ns as String, range: NSRange(location: 0, length: ns.length)).map(\.range)
    }
}
