//
//  LineStartIndex.swift
//  TextOps
//
//  Where every line of a text starts, kept current through edits without rescanning.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The UTF-16 offset at which every line of a text starts, for O(log n) line ↔ offset lookups on an
/// editor's hot paths (the gutter, the caret line, every line fragment), kept current through an edit by
/// a SPLICE instead of a rescan.
///
/// Lines are NSString's: `\n`, `\r`, `\r\n` (one break), U+0085, U+2028 and U+2029 each end one. The
/// empty line after a final break has no entry — TextKit draws it as an extra fragment that a gutter
/// numbers separately — so a text ending in a break has as many entries as breaks.
public struct LineStartIndex: Equatable, Sendable {
    /// The start offsets, ascending; `starts[0]` is always 0.
    public private(set) var starts: [Int]

    /// The index of `text`, scanned whole.
    public init(scanning text: NSString) {
        var out = [0]
        var i = 0
        while i < text.length {
            i = NSMaxRange(text.lineRange(for: NSRange(location: i, length: 0)))
            if i < text.length { out.append(i) }
        }
        starts = out
    }

    /// An index over known starts (ascending, beginning with 0).
    public init(starts: [Int]) { self.starts = starts }

    /// How many lines have an entry (at least 1).
    public var count: Int { starts.count }

    /// The 1-based line holding UTF-16 `offset`: the last line starting at or before it.
    @inlinable
    public func line(containing offset: Int) -> Int {
        var lo = 0, hi = starts.count - 1, index = 0
        while lo <= hi {
            let mid = (lo + hi) / 2
            if starts[mid] <= offset { index = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        return index + 1
    }

    /// The offset where 1-based `line` starts, or nil past either end.
    @inlinable
    public func start(ofLine line: Int) -> Int? {
        line >= 1 && line <= starts.count ? starts[line - 1] : nil
    }

    /// Brings the index through one edit of the text: `edited` is the edited range in the NEW text and
    /// `delta` the change in length, as `NSTextStorage` reports them, and `text` is the text after it.
    public mutating func splice(edited: NSRange, delta: Int, in text: NSString) {
        starts = Self.splicedStarts(starts, edited: edited, delta: delta, in: text)
    }

    /// In this (pre-edit) index: the index of the line an edit at `editLocation` began on, and the index
    /// just past the last line its replaced span — ending at `oldSpanEnd`, in old offsets — touched.
    public func editSpan(editLocation: Int, oldSpanEnd: Int) -> (edit: Int, spanEnd: Int) {
        var lo = 0, hi = starts.count - 1, k = 0
        while lo <= hi {
            let m = (lo + hi) / 2
            if starts[m] <= editLocation { k = m; lo = m + 1 } else { hi = m - 1 }
        }
        var tail = k + 1
        while tail < starts.count, starts[tail] <= oldSpanEnd { tail += 1 }
        return (k, tail)
    }

    /// The starts after an edit, without a full rescan.
    ///
    /// Membership is a PREDICATE, never bookkeeping: `p` starts a line iff `text[p-1]` is a break (a `\r`
    /// followed by `\n` does not count). So starts before the edit are kept, `edited.location...end` is
    /// recomputed, and starts past the old span shift by `delta`. Appending "one start per newline
    /// inserted" instead double-counts on replacements.
    static func splicedStarts(_ old: [Int], edited: NSRange, delta: Int, in s: NSString) -> [Int] {
        let oldSpanEnd = edited.location + edited.length - delta
        let editEnd = NSMaxRange(edited)
        // The predicate reads `s[p-1]` and `s[p]` for every p in the recompute range; fetch that window
        // ONCE as a block. `character(at:)` per position walks a text storage's NSBigMutableString tree
        // on every call: seconds for a whole-document swap of a multi-megabyte file, against ~20 ms for
        // one `getCharacters` read.
        let winStart = max(0, edited.location - 1)
        let winEnd = min(s.length, editEnd + 1)
        var win = [unichar](repeating: 0, count: max(0, winEnd - winStart))
        if winEnd > winStart { s.getCharacters(&win, range: NSRange(location: winStart, length: winEnd - winStart)) }
        /// Does `p` begin a line in the post-edit text? The empty final line owns no entry, hence
        /// `p < s.length`. Only asked for p in the recompute range, so `p - 1` and `p` are in the window.
        func isLineStart(_ p: Int) -> Bool {
            if p == 0 { return true }
            guard p < s.length else { return false }
            switch win[p - 1 - winStart] {
            case 0x0A, 0x0085, 0x2028, 0x2029: return true
            case 0x0D: return win[p - winStart] != 0x0A  // mid-\r\n is not a start
            default: return false
            }
        }
        var starts: [Int] = []
        starts.reserveCapacity(old.count + 4)
        var i = 0
        while i < old.count, old[i] < edited.location { starts.append(old[i]); i += 1 }
        if isLineStart(edited.location) { starts.append(edited.location) }
        // The rest of the recompute range: p > edited.location starts a line iff the unit before it is
        // a break. One tight pass over the window — a closure call per position was 25 ms of every
        // whole-document swap of a 7 MB file.
        let last = max(edited.location, editEnd)
        if last > edited.location {
            win.withUnsafeBufferPointer { w in
                for p in (edited.location + 1)...last where p < s.length {
                    let c = w[p - 1 - winStart]
                    if c == 0x0A || c == 0x2028 || c == 0x2029 || c == 0x0085 {
                        starts.append(p)
                    } else if c == 0x0D, w[p - winStart] != 0x0A {
                        starts.append(p)
                    }
                }
            }
        }
        var t = 0
        while t < old.count, old[t] <= oldSpanEnd { t += 1 }
        while t < old.count { starts.append(old[t] + delta); t += 1 }
        return starts
    }
}
