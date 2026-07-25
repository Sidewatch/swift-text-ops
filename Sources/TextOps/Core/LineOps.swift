//
//  LineOps.swift
//  SwiftTextOps
//
//  The line transforms — sort, dedupe, clean, join/split, re-case, transpose. Pure `[String]` in,
//  `[String]` out; no Foundation state, no I/O, no mutation of the input.
//
//  Created by David Sherlock on 7/25/26.
//

import Foundation

/// Stateless transforms over an array of lines.
///
/// Every operation takes lines and returns new lines, so they compose freely and are trivially
/// testable. Nothing here knows about text views, files, or selections — call through
/// ``TextLines/transform(_:_:)`` to apply one to a whole document.
///
/// Sorting is **stable**: lines that compare equal keep their original relative order, in ascending
/// and descending directions alike.
public enum LineOps {

    // MARK: - Ordering

    /// Sorts lines by `key`.
    ///
    /// The sort is stable — equal lines keep their original relative order even when `descending`
    /// is `true`. With ``SortKey/numeric``, lines containing no number are not sorted at all: they
    /// keep their relative order and collect at the end in both directions.
    ///
    /// - Parameters:
    ///   - lines: The lines to sort.
    ///   - key: The value to compare on (default ``SortKey/alphabetical``).
    ///   - descending: Reverse the ordering (default `false`).
    ///   - caseInsensitive: Compare case-folded — ``SortKey/alphabetical`` only (default `false`).
    /// - Returns: The sorted lines.
    public static func sort(_ lines: [String],
                            by key: SortKey = .alphabetical,
                            descending: Bool = false,
                            caseInsensitive: Bool = false) -> [String] {
        guard key == .numeric else {
            return stableSort(lines, descending: descending) {
                compare($0, $1, by: key, caseInsensitive: caseInsensitive)
            }
        }

        // Numeric: a line with no number has no position to sort into, so park those at the end
        // (in input order) rather than letting them sink or float with the direction.
        var numbered: [String] = []
        var unnumbered: [String] = []
        for line in lines {
            if leadingNumber(line) != nil { numbered.append(line) } else { unnumbered.append(line) }
        }
        let sorted = stableSort(numbered, descending: descending) {
            compare($0, $1, by: .numeric, caseInsensitive: caseInsensitive)
        }
        return sorted + unnumbered
    }

    /// Reverses the order of the lines.
    ///
    /// - Parameter lines: The lines to reverse.
    /// - Returns: The lines, last to first.
    public static func reverse(_ lines: [String]) -> [String] {
        lines.reversed()
    }

    /// Shuffles the lines using the system random source.
    ///
    /// - Parameter lines: The lines to shuffle.
    /// - Returns: The lines in random order.
    public static func shuffle(_ lines: [String]) -> [String] {
        lines.shuffled()
    }

    /// Shuffles the lines using a supplied random source.
    ///
    /// Seed the generator to make a shuffle reproducible — this is the overload tests use.
    ///
    /// - Parameters:
    ///   - lines: The lines to shuffle.
    ///   - generator: The random source to draw from.
    /// - Returns: The lines in random order.
    public static func shuffle<G: RandomNumberGenerator>(_ lines: [String], using generator: inout G) -> [String] {
        lines.shuffled(using: &generator)
    }

    // MARK: - Deduplication

    /// Removes duplicate lines, keeping the **first** occurrence of each and preserving order.
    ///
    /// - Parameters:
    ///   - lines: The lines to deduplicate.
    ///   - caseInsensitive: Treat lines differing only in case as duplicates (default `false`).
    ///     The surviving line keeps its original casing.
    /// - Returns: The lines with later duplicates removed.
    public static func unique(_ lines: [String], caseInsensitive: Bool = false) -> [String] {
        var seen = Set<String>()
        return lines.filter { seen.insert(caseInsensitive ? $0.lowercased() : $0).inserted }
    }

    // MARK: - Cleaning

    /// Removes every blank line — empty, or whitespace-only.
    ///
    /// - Parameter lines: The lines to filter.
    /// - Returns: The lines with blanks dropped.
    public static func removeBlankLines(_ lines: [String]) -> [String] {
        lines.filter { !isBlank($0) }
    }

