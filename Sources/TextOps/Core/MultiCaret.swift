//
//  MultiCaret.swift
//  TextOps
//
//  The arithmetic of editing at several carets at once.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The arithmetic of a multi-caret edit (⌘D, ⇧⌘L, ⌥-click, Add Cursors to Line Ends), kept apart from
/// the text view that applies it: which ranges an edit replaces, where each caret lands after it, and
/// what Backspace and Forward Delete take at each caret.
///
/// A deletion takes one whole CHARACTER, as a single caret does — an emoji, a flag, an accented letter
/// built from combining marks, and a CRLF break are each one — never one UTF-16 unit, which would leave
/// half a surrogate pair or a stray `\r` behind.
public enum MultiCaret {
    /// `ranges` sorted, with overlapping or touching neighbours merged into one.
    public static func merged(_ ranges: [NSRange]) -> [NSRange] {
        var merged: [NSRange] = []
        for range in ranges.sorted(by: { $0.location < $1.location }) {
            if let last = merged.last, range.location <= NSMaxRange(last) {
                let end = max(NSMaxRange(last), NSMaxRange(range))
                merged[merged.count - 1] = NSRange(location: last.location, length: end - last.location)
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    /// Where each caret lands after every range of `merged` (sorted, disjoint) is replaced by
    /// `insertLength` units: just past its replacement, in post-edit coordinates.
    public static func carets(afterReplacing merged: [NSRange], insertLength: Int) -> [Int] {
        var positions: [Int] = []
        var offset = 0
        for range in merged {
            positions.append(range.location + offset + insertLength)
            offset += insertLength - range.length
        }
        return positions
    }

    /// What Backspace removes at `carets`: the selected spans when any caret has a selection, else the
    /// character before each caret (none at the start of the text).
    public static func backspaceTargets(_ carets: [NSRange], in text: NSString) -> [NSRange] {
        if carets.contains(where: { $0.length > 0 }) { return carets }
        return carets.compactMap { caret in
            guard caret.location > 0, caret.location <= text.length else { return nil }
            let breakLength = LineTerminator.length(endingAt: caret.location, in: text)
            if breakLength > 0 { return NSRange(location: caret.location - breakLength, length: breakLength) }
            return text.rangeOfComposedCharacterSequence(at: caret.location - 1)
        }
    }

    /// What Forward Delete removes at `carets`: the selected spans when any caret has a selection, else
    /// the character after each caret (none at the end of the text).
    public static func forwardDeleteTargets(_ carets: [NSRange], in text: NSString) -> [NSRange] {
        if carets.contains(where: { $0.length > 0 }) { return carets }
        return carets.compactMap { caret in
            guard caret.location >= 0, caret.location < text.length else { return nil }
            let line = text.lineRange(for: NSRange(location: caret.location, length: 0))
            let breakLength = LineTerminator.of(line, in: text).utf16.count
            if breakLength > 0, caret.location == NSMaxRange(line) - breakLength {
                return NSRange(location: caret.location, length: breakLength)
            }
            return text.rangeOfComposedCharacterSequence(at: caret.location)
        }
    }

    /// A caret at the end of every line `selection` touches (Add Cursors to Line Ends): the last line's
    /// caret sits where the selection ends, and a selection ending at a line's START (whole lines,
    /// break included) adds none on that line. Empty for an empty selection.
    public static func lineEndCarets(for selection: NSRange, in text: NSString) -> [NSRange] {
        guard selection.length > 0 else { return [] }
        let end = NSMaxRange(selection)
        var carets: [NSRange] = []
        var lineStart = text.lineRange(for: NSRange(location: selection.location, length: 0)).location
        while lineStart < end {
            var lineEnd = 0, contentsEnd = 0
            text.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: lineStart, length: 0))
            carets.append(NSRange(location: min(contentsEnd, end), length: 0))
            guard lineEnd > lineStart else { break }
            lineStart = lineEnd
        }
        return carets
    }
}
