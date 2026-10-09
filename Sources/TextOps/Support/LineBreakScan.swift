//
//  LineBreakScan.swift
//  TextOps
//
//  One pass over a text's UTF-16 units that counts the `\n` git numbers lines by and locates
//  every break git does not count. Built for a 20 MB buffer: the units are fetched in chunks
//  and each chunk is swept with `memchr`, so the per-unit work stays in libc.
//
//  Created by David Sherlock on 10/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// What a pass over a text's line breaks found: how many `\n` it holds and, for every break
/// git does not count, the git line (1-based) that break lies on, in text order.
struct LineBreakScan: Equatable, Sendable {

    /// How many `\n` the text holds.
    var lineFeedCount = 0

    /// For each extra break in text order — a `\r` not followed by `\n`, U+0085, U+2028 or
    /// U+2029 — the git line it lies on. Non-decreasing.
    var extraGitLines: [Int] = []

    /// Units fetched per `getCharacters` call when the string has no contiguous UTF-16 store.
    static let chunk = 1 << 16

    /// Scans `text` whole.
    static func scan(_ text: NSString) -> LineBreakScan {
        var scan = LineBreakScan()
        let length = text.length
        if let direct = CFStringGetCharactersPtr(text as CFString) {
            scan.consume(direct, count: length, next: nil)
            return scan
        }
        // One unit of lookahead per chunk, so a `\r` on the chunk's last unit can see its `\n`.
        let buffer = UnsafeMutablePointer<unichar>.allocate(capacity: chunk + 1)
        defer { buffer.deallocate() }
        var position = 0
        while position < length {
            let count = min(chunk, length - position)
            let fetched = min(count + 1, length - position)
            text.getCharacters(buffer, range: NSRange(location: position, length: fetched))
            scan.consume(UnsafePointer(buffer), count: count, next: fetched > count ? buffer[count] : nil)
            position += count
        }
        return scan
    }

    /// Folds the `count` units at `units` into the scan; `next` is the unit after them, nil at
    /// the end of the text.
    private mutating func consume(_ units: UnsafePointer<unichar>, count: Int, next: unichar?) {
        let extras = Self.extraBreaks(in: units, count: count, next: next)
        guard !extras.isEmpty else {
            Self.visit(0x0A, in: units, count: count) { _ in lineFeedCount += 1 }
            return
        }
        // Merge the two ascending lists: every `\n` before an extra break is on an earlier line.
        let lineFeeds = Self.indices(of: 0x0A, in: units, count: count)
        var seen = 0
        for extra in extras {
            while seen < lineFeeds.count, lineFeeds[seen] < extra { seen += 1 }
            extraGitLines.append(lineFeedCount + seen + 1)
        }
        lineFeedCount += lineFeeds.count
    }

    /// The indices of the extra breaks among the units, ascending.
    private static func extraBreaks(in units: UnsafePointer<unichar>, count: Int, next: unichar?) -> [Int] {
        var found: [Int] = []
        visit(0x0D, in: units, count: count) { index in
            let following = index + 1 < count ? units[index + 1] : next
            if following != 0x0A { found.append(index) }
        }
        for unit in [unichar(0x85), 0x2028, 0x2029] { found += indices(of: unit, in: units, count: count) }
        return found.sorted()
    }

    /// The indices of every unit equal to `unit`, ascending.
    private static func indices(of unit: unichar, in units: UnsafePointer<unichar>, count: Int) -> [Int] {
        var found: [Int] = []
        visit(unit, in: units, count: count) { found.append($0) }
        return found
    }

    /// Calls `body` with the index of every unit equal to `unit`, ascending. `memchr` finds the
    /// bytes equal to the unit's low byte; a hit on the other byte of a unit, or on a unit that
    /// merely contains the byte, is rejected by comparing the whole unit, which also keeps the
    /// sweep independent of byte order.
    private static func visit(_ unit: unichar, in units: UnsafePointer<unichar>, count: Int, _ body: (Int) -> Void) {
        let bytes = UnsafeRawPointer(units)
        let byteCount = count * 2
        var offset = 0
        while offset < byteCount, let hit = memchr(bytes + offset, Int32(unit & 0xFF), byteCount - offset) {
            let byteIndex = UnsafeRawPointer(hit) - bytes
            let index = byteIndex >> 1
            if units[index] == unit { body(index) }
            offset = byteIndex + 1
        }
    }
}
