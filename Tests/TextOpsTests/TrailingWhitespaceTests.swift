//
//  TrailingWhitespaceTests.swift
//  TextOpsTests
//
//  Trim-on-save: runs before every break kind, breaks themselves untouched.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import TextOps

/// `TrailingWhitespace` and `LineOps.dedent`.
final class TrailingWhitespaceTests: XCTestCase {
    func testRunsBeforeEveryBreakKindGoAndTheBreaksStay() {
        let text = "a \t\r\nb  \rc\u{A0}\u{2028}d \n  e  "
        XCTAssertEqual(TrailingWhitespace.trimmed(text), "a\r\nb\rc\u{2028}d\n  e")
        XCTAssertEqual(TrailingWhitespace.ranges(in: text).count, 5)
    }

    func testIndentationAndInnerSpacesStay() {
        XCTAssertEqual(TrailingWhitespace.trimmed("  a  b\n\tc"), "  a  b\n\tc")
        XCTAssertEqual(TrailingWhitespace.trimmed("a \n\n\r\nb"), "a\n\n\r\nb", "blank lines after a run keep their breaks")
    }

    func testDedentRemovesTheSharedIndentOnly() {
        XCTAssertEqual(LineOps.dedent(["    a", "      b", "", "    c"]), ["a", "  b", "", "c"])
        XCTAssertEqual(LineOps.dedent(["\t\tx", "\ty"]), ["\tx", "y"])
        XCTAssertEqual(LineOps.dedent(["    a\r", "\r", "      b\r"]), ["a\r", "\r", "  b\r"], "a blank CRLF line does not count")
        XCTAssertEqual(LineOps.dedent(["a", "  b"]), ["a", "  b"], "nothing shared")
    }

    /// A selection begun after the indentation of its first line: that line counts as indented to the start.
    func testASelectionBegunAfterTheIndentStillLosesIt() {
        // "    if x {" selected from the "i": the first line arrives without its four spaces.
        XCTAssertEqual(LineOps.dedent(["if x {", "        y()", "    }"], startColumn: 4), ["if x {", "    y()", "}"])
        XCTAssertEqual(LineOps.dedent(["  b()", "      c()"], startColumn: 2), ["b()", "  c()"], "begun inside the indent")
        XCTAssertEqual(LineOps.dedent(["\tx", "\t\t\ty"], startColumn: 1), ["x", "\ty"], "tabs count as characters")
        XCTAssertEqual(LineOps.dedent(["    one"], startColumn: 0), ["one"], "one line loses its own indent")
        XCTAssertEqual(LineOps.dedent(["x()"], startColumn: 8), ["x()"], "one line begun after its indent has none left")
    }

    /// Begun after code on its line: the first line sets nothing and loses nothing.
    func testASelectionBegunAfterCodeLeavesItsFirstLine() {
        XCTAssertEqual(LineOps.dedent(["foo(a,", "        b,", "        c)"], startColumn: nil), ["foo(a,", "b,", "c)"])
        XCTAssertEqual(LineOps.dedent(["  tail", "    next"], startColumn: nil), ["  tail", "next"])
    }
}
