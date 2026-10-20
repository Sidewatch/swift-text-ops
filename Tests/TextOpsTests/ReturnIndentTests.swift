//
//  ReturnIndentTests.swift
//  TextOpsTests
//
//  What Return inserts: carried indentation, one unit after an opener, the closer on its own line.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import TextOps

/// `ReturnIndent.edit(in:at:unit:)`.
final class ReturnIndentTests: XCTestCase {
    private func apply(_ text: String, at range: NSRange, unit: String = "    ") -> (String, NSRange)? {
        guard let edit = ReturnIndent.edit(in: text as NSString, at: range, unit: unit) else { return nil }
        return ((text as NSString).replacingCharacters(in: edit.range, with: edit.replacement), edit.selection)
    }

    func testTheLinesIndentationIsCarried() throws {
        let (text, caret) = try XCTUnwrap(apply("    let a = 1\nnext", at: NSRange(location: 13, length: 0)))
        XCTAssertEqual(text, "    let a = 1\n    \nnext")
        XCTAssertEqual(caret, NSRange(location: 18, length: 0), "after the copied indent")
    }

    func testAnOpenerAddsOneUnitEvenWithTrailingSpaces() throws {
        XCTAssertEqual(try XCTUnwrap(apply("  if a {", at: NSRange(location: 8, length: 0), unit: "\t")).0, "  if a {\n  \t")
        XCTAssertEqual(try XCTUnwrap(apply("f(  ", at: NSRange(location: 4, length: 0))).0, "f(  \n    ")
    }

    func testATabIndentedLineCopiesItsTab() throws {
        XCTAssertEqual(try XCTUnwrap(apply("\tb()", at: NSRange(location: 4, length: 0))).0, "\tb()\n\t")
    }

    func testColumnZeroAndAnUnindentedLineNeedNothing() {
        XCTAssertNil(apply("    let a", at: NSRange(location: 0, length: 0)), "only the whitespace BEFORE the caret counts")
        XCTAssertNil(apply("plain", at: NSRange(location: 5, length: 0)))
    }

    func testASelectionIsReplacedAndIndentsFromItsLine() throws {
        let (text, _) = try XCTUnwrap(apply("    let a = 1", at: NSRange(location: 8, length: 5)))
        XCTAssertEqual(text, "    let \n    ")
    }

    func testReturnBetweenAPairPutsTheCloserOnItsOwnLine() throws {
        let (text, caret) = try XCTUnwrap(apply("    function f() {}", at: NSRange(location: 18, length: 0)))
        XCTAssertEqual(text, "    function f() {\n        \n    }")
        XCTAssertEqual(caret, NSRange(location: 18 + 1 + 8, length: 0), "on the indented middle line")
        XCTAssertEqual(try XCTUnwrap(apply("f() {}", at: NSRange(location: 5, length: 0))).0, "f() {\n    \n}", "a top-level pair")
    }

    func testTheIndentIsReadFromTheCaretsLineInACRLFFile() throws {
        XCTAssertEqual(try XCTUnwrap(apply("x\r\n  y", at: NSRange(location: 6, length: 0))).0, "x\r\n  y\n  ")
    }
}
