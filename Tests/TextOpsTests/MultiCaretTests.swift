//
//  MultiCaretTests.swift
//  TextOpsTests
//
//  Several carets at once: merging, where carets land, and what each deletion takes.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import TextOps

/// `MultiCaret`.
final class MultiCaretTests: XCTestCase {
    private func carets(_ locations: Int...) -> [NSRange] { locations.map { NSRange(location: $0, length: 0) } }

    /// Applies `targets` the way the editor does: merged, replaced back to front.
    private func apply(_ targets: [NSRange], to text: String, with insert: String = "") -> (String, [Int]) {
        let merged = MultiCaret.merged(targets)
        let out = NSMutableString(string: text)
        for range in merged.reversed() { out.replaceCharacters(in: range, with: insert) }
        return (out as String, MultiCaret.carets(afterReplacing: merged, insertLength: (insert as NSString).length))
    }

    func testOverlappingAndTouchingRangesMergeInOrder() {
        let merged = MultiCaret.merged([
            NSRange(location: 8, length: 2), NSRange(location: 0, length: 3), NSRange(location: 3, length: 1),
            NSRange(location: 9, length: 4),
        ])
        XCTAssertEqual(merged, [NSRange(location: 0, length: 4), NSRange(location: 8, length: 5)])
    }

    func testCaretsLandPastEachReplacementInPostEditCoordinates() {
        let (text, positions) = apply([NSRange(location: 0, length: 3), NSRange(location: 4, length: 3)], to: "foo foo", with: "barbaz")
        XCTAssertEqual(text, "barbaz barbaz")
        XCTAssertEqual(positions, [6, 13])
    }

    func testBackspaceTakesAWholeCharacterAtEachCaret() {
        let text = "a😀|e\u{301}|🇬🇧|x"
        let ns = text as NSString
        let after = [ns.range(of: "😀"), ns.range(of: "e\u{301}"), ns.range(of: "🇬🇧"), ns.range(of: "x")].map { NSMaxRange($0) }
        let (result, _) = apply(MultiCaret.backspaceTargets(after.map { NSRange(location: $0, length: 0) }, in: ns), to: text)
        XCTAssertEqual(result, "a|||", "an emoji, a combining accent, a flag and a letter, each whole")
    }

    func testBackspaceAfterACRLFTakesTheWholeBreak() {
        let (joined, _) = apply(MultiCaret.backspaceTargets(carets(4, 8), in: "ab\r\ncd\r\nef"), to: "ab\r\ncd\r\nef")
        XCTAssertEqual(joined, "abcdef", "no stray \\r is left behind")
    }

    func testForwardDeleteTakesAWholeCharacterOrBreak() {
        let text = "a😀b\r\nc"
        let (result, _) = apply(MultiCaret.forwardDeleteTargets(carets(1, 4), in: text as NSString), to: text)
        XCTAssertEqual(result, "abc", "the emoji whole, and the CRLF whole")
    }

    func testDeletionsSkipTheEdgesOfTheText() {
        XCTAssertEqual(MultiCaret.backspaceTargets(carets(0, 2), in: "ab"), [NSRange(location: 1, length: 1)])
        XCTAssertEqual(MultiCaret.forwardDeleteTargets(carets(0, 2), in: "ab"), [NSRange(location: 0, length: 1)])
    }

    func testASelectionAnywhereMakesEveryDeletionTheSelections() {
        let mixed = [NSRange(location: 1, length: 2), NSRange(location: 5, length: 0)]
        XCTAssertEqual(MultiCaret.backspaceTargets(mixed, in: "abcdefg"), mixed)
        XCTAssertEqual(MultiCaret.forwardDeleteTargets(mixed, in: "abcdefg"), mixed)
    }

    func testLineEndCaretsStopWhereTheSelectionDoes() {
        let text = "one\r\ntwo\nthree" as NSString
        XCTAssertEqual(
            MultiCaret.lineEndCarets(for: NSRange(location: 1, length: 11), in: text), carets(3, 8, 12),
            "the last caret is where the selection ends")
        XCTAssertEqual(
            MultiCaret.lineEndCarets(for: NSRange(location: 0, length: 9), in: text), carets(3, 8), "ending at a line start adds none there"
        )
        XCTAssertEqual(MultiCaret.lineEndCarets(for: NSRange(location: 2, length: 0), in: text), [])
    }
}
