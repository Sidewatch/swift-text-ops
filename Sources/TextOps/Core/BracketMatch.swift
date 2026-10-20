//
//  BracketMatch.swift
//  TextOps
//
//  The bracket the caret is on, and its partner by nesting count.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Bracket pairing for a caret: which of `( ) [ ] { }` it sits on, and where that bracket's partner is.
///
/// The pairing is a plain nesting count over the raw UTF-16 text — blind to strings and comments, so a
/// `)` inside a string literal counts. That is the deliberate trade: it is fast enough to run on every
/// selection change, and a highlight and a jump that both use it can never disagree. The pairs are
/// ``AutoClose/brackets``, so typing and matching share one list.
public enum BracketMatch {
    /// How far ``partner(of:in:cap:)`` walks by default: far enough to pair the braces of a very long
    /// type, and still about a millisecond, because the walk compares raw UTF-16 units.
    public static let defaultCap = 500_000

    /// Opening unit → closing unit, from ``AutoClose/brackets``.
    static let openToClose: [unichar: unichar] = Dictionary(
        uniqueKeysWithValues: AutoClose.brackets.map { (unit($0.key), unit($0.value)) })
    /// Closing unit → opening unit.
    static let closeToOpen: [unichar: unichar] = Dictionary(uniqueKeysWithValues: openToClose.map { ($0.value, $0.key) })

    /// The index of the bracket at `location`, else the one just before it (typing a bracket leaves
    /// the caret past it), else nil.
    public static func bracket(near location: Int, in text: NSString) -> Int? {
        if location >= 0, location < text.length, isBracket(text.character(at: location)) { return location }
        if location > 0, location <= text.length, isBracket(text.character(at: location - 1)) { return location - 1 }
        return nil
    }

    /// The index of the bracket that pairs with the one at `index`, by nesting count: forward from an
    /// opener, backward from a closer, at most `cap` units each way (the bracket itself included). Nil when `index` is not a bracket,
    /// or the pair does not close within the cap.
    public static func partner(of index: Int, in text: NSString, cap: Int = defaultCap) -> Int? {
        guard index >= 0, index < text.length else { return nil }
        let unit = text.character(at: index)
        if let close = openToClose[unit] {
            return walk(from: index, step: 1, until: min(text.length, index + cap), same: unit, other: close, in: text)
        }
        if let open = closeToOpen[unit] {
            return walk(from: index, step: -1, until: max(-1, index - cap), same: unit, other: open, in: text)
        }
        return nil
    }

    /// Whether `unit` is one of the paired brackets.
    static func isBracket(_ unit: unichar) -> Bool { openToClose[unit] != nil || closeToOpen[unit] != nil }

    /// Steps from `start` toward `end` (exclusive), counting `same` up and `other` down; the index where
    /// the count returns to zero.
    private static func walk(from start: Int, step: Int, until end: Int, same: unichar, other: unichar, in text: NSString) -> Int? {
        var depth = 0, i = start
        while i != end {
            let c = text.character(at: i)
            if c == same {
                depth += 1
            } else if c == other {
                depth -= 1
                if depth == 0 { return i }
            }
            i += step
        }
        return nil
    }

    /// The single UTF-16 unit of an ASCII bracket character.
    private static func unit(_ character: Character) -> unichar { character.utf16.first ?? 0 }
}
