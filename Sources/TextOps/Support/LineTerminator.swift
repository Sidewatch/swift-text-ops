//
//  LineTerminator.swift
//  TextOps
//
//  The line break at the end of a line, read the way NSString divides lines.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The line break at the end of a line, read the way `NSString.lineRange(for:)` divides lines:
/// `\r\n` is ONE break of two units, and `\n`, `\r`, NEL, LS and PS are one unit each. In Swift
/// `"\r\n"` is a single `Character`, so `hasSuffix("\n")` is false for a CRLF line — the reason
/// line commands go through this instead.
enum LineTerminator {
    /// The break `range` (a whole line from `lineRange(for:)`) ends with, or `""` for the last line
    /// of a text that does not end in one.
    static func of(_ range: NSRange, in ns: NSString) -> String {
        let end = NSMaxRange(range)
        let length = self.length(endingAt: end, in: ns, notBefore: range.location)
        return length == 0 ? "" : ns.substring(with: NSRange(location: end - length, length: length))
    }

    /// The length (0, 1 or 2) of the break that ends just before `index`, never reaching before `floor`.
    static func length(endingAt index: Int, in ns: NSString, notBefore floor: Int = 0) -> Int {
        guard index > floor else { return 0 }
        let last = ns.character(at: index - 1)
        if last == 0x0A, index - 1 > floor, ns.character(at: index - 2) == 0x0D { return 2 }
        return [0x0A, 0x0D, 0x85, 0x2028, 0x2029].contains(last) ? 1 : 0
    }

    /// The break the text uses: its first one, or `\n` when it has none — what a command that has to
    /// supply a break (duplicating an unterminated last line) writes, so a CRLF file stays CRLF.
    static func preferred(in ns: NSString) -> String {
        var start = 0, end = 0, contentsEnd = 0
        ns.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: 0, length: 0))
        return end > contentsEnd ? ns.substring(with: NSRange(location: contentsEnd, length: end - contentsEnd)) : "\n"
    }
}
