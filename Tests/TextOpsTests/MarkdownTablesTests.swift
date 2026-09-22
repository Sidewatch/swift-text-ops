//
//  MarkdownTablesTests.swift
//  Tests for TextOps.MarkdownFormatting (tables)
//
//  The pipe table at the caret is read as cells, formatted aligned, grown and shrunk by a row or
//  a column, and a new one is inserted on its own paragraph.
//
//  Created by David Sherlock on 9/22/26.
//

import XCTest
@testable import TextOps

final class MarkdownTablesTests: XCTestCase {
    private func apply(_ e: MarkdownFormatting.Edit, to text: String) -> String {
        (text as NSString).replacingCharacters(in: e.range, with: e.replacement)
    }
    private func caret(_ s: String, in text: String) -> NSRange { NSRange(location: (text as NSString).range(of: s).location, length: 0) }

    private let ugly = "intro\n|Name|Qty|Price|\n|:--|--:|:-:|\n|apple|1|0.5|\n|kiwi \\| gold|12|10|\n\nafter"
    private let pretty = "intro\n| Name         | Qty | Price |\n| :----------- | --: | :---: |\n| apple        |   1 |  0.5  |\n| kiwi \\| gold |  12 |  10   |\n\nafter"

    func testTheTableAtTheCaretIsReadAsCellsWithAlignmentsAndTheCaretsCell() throws {
        let t = try XCTUnwrap(MarkdownFormatting.table(in: ugly, selection: caret("12", in: ugly)))
        XCTAssertEqual(t.rows, [["Name", "Qty", "Price"], ["apple", "1", "0.5"], ["kiwi \\| gold", "12", "10"]], "the separator is not a row; an escaped pipe stays in its cell")
        XCTAssertEqual(t.alignments, [.left, .right, .center])
        XCTAssertEqual((t.row, t.column).0, 2)
        XCTAssertEqual(t.column, 1)
        XCTAssertEqual((ugly as NSString).substring(with: t.range), "|Name|Qty|Price|\n|:--|--:|:-:|\n|apple|1|0.5|\n|kiwi \\| gold|12|10|", "the lines of the table, without the blank line after")
        XCTAssertEqual(MarkdownFormatting.table(in: ugly, selection: caret("Price", in: ugly))?.row, 0)
        XCTAssertEqual(MarkdownFormatting.table(in: ugly, selection: caret(":-:", in: ugly))?.row, 0, "the separator line counts as the header")
        XCTAssertEqual(MarkdownFormatting.table(in: ugly, selection: caret("Price", in: ugly))?.column, 2)
    }

    func testNoTableOutsideOneOrWithoutASeparatorRow() {
        XCTAssertNil(MarkdownFormatting.table(in: ugly, selection: caret("intro", in: ugly)))
        XCTAssertNil(MarkdownFormatting.table(in: ugly, selection: caret("after", in: ugly)))
        let noSeparator = "|a|b|\n|c|d|"
        XCTAssertNil(MarkdownFormatting.table(in: noSeparator, selection: caret("c", in: noSeparator)))
        XCTAssertNil(MarkdownFormatting.table(in: "x | y", selection: NSRange(location: 0, length: 0)), "one line with a pipe is prose")
        XCTAssertFalse(MarkdownFormatting.context(in: ugly, selection: caret("intro", in: ugly)).table)
        XCTAssertTrue(MarkdownFormatting.context(in: ugly, selection: caret("apple", in: ugly)).table)
        XCTAssertNil(MarkdownFormatting.context(in: ugly, selection: caret("apple", in: ugly)).block, "a table row is no other block")
    }

    func testFormatAlignsEveryColumnAndKeepsTheColons() {
        let e = MarkdownFormatting.table(.format, in: ugly, selection: caret("12", in: ugly))!
        XCTAssertEqual(apply(e, to: ugly), pretty)
        XCTAssertEqual((apply(e, to: ugly) as NSString).substring(with: NSRange(location: e.selection.location, length: 2)), "12", "the caret lands on its cell's text")
        XCTAssertEqual(MarkdownFormatting.table(.format, in: pretty, selection: caret("12", in: pretty)).map { apply($0, to: pretty) }, pretty, "formatting a formatted table changes nothing")
    }

    func testRaggedRowsAndMissingOuterPipesAreNormalised() {
        // A row must carry a pipe (GFM ends the table at a line without one); short rows pad.
        let ragged = "a | b\n--|--\n1 |\n2 | 3 | 4"
        let e = MarkdownFormatting.table(.format, in: ragged, selection: caret("1 |", in: ragged))!
        XCTAssertEqual(apply(e, to: ragged), "| a   | b   |     |\n| --- | --- | --- |\n| 1   |     |     |\n| 2   | 3   | 4   |")
    }