    /// Collapses each run of two or more blank lines down to a single blank line.
    ///
    /// Unlike ``removeBlankLines(_:)`` this keeps paragraph separation intact — it only removes
    /// the *extra* blanks.
    ///
    /// - Parameter lines: The lines to collapse.
    /// - Returns: The lines with blank runs reduced to one.
    public static func collapseBlankRuns(_ lines: [String]) -> [String] {
        var result: [String] = []
        var previousWasBlank = false
        for line in lines {
            let blank = isBlank(line)
            if blank && previousWasBlank { continue }
            result.append(line)
            previousWasBlank = blank
        }
        return result
    }

    /// Strips trailing whitespace from every line.
    ///
    /// Leading indentation is untouched — only the end of each line is trimmed.
    ///
    /// - Parameter lines: The lines to trim.
    /// - Returns: The trimmed lines.
    public static func trimTrailingWhitespace(_ lines: [String]) -> [String] {
        lines.map { line in
            var trimmed = Substring(line)
            while let last = trimmed.last, last.isWhitespace { trimmed.removeLast() }
            return String(trimmed)
        }
    }

    // MARK: - Joining & splitting

    /// Joins every line into one, separated by `separator`.
    ///
    /// - Parameters:
    ///   - lines: The lines to join.
    ///   - separator: The text to place between them (default a single space).
    /// - Returns: A single-element array holding the joined text.
    public static func join(_ lines: [String], separator: String = " ") -> [String] {
        [lines.joined(separator: separator)]
    }

    /// Splits every line on `delimiter`, so each piece becomes its own line.
    ///
    /// - Parameters:
    ///   - lines: The lines to split.
    ///   - delimiter: The text to split on. An empty delimiter returns the input unchanged.
    /// - Returns: The split lines.
    public static func split(_ lines: [String], on delimiter: String) -> [String] {
        guard !delimiter.isEmpty else { return lines }
        return lines.flatMap { $0.components(separatedBy: delimiter) }
    }

    // MARK: - Decorating

    /// Wraps every line in `prefix` and `suffix`.
    ///
    /// - Parameters:
    ///   - lines: The lines to decorate.
    ///   - prefix: Text to place before each line (default none).
    ///   - suffix: Text to place after each line (default none).
    /// - Returns: The decorated lines, or the input unchanged when both affixes are empty.
    public static func addAffixes(_ lines: [String], prefix: String = "", suffix: String = "") -> [String] {
        guard !prefix.isEmpty || !suffix.isEmpty else { return lines }
        return lines.map { prefix + $0 + suffix }
    }

    /// Numbers every line, counting from `start`.
    ///
    /// - Parameters:
    ///   - lines: The lines to number.
    ///   - start: The number given to the first line (default `1`).
    ///   - separator: Text placed between the number and the line (default `". "`).
    /// - Returns: The numbered lines.
    public static func number(_ lines: [String], startingAt start: Int = 1, separator: String = ". ") -> [String] {
        lines.enumerated().map { "\(start + $0.offset)\(separator)\($0.element)" }
    }

    /// Removes `leading` from the start of every line and `trailing` from its end, where present.
    ///
    /// Lines that don't carry the trigger text are left alone, so this is safe to run over a mixed
    /// list. Both ends are considered independently.
    ///
    /// - Parameters:
    ///   - lines: The lines to prune.
    ///   - leading: Text to strip from the start of each line (default none).
    ///   - trailing: Text to strip from the end of each line (default none).
    /// - Returns: The pruned lines, or the input unchanged when both triggers are empty.
    public static func prune(_ lines: [String], leading: String = "", trailing: String = "") -> [String] {
        guard !leading.isEmpty || !trailing.isEmpty else { return lines }
        return lines.map { line in
            var remaining = Substring(line)
            if !leading.isEmpty, remaining.hasPrefix(leading) { remaining = remaining.dropFirst(leading.count) }
            if !trailing.isEmpty, remaining.hasSuffix(trailing) { remaining = remaining.dropLast(trailing.count) }
            return String(remaining)
        }
    }

