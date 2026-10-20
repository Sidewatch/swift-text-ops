//
//  LineStartIndexTests.swift
//  TextOpsTests
//
//  The line-start index: every break kind, lookups, and the splice fuzzed against a full rescan.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import TextOps

/// `LineStartIndex` and `LineRemap`.
final class LineStartIndexTests: XCTestCase {
    func testEveryBreakKindEndsALineAndCRLFIsOne() {
        let text = "a\nb\r\nc\rd\u{85}e\u{2028}f\u{2029}g" as NSString
        XCTAssertEqual(LineStartIndex(scanning: text).starts, [0, 2, 5, 7, 9, 11, 13])
    }

    func testTheEmptyLineAfterAFinalBreakHasNoEntry() {
        XCTAssertEqual(LineStartIndex(scanning: "a\nb\n").starts, [0, 2])
        XCTAssertEqual(LineStartIndex(scanning: "").starts, [0])
    }

    func testLookupsBothWays() {
        let index = LineStartIndex(scanning: "one\ntwo\nthree")
        XCTAssertEqual(index.line(containing: 0), 1)
        XCTAssertEqual(index.line(containing: 3), 1, "the break belongs to its line")
        XCTAssertEqual(index.line(containing: 4), 2)
        XCTAssertEqual(index.line(containing: 99), 3, "past the end is the last line")
        XCTAssertEqual(index.start(ofLine: 3), 8)
        XCTAssertNil(index.start(ofLine: 0))
        XCTAssertNil(index.start(ofLine: 4))
    }

    func testEditSpanNamesTheEditsFirstLineAndPastItsLast() {
        let index = LineStartIndex(scanning: "a\nb\nc\nd")  // starts 0, 2, 4, 6
        XCTAssertEqual(index.editSpan(editLocation: 1, oldSpanEnd: 1).edit, 0)
        XCTAssertEqual(index.editSpan(editLocation: 1, oldSpanEnd: 1).spanEnd, 1, "inside one line")
        XCTAssertEqual(index.editSpan(editLocation: 1, oldSpanEnd: 5).spanEnd, 3, "the span reached line 3")
        XCTAssertEqual(
            index.editSpan(editLocation: 1, oldSpanEnd: 4).spanEnd, 3,
            "a span ending exactly at line 3's start took the break before it, so line 3 merged into the edit")
    }

    func testTheRemapKeepsDropsAndSlides() {
        let remap = LineRemap(editLine: 4, spanEndLine: 6, lineDelta: 2)
        XCTAssertEqual(remap.line(4), 4)
        XCTAssertNil(remap.line(5), "its text was replaced")
        XCTAssertNil(remap.line(6))
        XCTAssertEqual(remap.line(7), 9)
    }

    /// 6,000 random edits over text holding every break kind: after each, the spliced index must equal a
    /// full rescan. Inserting `\n` after a `\r`, deleting half a CRLF and replacing across breaks are all
    /// in the mix, because those are the cases bookkeeping gets wrong.
    func testTheSpliceMatchesARescanThroughRandomEdits() {
        var rng = SplitMix(seed: 0x5EED)
        let pieces = ["a", "bc", "\n", "\r", "\r\n", "\u{2028}", "\u{85}", "\u{2029}", "😀", "  "]
        func random(_ n: Int) -> String { (0..<n).map { _ in pieces[Int(rng.next() % UInt64(pieces.count))] }.joined() }
        let text = NSMutableString(string: random(60))
        var index = LineStartIndex(scanning: text)
        for step in 0..<6_000 {
            let length = text.length
            let location = length == 0 ? 0 : Int(rng.next() % UInt64(length + 1))
            let span = min(length - location, Int(rng.next() % 6))
            let insert = random(Int(rng.next() % 4))
            text.replaceCharacters(in: NSRange(location: location, length: span), with: insert)
            let inserted = (insert as NSString).length
            index.splice(edited: NSRange(location: location, length: inserted), delta: inserted - span, in: text)
            let truth = LineStartIndex(scanning: text)
            if index != truth {
                XCTFail("step \(step): spliced \(index.starts) != rescanned \(truth.starts) for \(Array((text as String).utf16))")
                return
            }
            if text.length > 400 { text.deleteCharacters(in: NSRange(location: 0, length: 200)); index = LineStartIndex(scanning: text) }
        }
    }

    /// A keystroke's splice on a 200,000-line text stays far under a frame.
    func testASpliceOnALargeTextIsCheap() {
        let text = NSMutableString(string: String(repeating: "let value = compute(input)\n", count: 200_000))
        var index = LineStartIndex(scanning: text)
        let middle = text.length / 2
        let start = Date()
        for i in 0..<100 {
            text.insert("\n", at: middle + i)
            index.splice(edited: NSRange(location: middle + i, length: 1), delta: 1, in: text)
        }
        let perEdit = Date().timeIntervalSince(start) * 1000 / 100
        print("LineStartIndex: splice on 200,000 lines \(String(format: "%.3f", perEdit)) ms per edit (debug build)")
        XCTAssertEqual(index.count, 200_100)
        XCTAssertLessThan(perEdit, 16, "a frame, even unoptimised")
    }
}

/// A deterministic generator, so a failing fuzz step replays.
private struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
