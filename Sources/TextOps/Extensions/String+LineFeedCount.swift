//
//  String+LineFeedCount.swift
//  TextOps
//
//  How many line feeds a string holds, counted at memchr speed over its UTF-8.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

public extension String {
    /// How many `\n` this string holds, counted over its UTF-8 bytes with `memchr` (about 3 ms for
    /// 7.5 MB) — for a size check on freshly read text, before any line index exists. A CRLF counts
    /// once; a lone `\r` or a Unicode separator does not count (``LineNumberMap`` handles those).
    /// A native string is read in place; a bridged one is copied to UTF-8 first.
    var lineFeedCount: Int {
        var copy = self
        return copy.withUTF8 { buffer -> Int in
            guard var p = buffer.baseAddress else { return 0 }
            var remaining = buffer.count, count = 0
            while remaining > 0, let hit = memchr(p, 0x0A, remaining) {
                let step = UnsafePointer<UInt8>(hit.assumingMemoryBound(to: UInt8.self)) - p + 1
                p += step
                remaining -= step
                count += 1
            }
            return count
        }
    }
}
