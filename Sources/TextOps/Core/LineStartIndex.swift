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
        var out: [Int] = []
        Self.appendStarts(in: text, from: 0, through: text.length, to: &out)
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
        var starts: [Int] = []
        starts.reserveCapacity(old.count + 4)
        var i = 0
        while i < old.count, old[i] < edited.location { starts.append(old[i]); i += 1 }
        appendStarts(in: s, from: edited.location, through: max(edited.location, NSMaxRange(edited)), to: &starts)
        // Starts before the edit are below `oldSpanEnd` already: carry on from the first one that is not.
        var t = i
        while t < old.count, old[t] <= oldSpanEnd { t += 1 }
        while t < old.count { starts.append(old[t] + delta); t += 1 }
        return starts
    }

    /// Units read per `getCharacters` call by ``appendStarts(in:from:through:block:to:)``.
    static let block = 1 << 16

    /// Appends to `starts`, ascending, every offset `p` in `lo...hi` that begins a line of `s`: 0, and any
    /// `p < s.length` whose preceding unit is a break (a `\r` followed by `\n` is not one; the empty line after
    /// a final break owns no entry). The units are read `block` at a time with one unit of lookahead, never one
    /// by one (`character(at:)` walks a text storage's NSBigMutableString tree on every call) and never as one
    /// copy of the whole range (a 1 GB document's swap allocated and zeroed a 2 GB window).
    static func appendStarts(in s: NSString, from lo: Int, through hi: Int, block: Int = block, to starts: inout [Int]) {
        if lo == 0 { starts.append(0) }
        let last = min(hi, s.length - 1)  // the last p that can start a line
        var before = max(lo, 1) - 1  // the unit before the next p
        guard before < last else { return }
        let buffer = UnsafeMutablePointer<unichar>.allocate(capacity: block + 1)
        defer { buffer.deallocate() }
        while before < last {
            let end = min(before + block, last)  // this pass decides p = before + 1 ... end
            s.getCharacters(buffer, range: NSRange(location: before, length: end - before + 1))
            appendBreaks(in: buffer, count: end - before, base: before + 1, to: &starts)
            before = end
        }
    }

    /// Appends `base + k` for every `k < count` whose unit ends a line (`units[k + 1]`, which must be readable,
    /// tells a `\r` from a `\r\n`). Sixteen units at a time: a run of sixteen holding none of the five break
    /// units, which is nearly every run of a text, is passed with a handful of vector comparisons, a 1 GB log's
    /// whole scan in a fraction of the time a unit-by-unit loop takes.
    private static func appendBreaks(in units: UnsafePointer<unichar>, count: Int, base: Int, to starts: inout [Int]) {
        let raw = UnsafeRawPointer(units)
        var k = 0
        while k + 16 <= count {
            let v = raw.loadUnaligned(fromByteOffset: k * 2, as: SIMD16<UInt16>.self)
            let lineFeedOrReturn = (v .== SIMD16(repeating: 0x0A)) .| (v .== SIMD16(repeating: 0x0D))
            let separators = (v .== SIMD16(repeating: 0x85)) .| (v .== SIMD16(repeating: 0x2028)) .| (v .== SIMD16(repeating: 0x2029))
            if any(lineFeedOrReturn .| separators) {
                for j in k..<(k + 16) where endsLine(units, j) { starts.append(base + j) }
            }
            k += 16
        }
        while k < count {
            if endsLine(units, k) { starts.append(base + k) }
            k += 1
        }
    }

    /// Whether `units[k]` ends a line: `\n`, U+0085, U+2028, U+2029, or a `\r` that no `\n` follows.
    @inline(__always)
    private static func endsLine(_ units: UnsafePointer<unichar>, _ k: Int) -> Bool {
        let c = units[k]
        return c == 0x0A || c == 0x85 || c == 0x2028 || c == 0x2029 || (c == 0x0D && units[k + 1] != 0x0A)
    }
}
