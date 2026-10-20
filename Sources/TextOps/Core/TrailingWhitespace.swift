//
//  TrailingWhitespace.swift
//  TextOps
//
//  The spaces and tabs at the end of every line, for trim-on-save.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Trailing whitespace across a whole text — the trim-on-save rule. A run of tabs and Unicode space
/// separators (`\p{Zs}`) before ANY line break or the end of the text; the breaks themselves are never
/// part of a run, so mixed, CR-only and Unicode line endings survive a trim untouched.
public enum TrailingWhitespace {
    /// `[\t\p{Zs}]+$` with `$` before every break kind (`.anchorsMatchLines`).
    static let expression = try! NSRegularExpression(pattern: "[\\t\\p{Zs}]+$", options: [.anchorsMatchLines])

    /// Every trailing run, in text order — for deleting them one by one, so a text view keeps the caret
    /// and scroll position across each.
    public static func ranges(in text: String) -> [NSRange] {
        expression.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)).map(\.range)
    }

    /// `text` with every trailing run removed.
    public static func trimmed(_ text: String) -> String {
        expression.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: "")
    }
}
