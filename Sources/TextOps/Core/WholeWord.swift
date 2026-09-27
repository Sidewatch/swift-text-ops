//
//  WholeWord.swift
//  TextOps
//
//  Building the `\b`-anchored pattern for a "whole word" search, without the trap.
//
//  Created by David Sherlock on 8/5/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Whole-word search patterns.
///
/// `\b` next to a NON-word character inverts its meaning: `\b==\b` cannot match ` a == b `.
/// So only the ends that are word characters are anchored, and a fully non-word needle
/// (`==`, `->`, `!`) degrades to a literal search instead of an unmatchable one.
public enum WholeWord {

    /// True for the characters `\b` treats as word characters (`\w`): letters, digits, `_`.
    public static func isWordCharacter(_ c: Character?) -> Bool {
        guard let c else { return false }
        return c == "_" || c.isLetter || c.isNumber
    }

    /// A whole-word regex pattern for `query`, or nil for an empty query.
    ///
    /// With `isRegex`, `query` is a user-authored pattern and both ends are anchored
    /// unconditionally (its metacharacters make "is this end a word character?" unanswerable);
    /// otherwise it is escaped as a literal first.
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
