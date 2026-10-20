//
//  BracketMatchTests.swift
//  TextOpsTests
//
//  The bracket the caret is on and its partner: nesting, direction, the cap, unmatched pairs.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import TextOps

/// `BracketMatch`.
final class BracketMatchTests: XCTestCase {
    func testTheBracketAtTheCaretWinsOverTheOneBeforeIt() {
        let text = "a()" as NSString
        XCTAssertEqual(BracketMatch.bracket(near: 1, in: text), 1, "on the opener")
        XCTAssertEqual(BracketMatch.bracket(near: 3, in: text), 2, "just past the closer, as typing leaves it")
        XCTAssertNil(BracketMatch.bracket(near: 0, in: text), "neither side is a bracket")
        XCTAssertNil(BracketMatch.bracket(near: 9, in: text), "past the end is not a crash")
    }

    func testNestedPairsMatchByDepthInBothDirections() {
        let text = "f(a(b)[c]{d})" as NSString
        XCTAssertEqual(BracketMatch.partner(of: 1, in: text), 12, "the outer opener skips the inner pairs")
        XCTAssertEqual(BracketMatch.partner(of: 12, in: text), 1, "and the outer closer walks back past them")
        XCTAssertEqual(BracketMatch.partner(of: 3, in: text), 5)
        XCTAssertEqual(BracketMatch.partner(of: 6, in: text), 8, "square brackets")
        XCTAssertEqual(BracketMatch.partner(of: 11, in: text), 9, "braces, backward")
    }

    func testAnUnmatchedOrNonBracketIndexHasNoPartner() {
        XCTAssertNil(BracketMatch.partner(of: 0, in: "((x)" as NSString), "never closes")
        XCTAssertNil(BracketMatch.partner(of: 0, in: "x)" as NSString), "not a bracket")
        XCTAssertNil(BracketMatch.partner(of: 1, in: "x)" as NSString), "a closer with no opener")
    }

    func testTheCapBoundsTheWalkEachWay() {
        let text = ("(" + String(repeating: "x", count: 10) + ")") as NSString
        XCTAssertEqual(BracketMatch.partner(of: 0, in: text, cap: 12), 11, "the closer is inside the cap")
        XCTAssertNil(BracketMatch.partner(of: 0, in: text, cap: 11), "one unit short")
        XCTAssertEqual(BracketMatch.partner(of: 11, in: text, cap: 12), 0)
        XCTAssertNil(BracketMatch.partner(of: 11, in: text, cap: 11))
    }

    func testThePairsAreAutoClosesBrackets() {
        XCTAssertEqual(BracketMatch.openToClose.count, AutoClose.brackets.count)
        for (open, close) in AutoClose.brackets {
            XCTAssertEqual(BracketMatch.openToClose[open.utf16.first!], close.utf16.first!)
        }
    }

    /// Half a million units, the default cap, stays near a millisecond.
    func testTheDefaultCapWalkIsFast() {
        let text = ("{" + String(repeating: "a", count: BracketMatch.defaultCap - 2) + "}") as NSString
        let start = Date()
        XCTAssertEqual(BracketMatch.partner(of: 0, in: text), text.length - 1)
        let ms = Date().timeIntervalSince(start) * 1000
        print("BracketMatch: \(BracketMatch.defaultCap) units in \(String(format: "%.2f", ms)) ms")
        XCTAssertLessThan(ms, 50, "a debug build; the release walk is about 1 ms")
    }
}