    // MARK: - Case

    /// Re-cases every line.
    ///
    /// - Parameters:
    ///   - lines: The lines to re-case.
    ///   - letterCase: The transform to apply.
    /// - Returns: The re-cased lines.
    public static func applyCase(_ lines: [String], _ letterCase: LetterCase) -> [String] {
        lines.map { line in
            switch letterCase {
            case .lower: return line.lowercased()
            case .upper: return line.uppercased()
            case .title: return line.capitalized
            }
        }
    }

    // MARK: - Transpose

    /// Transposes rows into columns.
    ///
    /// Each line is split on `delimiter` into cells; the resulting grid is flipped so row *n*
    /// becomes column *n*. Ragged rows are padded with empty cells, so the output is always
    /// rectangular and the operation round-trips when applied twice to rectangular input.
    ///
    /// - Parameters:
    ///   - lines: The rows to transpose.
    ///   - delimiter: The cell separator, used to both split and re-join (default a tab).
    /// - Returns: The transposed rows. Empty input, or an empty delimiter, returns the input unchanged.
    public static func transpose(_ lines: [String], delimiter: String = "\t") -> [String] {
        guard !lines.isEmpty, !delimiter.isEmpty else { return lines }

        let rows = lines.map { $0.components(separatedBy: delimiter) }
        guard let width = rows.map(\.count).max(), width > 0 else { return lines }

        return (0..<width).map { column in
            rows.map { column < $0.count ? $0[column] : "" }.joined(separator: delimiter)
        }
    }

    // MARK: - Internal

    /// Whether a line is empty or whitespace-only.
    private static func isBlank(_ line: String) -> Bool {
        line.allSatisfy(\.isWhitespace)
    }

    /// Sorts with the original index as the tiebreak, so equal elements never reorder — including
    /// when `descending` flips the comparison.
    private static func stableSort(_ lines: [String],
                                   descending: Bool,
                                   by compare: (String, String) -> ComparisonResult) -> [String] {
        lines.enumerated()
            .sorted { a, b in
                switch compare(a.element, b.element) {
                case .orderedAscending: return !descending
                case .orderedDescending: return descending
                case .orderedSame: return a.offset < b.offset
                }
            }
            .map(\.element)
    }

    /// Compares two lines on `key`.
    private static func compare(_ a: String, _ b: String, by key: SortKey, caseInsensitive: Bool) -> ComparisonResult {
        switch key {
        case .alphabetical:
            let left = caseInsensitive ? a.lowercased() : a
            let right = caseInsensitive ? b.lowercased() : b
            if left == right { return .orderedSame }
            return left < right ? .orderedAscending : .orderedDescending

        case .length:
            if a.count == b.count { return .orderedSame }
            return a.count < b.count ? .orderedAscending : .orderedDescending

        case .numeric:
            // Only reached for lines that `sort` already established do carry a number.
            let left = leadingNumber(a) ?? 0
            let right = leadingNumber(b) ?? 0
            if left == right { return .orderedSame }
            return left < right ? .orderedAscending : .orderedDescending
        }
    }

    /// The first number appearing anywhere in `line`, or `nil` when it holds none.
    ///
    /// Scans for the first digit run, keeping a leading sign and one decimal point:
    /// `"item 12.5 of 30"` reads as `12.5`, `"v2"` as `2`, `"12. Widgets"` as `12`.
    private static func leadingNumber(_ line: String) -> Double? {
        var token = ""
        var seenDigit = false
        var seenDot = false

        for character in line {
            if character.isNumber {
                token.append(character)
                seenDigit = true
            } else if (character == "-" || character == "+") && token.isEmpty {
                token.append(character)
            } else if character == "." && seenDigit && !seenDot {
                token.append(character)
                seenDot = true
            } else if seenDigit {
                break
            } else {
                // A sign with no digits behind it was a false start — drop it and keep scanning.
                token = ""
            }
        }

        // A number ending at the decimal point ("12." from a numbered list) won't parse as-is.
        if token.hasSuffix(".") { token.removeLast() }
        return Double(token)
    }
}
