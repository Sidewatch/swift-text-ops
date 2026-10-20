//
//  TextSearch.swift
//  TextOps
//
//  Find and replace over a text: every match, the next and previous one, and what Replace writes.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Find and replace as pure functions over a text, for an editor's find bar and its selection commands.
///
/// Matches never overlap and are found left to right. A plain search is NSString comparison, so the
/// caller's options decide canonical equivalence (`.literal` turns it off) and case. A regular
/// expression never yields a ZERO-WIDTH match (`x*` matches nothing at all rather than the empty string
/// everywhere), so the count, Find Next, Find Previous and Replace All always agree, and Find Next always
/// moves. In regex mode a replacement is a template: `$1` is the first capture group.
public enum TextSearch {
    /// Every match of the plain `needle` in `text` under `options`, non-overlapping, left to right.
    public static func ranges(of needle: String, in text: NSString, options: NSString.CompareOptions = []) -> [NSRange] {
        guard !needle.isEmpty else { return [] }
        var found: [NSRange] = []
        var position = 0
        while position < text.length {
            let range = text.range(of: needle, options: options, range: NSRange(location: position, length: text.length - position))
            if range.location == NSNotFound { break }
            found.append(range)
            position = NSMaxRange(range)
        }
        return found
    }

    /// Every match of the find bar's query: `query` as plain text, or as a regular expression when
    /// `regex` (an invalid pattern matches nothing), case-folded unless `caseSensitive`.
    public static func ranges(of query: String, in text: NSString, caseSensitive: Bool, regex: Bool) -> [NSRange] {
        guard !query.isEmpty else { return [] }
        if regex {
            guard let expression = expression(query, caseSensitive: caseSensitive) else { return [] }
            return expression.matches(in: text as String, range: NSRange(location: 0, length: text.length)).map(\.range).filter {
                $0.length > 0
            }
        }
        return ranges(of: query, in: text, options: caseSensitive ? [] : [.caseInsensitive])
    }

    /// The first match starting at or after `location`, else the first in the text (the search wraps);
    /// nil when there is none.
    public static func next(_ query: String, from location: Int, in text: NSString, caseSensitive: Bool, regex: Bool) -> NSRange? {
        guard !query.isEmpty else { return nil }
        let start = max(0, min(location, text.length))
        if regex {
            guard let expression = expression(query, caseSensitive: caseSensitive) else { return nil }
            return firstMatch(expression, in: text, from: start) ?? firstMatch(expression, in: text, from: 0)
        }
        let options: NSString.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        let after = text.range(of: query, options: options, range: NSRange(location: start, length: text.length - start))
        if after.location != NSNotFound { return after }
        let any = text.range(of: query, options: options, range: NSRange(location: 0, length: text.length))
        return any.location == NSNotFound ? nil : any
    }

    /// The last match ending at or before `location`, else the last in the text (the search wraps);
    /// nil when there is none.
    public static func previous(_ query: String, before location: Int, in text: NSString, caseSensitive: Bool, regex: Bool) -> NSRange? {
        guard !query.isEmpty else { return nil }
        let end = max(0, min(location, text.length))
        if regex {
            // `.backwards` cannot accompany a regular expression: enumerate forward, take the last.
            let all = ranges(of: query, in: text, caseSensitive: caseSensitive, regex: true)
            return all.last { NSMaxRange($0) <= end } ?? all.last
        }
        let options: NSString.CompareOptions = caseSensitive ? [.backwards] : [.backwards, .caseInsensitive]
        let before = text.range(of: query, options: options, range: NSRange(location: 0, length: end))
        if before.location != NSNotFound { return before }
        let any = text.range(of: query, options: options, range: NSRange(location: 0, length: text.length))
        return any.location == NSNotFound ? nil : any
    }

    /// What Replace writes over `selected` when the selection IS a match of `query` (the whole of it,
    /// for a regex), or nil when it is not — Replace then only moves on. A regex `template` is expanded
    /// against the selection's groups.
    public static func replacement(forSelection selected: String, query: String, template: String, caseSensitive: Bool, regex: Bool)
        -> String?
    {
        guard regex else {
            let same = caseSensitive ? selected == query : selected.caseInsensitiveCompare(query) == .orderedSame
            return same ? template : nil
        }
        let whole = NSRange(location: 0, length: (selected as NSString).length)
        guard let expression = expression(query, caseSensitive: caseSensitive),
            let match = expression.firstMatch(in: selected, range: whole), match.range == whole
        else { return nil }
        return expression.replacementString(for: match, in: selected, offset: 0, template: template)
    }

    /// Replace All's work: every match of `query` paired with what replaces it — `template` itself, or
    /// for a regex the template expanded per match. In text order.
    public static func replaceAll(_ query: String, with template: String, in text: NSString, caseSensitive: Bool, regex: Bool) -> [(
        range: NSRange, replacement: String
    )] {
        guard !query.isEmpty else { return [] }
        guard regex else { return ranges(of: query, in: text, caseSensitive: caseSensitive, regex: false).map { ($0, template) } }
        guard let expression = expression(query, caseSensitive: caseSensitive) else { return [] }
        let string = text as String
        return expression.matches(in: string, range: NSRange(location: 0, length: text.length))
            .filter { $0.range.length > 0 }
            .map { ($0.range, expression.replacementString(for: $0, in: string, offset: 0, template: template)) }
    }

    /// Where a caret at `caret` lands after `edits` (sorted, disjoint) are applied: shifted by every edit
    /// that ends before it; a caret inside a match goes to the end of that match's replacement.
    public static func caret(_ caret: Int, after edits: [(range: NSRange, replacement: String)]) -> Int {
        var moved = caret
        for edit in edits {
            let length = (edit.replacement as NSString).length
            if NSMaxRange(edit.range) <= caret {
                moved += length - edit.range.length
            } else if edit.range.location < caret {
                return edit.range.location + length + (moved - caret)
            } else {
                break
            }
        }
        return moved
    }

    /// The compiled query, or nil for an invalid pattern.
    private static func expression(_ pattern: String, caseSensitive: Bool) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: caseSensitive ? [] : [.caseInsensitive])
    }

    /// The first non-empty match of `expression` starting at or after `start`.
    private static func firstMatch(_ expression: NSRegularExpression, in text: NSString, from start: Int) -> NSRange? {
        var found: NSRange?
        expression.enumerateMatches(in: text as String, range: NSRange(location: start, length: text.length - start)) { match, _, stop in
            if let match, match.range.length > 0 {
                found = match.range
                stop.pointee = true
            }
        }
        return found
    }
}
