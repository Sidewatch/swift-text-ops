//
//  TextLines.swift
//  SwiftTextOps
//
//  Splitting a text into lines and putting it back together with the terminator it arrived with.
//
//  Created by David Sherlock on 7/25/26.
//

import Foundation

/// Line splitting and re-joining that survives a round trip.
///
/// Every transform in ``LineOps`` works on `[String]`. `TextLines` is the bridge from and back to
/// a whole document: it detects the text's line terminator, hides the empty element a trailing
/// newline produces (so a sort can't drag it into the middle of the file), and restores both on
/// the way out.
public enum TextLines {

    /// The line terminator `text` uses.
    ///
    /// The first terminator found wins: a text containing `\r\n` reports ``LineEnding/crlf`` even
    /// when bare `\n` appears elsewhere. A text with no terminator at all reports ``LineEnding/lf``.
    ///
    /// - Parameter text: The text to inspect.
    /// - Returns: The detected terminator.
    public static func detectEnding(_ text: String) -> LineEnding {
        if text.contains("\r\n") { return .crlf }
        if text.contains("\r") { return .cr }
        return .lf
    }

    /// Splits `text` into lines, normalizing `\r\n` and lone `\r` to `\n` first.
    ///
    /// A trailing newline yields a final empty element, matching `components(separatedBy:)` — so
    /// `"a\nb\n"` splits into `["a", "b", ""]`. Use ``transform(_:_:)`` to apply an operation
    /// without that element getting in the way.
    ///
    /// - Parameter text: The text to split.
    /// - Returns: The lines, without terminators.
    public static func split(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }

    /// Joins `lines` with `ending`.
    ///
    /// - Parameters:
    ///   - lines: The lines to join.
    ///   - ending: The terminator to place between them (default ``LineEnding/lf``).
    /// - Returns: The joined text.
    public static func join(_ lines: [String], ending: LineEnding = .lf) -> String {
        lines.joined(separator: ending.rawValue)
    }

    /// Runs a line transform over a whole text, preserving its line terminator and its
    /// trailing newline (or absence of one).
    ///
    /// This is the entry point a text view should call: `body` sees only real lines — never the
    /// empty element a trailing newline produces — and the result is re-joined with whatever
    /// terminator the input used.
    ///
    /// - Parameters:
    ///   - text: The whole text to transform.
    ///   - body: The line transform to apply.
    /// - Returns: The transformed text.
    public static func transform(_ text: String, _ body: ([String]) -> [String]) -> String {
        let ending = detectEnding(text)
        var lines = split(text)

        // `split` reports a trailing newline as a final empty element. Hold it back so operations
        // like sort or unique can't relocate or swallow it, then put it back afterwards.
        let hadTrailingNewline = lines.count > 1 && lines.last == ""
        if hadTrailingNewline { lines.removeLast() }

        var result = body(lines)
        if hadTrailingNewline { result.append("") }

        return join(result, ending: ending)
    }
}
