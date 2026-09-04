//
//  Identifier.swift
//  TextOps
//
//  Identifier-style word ranges in UTF-16 text: letters, digits, `_` and `$` — the set a
//  hover, a completion prefix and a select-word all agree on.
//

import Foundation

/// Identifier-style words (alphanumerics, `_`, `$`) located by UTF-16 offset.
public enum Identifier {

    /// True for a unit that can be part of an identifier: alphanumerics, `_` and `$`.
    public static func isUnit(_ u: unichar) -> Bool {
        guard let s = Unicode.Scalar(u) else { return false }
        return CharacterSet.alphanumerics.contains(s) || s == "_" || s == "$"
    }

    /// The identifier containing `index`, or nil when `index` is not on an identifier unit
    /// (or is past the end).
    public static func range(at index: Int, in ns: NSString) -> NSRange? {
        guard index >= 0, index < ns.length, isUnit(ns.character(at: index)) else { return nil }
        return expand(from: index, in: ns)
    }

    /// The identifier at a caret: the one containing `index`, or — when the caret sits just
    /// past a word, as after typing it — the one ending at `index`. Nil when neither.
    public static func range(nearCaret index: Int, in ns: NSString) -> NSRange? {
        if let here = range(at: index, in: ns) { return here }
        guard index > 0, index <= ns.length, isUnit(ns.character(at: index - 1)) else { return nil }
        return expand(from: index - 1, in: ns)
    }

    /// The identifier around an index known to be on a unit.
    private static func expand(from index: Int, in ns: NSString) -> NSRange {
        var start = index, end = index + 1
        while start > 0, isUnit(ns.character(at: start - 1)) { start -= 1 }
        while end < ns.length, isUnit(ns.character(at: end)) { end += 1 }
        return NSRange(location: start, length: end - start)
    }
}
