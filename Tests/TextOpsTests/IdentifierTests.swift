//
//  IdentifierTests.swift
//  TextOpsTests
//
//  Tests for `Identifier.range(at:in:)`: the whole word from any of its units, nil off a word
//  and past the end.
//
//  Created by David Sherlock on 9/5/26.
//

import XCTest
@testable import TextOps

/// Tests for `Identifier.range(at:in:)`: the whole word from any of its units, nil off a word
/// and past the end.
final class IdentifierTests: XCTestCase {

    func testRangeCoversTheWholeWordFromAnyOfItsUnits() {
        let ns = "let $foo_bar = 1" as NSString      // `$foo_bar` is 4..<12
        for i in 4..<12 { XCTAssertEqual(Identifier.range(at: i, in: ns), NSRange(location: 4, length: 8), "at \(i)") }
    }

    func testRangeIsNilOffAWordAndPastTheEnd() {
        let ns = "a b" as NSString
        XCTAssertNil(Identifier.range(at: 1, in: ns))
        XCTAssertNil(Identifier.range(at: 3, in: ns))
        XCTAssertNil(Identifier.range(at: -1, in: ns))
    }

    func testRangeNearCaretNudgesLeftWhenJustPastAWord() {
        let ns = "foo bar" as NSString
        XCTAssertEqual(Identifier.range(nearCaret: 3, in: ns), NSRange(location: 0, length: 3), "caret after foo")
        XCTAssertEqual(Identifier.range(nearCaret: 7, in: ns), NSRange(location: 4, length: 3), "caret at the end")
        XCTAssertEqual(Identifier.range(nearCaret: 4, in: ns), NSRange(location: 4, length: 3), "caret on bar")
        XCTAssertNil(Identifier.range(nearCaret: 0, in: " x" as NSString))
    }

    func testUnitsAreLettersDigitsUnderscoreAndDollar() {
        for c in "aZ9_$é" { XCTAssertTrue(Identifier.isUnit(unichar(c.unicodeScalars.first!.value)), "\(c)") }
        for c in " -.(:" { XCTAssertFalse(Identifier.isUnit(unichar(c.unicodeScalars.first!.value)), "\(c)") }
    }

    func testWholeWordMatchesFindEveryOccurrence() {
        XCTAssertEqual(WholeWord.matches(of: "foo", in: "foo food foo" as NSString),
                       [NSRange(location: 0, length: 3), NSRange(location: 9, length: 3)])
        XCTAssertEqual(WholeWord.matches(of: "==", in: "a == b == c" as NSString).count, 2, "a non-word needle still matches")
        XCTAssertEqual(WholeWord.matches(of: "", in: "abc" as NSString), [])
    }
}
