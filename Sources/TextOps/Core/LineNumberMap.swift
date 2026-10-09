//
//  LineNumberMap.swift
//  TextOps
//
//  Git numbers lines by `\n` alone; a Unicode-aware editor (TextKit, `NSString.lineRange`)
//  also breaks on a lone `\r`, U+0085, U+2028 and U+2029. Every such unit puts the two
//  numberings one further apart, and this map converts between them.
//
//  Created by David Sherlock on 10/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Converts between git's line numbers and a Unicode-aware editor's for one text.
///
/// Git ends a line at `\n` only. TextKit and `NSString.lineRange` also end one at a lone `\r`,
/// U+0085 (NEL), U+2028 (LS) and U+2029 (PS); `\r\n` is one break to both. A file holding any
/// such unit has every git line number below it off by one per unit, so a diff hunk's line
/// lands on the wrong editor line and a blame row names the wrong line. The map records where
/// the extra breaks fall, once per text, and answers both directions in O(log n).
///
/// Line numbers are 1-based. A git line that spans several editor lines maps to the first of
/// them; an editor line inside such a span maps to the git line holding it. Both directions
/// are monotone and clamp a number past either end to the last line.
public struct LineNumberMap: Equatable, Sendable {

    /// The git line each extra break lies on, in text order.
    private let extraGitLines: [Int]

    /// How many `\n` the text holds.
    private let lineFeedCount: Int

    /// The map for `text`; one pass over its UTF-16 units.
    public init(text: NSString) {
        let scan = LineBreakScan.scan(text)
        extraGitLines = scan.extraGitLines
        lineFeedCount = scan.lineFeedCount
    }

    /// The map for `text`; one pass over its UTF-16 units.
    public init(text: String) {
        self.init(text: text as NSString)
    }

    /// True when the text holds no break git would miss, so both numberings agree.
    public var isIdentity: Bool { extraGitLines.isEmpty }

    /// How many breaks the editor sees that git does not.
    public var extraBreakCount: Int { extraGitLines.count }

    /// How many lines git counts: one more than the `\n` count, the way an editor numbers the
    /// line after a final newline.
    public var gitLineCount: Int { lineFeedCount + 1 }

    /// How many lines the editor counts.
    public var unicodeLineCount: Int { lineFeedCount + extraGitLines.count + 1 }

    /// The editor line where git line `line` starts.
    public func unicodeLine(forGitLine line: Int) -> Int {
        let git = line.clamped(to: 1...gitLineCount)
        // Every extra break on an earlier git line comes before this line's start.
        return git + firstIndex { extraGitLines[$0] >= git }
    }

    /// The git line holding editor line `line`.
    public func gitLine(forUnicodeLine line: Int) -> Int {
        let unicode = line.clamped(to: 1...unicodeLineCount)
        // The i-th extra break (0-based) ends editor line `extraGitLines[i] + i`, so the line
        // after it starts at one more; every extra break starting at or before this line
        // shifted it by one.
        return unicode - firstIndex { extraGitLines[$0] + $0 + 1 > unicode }
    }

    /// The first index of `extraGitLines` where `predicate` holds, or the count when none does.
    /// `predicate` is false then true along the array, so this is a binary search.
    private func firstIndex(where predicate: (Int) -> Bool) -> Int {
        var low = 0
        var high = extraGitLines.count
        while low < high {
            let mid = (low + high) / 2
            if predicate(mid) { high = mid } else { low = mid + 1 }
        }
        return low
    }
}

extension Int {
    /// `self` held inside `range`.
    fileprivate func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