    func testRowsAreInsertedAndDeletedAroundTheCaret() {
        let below = MarkdownFormatting.table(.insertRowBelow, in: pretty, selection: caret("apple", in: pretty))!
        let withRow = apply(below, to: pretty)
        XCTAssertEqual(withRow.components(separatedBy: "\n")[4], "|              |     |       |")
        XCTAssertEqual(withRow.components(separatedBy: "\n")[3], "| apple        |   1 |  0.5  |")
        XCTAssertEqual(below.selection, NSRange(location: (withRow as NSString).range(of: "|              |").location + 2, length: 0), "the caret is in the new row's first cell")
        let aboveHeader = MarkdownFormatting.table(.insertRowAbove, in: pretty, selection: caret("Name", in: pretty))!
        XCTAssertEqual(apply(aboveHeader, to: pretty).components(separatedBy: "\n")[3], "|              |     |       |", "above the header goes below it")
        let deleted = MarkdownFormatting.table(.deleteRow, in: pretty, selection: caret("apple", in: pretty))!
        XCTAssertEqual(apply(deleted, to: pretty), "intro\n| Name         | Qty | Price |\n| :----------- | --: | :---: |\n| kiwi \\| gold |  12 |  10   |\n\nafter")
        XCTAssertNil(MarkdownFormatting.table(.deleteRow, in: pretty, selection: caret("Name", in: pretty)), "the header cannot be deleted")
    }

    func testColumnsAreInsertedAndDeletedAtTheCaret() {
        let after = MarkdownFormatting.table(.insertColumnAfter, in: pretty, selection: caret("Qty", in: pretty))!
        let grown = apply(after, to: pretty)
        XCTAssertEqual(grown.components(separatedBy: "\n")[1], "| Name         | Qty |     | Price |")
        XCTAssertEqual(grown.components(separatedBy: "\n")[2], "| :----------- | --: | --- | :---: |")
        XCTAssertEqual(after.selection.location, (grown as NSString).range(of: "| Qty |     |").location + 8, "the caret is in the new column's header cell")
        let before = MarkdownFormatting.table(.insertColumnBefore, in: pretty, selection: caret("Name", in: pretty))!
        XCTAssertTrue(apply(before, to: pretty).components(separatedBy: "\n")[1].hasPrefix("|     | Name "))
        let dropped = MarkdownFormatting.table(.deleteColumn, in: pretty, selection: caret("Qty", in: pretty))!
        XCTAssertEqual(apply(dropped, to: pretty).components(separatedBy: "\n")[1], "| Name         | Price |")
        XCTAssertEqual(apply(dropped, to: pretty).components(separatedBy: "\n")[2], "| :----------- | :---: |")
        let one = "| a |\n| - |\n| 1 |"
        XCTAssertNil(MarkdownFormatting.table(.deleteColumn, in: one, selection: caret("1", in: one)), "the only column stays")
    }

    /// Delete Row on the last body row leaves header + separator; reading that (the bar's
    /// context does, on every caret move) crashed on an invalid closed range (22 Sep 2026).
    func testAHeaderOnlyTableReadsFormatsAndGrowsARow() throws {
        let headerOnly = "| a   |     | b   |\n| --- | --- | --- |\n"
        let t = try XCTUnwrap(MarkdownFormatting.table(in: headerOnly, selection: caret("b", in: headerOnly)))
        XCTAssertEqual(t.rows, [["a", "", "b"]])
        XCTAssertEqual(t.row, 0)
        XCTAssertEqual(t.column, 2)
        XCTAssertTrue(MarkdownFormatting.context(in: headerOnly, selection: caret("---", in: headerOnly)).table)
        XCTAssertEqual(MarkdownFormatting.table(.format, in: headerOnly, selection: caret("a", in: headerOnly)).map { apply($0, to: headerOnly) }, headerOnly)
        let grown = MarkdownFormatting.table(.insertRowBelow, in: headerOnly, selection: caret("a", in: headerOnly))!
        XCTAssertEqual(apply(grown, to: headerOnly), "| a   |     | b   |\n| --- | --- | --- |\n|     |     |     |\n")
        XCTAssertNil(MarkdownFormatting.table(.deleteRow, in: headerOnly, selection: caret("a", in: headerOnly)))
    }

    func testInsertTableTakesABlankLineOrStartsAParagraphAfterText() {
        let blank = "text\n\nmore"
        let e = MarkdownFormatting.insertTable(in: blank, selection: NSRange(location: 5, length: 0))
        let out = apply(e, to: blank)
        XCTAssertEqual(out, "text\n| Column 1 | Column 2 | Column 3 |\n| -------- | -------- | -------- |\n|          |          |          |\n|          |          |          |\nmore")
        XCTAssertEqual((out as NSString).substring(with: e.selection), "Column 1", "the first header cell is selected to type over")
        let inline = "text"
        let e2 = MarkdownFormatting.insertTable(in: inline, selection: NSRange(location: 2, length: 0), columns: 2, rows: 1)
        let out2 = apply(e2, to: inline)
        XCTAssertEqual(out2, "text\n\n| Column 1 | Column 2 |\n| -------- | -------- |\n|          |          |")
        XCTAssertEqual((out2 as NSString).substring(with: e2.selection), "Column 1")
    }
}
