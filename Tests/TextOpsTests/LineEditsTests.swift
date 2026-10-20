//
//  LineEditsTests.swift
//  TextOpsTests
//
//  `LineEdits` on LF and CRLF text: delete, move, duplicate, indent, unindent — no stray `\r`,
//  no welded lines, no doubled breaks — and the no-op cases.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import TextOps

/// `LineEdits` on LF and CRLF text.
final class LineEditsTests: XCTestCase {
    /// `text` with `edit` applied.
    private func apply(_ edit: TextEdit?, to text: String) -> String {
        guard let edit else { return text }
        return (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
    }
    /// The caret placed at the start of line `n` (0-based) of `text`.
    private func caret(line n: Int, in text: String) -> NSRange {
        var at = 0
        let ns = text as NSString
        for _ in 0..<n { at = NSMaxRange(ns.lineRange(for: NSRange(location: at, length: 0))) }
        return NSRange(location: at, length: 0)
    }

    // MARK: Delete

    func testDeletingTheLastLineOfACRLFFileLeavesNoStrayReturn() {
        let text = "one\r\ntwo\r\nthree"
        XCTAssertEqual(apply(LineEdits.deleteLine(in: text, selection: caret(line: 2, in: text)), to: text), "one\r\ntwo")
    }

    func testDeletingAMiddleLineTakesItsWholeBreak() {
        let text = "one\r\ntwo\r\nthree"
        XCTAssertEqual(apply(LineEdits.deleteLine(in: text, selection: caret(line: 1, in: text)), to: text), "one\r\nthree")
        XCTAssertEqual(apply(LineEdits.deleteLine(in: "a\nb\nc", selection: caret(line: 2, in: "a\nb\nc")), to: "a\nb\nc"), "a\nb")
    }

    func testDeletingTheOnlyLineEmptiesTheText() {
        XCTAssertEqual(apply(LineEdits.deleteLine(in: "solo", selection: NSRange(location: 2, length: 0)), to: "solo"), "")
    }

    // MARK: Move

    func testMovingTheUnterminatedLastLineUpKeepsTwoLines() {
        let text = "one\r\ntwo"
        let edit = LineEdits.moveUp(in: text, selection: caret(line: 1, in: text))
        XCTAssertEqual(apply(edit, to: text), "two\r\none")
        XCTAssertEqual(edit?.selection.location, 0, "the caret moves with its line")
    }

    func testMovingALineDownOntoTheUnterminatedLastLine() {
        let text = "one\r\ntwo"
        XCTAssertEqual(apply(LineEdits.moveDown(in: text, selection: caret(line: 0, in: text)), to: text), "two\r\none")
        XCTAssertEqual(apply(LineEdits.moveDown(in: "a\nb", selection: caret(line: 0, in: "a\nb")), to: "a\nb"), "b\na")
    }

    func testMovingPastTheEdgesDoesNothing() {
        XCTAssertNil(LineEdits.moveUp(in: "a\nb", selection: caret(line: 0, in: "a\nb")))
        XCTAssertNil(LineEdits.moveDown(in: "a\nb", selection: caret(line: 1, in: "a\nb")))
    }

    // MARK: Duplicate

    func testDuplicatingACRLFLineDoublesItWithOneBreakEach() {
        let text = "one\r\ntwo\r\n"
        XCTAssertEqual(
            apply(LineEdits.duplicate(in: text, selection: caret(line: 0, in: text), followCopy: false), to: text), "one\r\none\r\ntwo\r\n")
    }

    func testDuplicatingTheUnterminatedLastLineSuppliesTheFilesBreak() {
        let text = "one\r\ntwo"
        XCTAssertEqual(
            apply(LineEdits.duplicate(in: text, selection: caret(line: 1, in: text), followCopy: true), to: text), "one\r\ntwo\r\ntwo")
        XCTAssertEqual(apply(LineEdits.duplicate(in: "x", selection: NSRange(location: 0, length: 0), followCopy: true), to: "x"), "x\nx")
    }

    func testDuplicateFollowsTheChosenCopy() {
        let text = "ab\n"
        XCTAssertEqual(LineEdits.duplicate(in: text, selection: NSRange(location: 1, length: 0), followCopy: false)?.selection.location, 1)
        XCTAssertEqual(LineEdits.duplicate(in: text, selection: NSRange(location: 1, length: 0), followCopy: true)?.selection.location, 4)
    }

    // MARK: Indent

    func testIndentingACRLFBlockIndentsOnlyItsOwnLines() {
        let text = "a\r\nb\r\nc"
        let selection = NSRange(location: 0, length: 6)  // "a\r\nb\r\n": two lines, ending after the second break
        XCTAssertEqual(apply(LineEdits.indent(in: text, selection: selection, unit: "  "), to: text), "  a\r\n  b\r\nc")
    }

    func testIndentNeedsALineBreakInTheSelection() {
        XCTAssertNil(LineEdits.indent(in: "abc\ndef", selection: NSRange(location: 0, length: 2), unit: "\t"))
        XCTAssertNil(LineEdits.indent(in: "abc", selection: NSRange(location: 0, length: 0), unit: "\t"))
        XCTAssertNotNil(
            LineEdits.indent(in: "abc\ndef", selection: NSRange(location: 0, length: 4), unit: "\t"), "a whole line with its break")
    }

    func testUnindentRemovesOneLevelPerLineAndKeepsCRLF() {
        let text = "\ta\r\n      b\r\nc"
        let edit = LineEdits.unindent(in: text, selection: NSRange(location: 0, length: (text as NSString).length), width: 4)
        XCTAssertEqual(apply(edit, to: text), "a\r\n  b\r\nc")
        XCTAssertNil(LineEdits.unindent(in: "flush\nleft", selection: NSRange(location: 0, length: 3), width: 4), "nothing to remove")
    }
}
