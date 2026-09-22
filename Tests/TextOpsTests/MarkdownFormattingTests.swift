//
//  MarkdownFormattingTests.swift
//  Tests for TextOps.MarkdownFormatting
//
//  Inline styles toggle, block styles act per line and toggle off, a link wraps, and Return
//  continues or ends a list.
//
//  Created by David Sherlock on 9/22/26.
//

import XCTest
@testable import TextOps

final class MarkdownFormattingTests: XCTestCase {
    private func apply(_ e: MarkdownFormatting.Edit, to text: String) -> String {
        (text as NSString).replacingCharacters(in: e.range, with: e.replacement)
    }
    private func range(of s: String, in text: String) -> NSRange { (text as NSString).range(of: s) }

    func testInlineWrapsAndUnwrapsFromInsideAndOutside() {
        let t = "make it bold now"
        let wrap = MarkdownFormatting.toggle(.bold, in: t, selection: range(of: "bold", in: t))
        XCTAssertEqual(apply(wrap, to: t), "make it **bold** now")
        XCTAssertEqual(wrap.selection, NSRange(location: 10, length: 4), "the inner text stays selected")
        let wrapped = "make it **bold** now"
        let inside = MarkdownFormatting.toggle(.bold, in: wrapped, selection: range(of: "bold", in: wrapped))
        XCTAssertEqual(apply(inside, to: wrapped), t, "the markers just outside the selection come off")
        let outside = MarkdownFormatting.toggle(.bold, in: wrapped, selection: range(of: "**bold**", in: wrapped))
        XCTAssertEqual(apply(outside, to: wrapped), t, "a selection carrying its own markers comes off")
        XCTAssertEqual(outside.selection, NSRange(location: 8, length: 4))
    }

    func testItalicOnBoldAddsAThirdStarInsteadOfEatingOne() {
        let bold = "a **word** b"
        let e = MarkdownFormatting.toggle(.italic, in: bold, selection: range(of: "word", in: bold))
        XCTAssertEqual(apply(e, to: bold), "a ***word*** b")
        let both = "a ***word*** b"
        let off = MarkdownFormatting.toggle(.italic, in: both, selection: range(of: "word", in: both))
        XCTAssertEqual(apply(off, to: both), "a **word** b", "italic off leaves the bold")
    }

    func testNoSelectionTakesTheWordUnderTheCaretOrLeavesAnEmptyPair() {
        let t = "some code here"
        let word = MarkdownFormatting.toggle(.code, in: t, selection: NSRange(location: 7, length: 0))
        XCTAssertEqual(apply(word, to: t), "some `code` here")
        let empty = MarkdownFormatting.toggle(.strikethrough, in: "a  b", selection: NSRange(location: 2, length: 0))
        XCTAssertEqual(apply(empty, to: "a  b"), "a ~~~~ b")
        XCTAssertEqual(empty.selection, NSRange(location: 4, length: 0), "the caret sits between the markers")
    }

    func testHeadingsSetReplaceAndToggleOff() {
        let t = "Title\nbody"
        let h2 = MarkdownFormatting.toggle(.heading(2), in: t, selection: NSRange(location: 0, length: 0))
        XCTAssertEqual(apply(h2, to: t), "## Title\nbody")
        XCTAssertEqual(h2.selection, NSRange(location: 0, length: 8), "the whole line is selected, not its newline")
        let h1 = MarkdownFormatting.toggle(.heading(1), in: "## Title\nbody", selection: NSRange(location: 3, length: 0))
        XCTAssertEqual(apply(h1, to: "## Title\nbody"), "# Title\nbody", "a level replaces a level")
        let off = MarkdownFormatting.toggle(.heading(1), in: "# Title\nbody", selection: NSRange(location: 3, length: 0))
        XCTAssertEqual(apply(off, to: "# Title\nbody"), "Title\nbody")
    }

    func testListsActPerLineAndToggleOff() {
        let t = "one\ntwo\n\nthree"
        let all = NSRange(location: 0, length: (t as NSString).length)
        let bullets = apply(MarkdownFormatting.toggle(.bullets, in: t, selection: all), to: t)
        XCTAssertEqual(bullets, "- one\n- two\n\n- three", "blank lines are left alone")
        XCTAssertEqual(apply(MarkdownFormatting.toggle(.bullets, in: bullets, selection: NSRange(location: 0, length: (bullets as NSString).length)), to: bullets), t)
        let numbers = apply(MarkdownFormatting.toggle(.numbers, in: bullets, selection: NSRange(location: 0, length: (bullets as NSString).length)), to: bullets)
        XCTAssertEqual(numbers, "1. one\n2. two\n\n3. three", "a bulleted run becomes a numbered one")
        let tasks = apply(MarkdownFormatting.toggle(.tasks, in: "a\nb", selection: NSRange(location: 0, length: 3)), to: "a\nb")
        XCTAssertEqual(tasks, "- [ ] a\n- [ ] b")
        XCTAssertEqual(apply(MarkdownFormatting.toggle(.tasks, in: "- [x] a\n- [ ] b", selection: NSRange(location: 0, length: 15)), to: "- [x] a\n- [ ] b"), "a\nb")
        let one = MarkdownFormatting.toggle(.bullets, in: "x\ny", selection: NSRange(location: 2, length: 0))
        XCTAssertEqual(apply(one, to: "x\ny"), "x\n- y", "no selection: the caret's line only")
    }

    func testQuoteAndCodeBlock() {
        let q = apply(MarkdownFormatting.toggle(.quote, in: "a\n\nb", selection: NSRange(location: 0, length: 4)), to: "a\n\nb")
        XCTAssertEqual(q, "> a\n>\n> b")
        XCTAssertEqual(apply(MarkdownFormatting.toggle(.quote, in: q, selection: NSRange(location: 0, length: 9)), to: q), "a\n\nb")
        let t = "let a = 1\nlet b = 2\n"
        let fenced = MarkdownFormatting.toggle(.codeBlock, in: t, selection: NSRange(location: 0, length: 19))
        XCTAssertEqual(apply(fenced, to: t), "```\nlet a = 1\nlet b = 2\n```\n", "the trailing newline stays outside")
        let out = apply(fenced, to: t)
        XCTAssertEqual(apply(MarkdownFormatting.toggle(.codeBlock, in: out, selection: NSRange(location: 0, length: 27)), to: out), t)
    }

    func testLinkFromAWordAUrlOrNothing() {
        let word = MarkdownFormatting.link(in: "see docs now", selection: NSRange(location: 4, length: 4))
        XCTAssertEqual(apply(word, to: "see docs now"), "see [docs](url) now")
        XCTAssertEqual((("see [docs](url) now") as NSString).substring(with: word.selection), "url")
        let url = MarkdownFormatting.link(in: "https://x.io", selection: NSRange(location: 0, length: 12))
        XCTAssertEqual(apply(url, to: "https://x.io"), "[text](https://x.io)")
        XCTAssertEqual(("[text](https://x.io)" as NSString).substring(with: url.selection), "text")
        let none = MarkdownFormatting.link(in: "", selection: NSRange(location: 0, length: 0))
        XCTAssertEqual(apply(none, to: ""), "[text](url)")
    }

    func testReturnContinuesAListAndAnEmptyItemEndsIt() {
        let bullet = MarkdownFormatting.listContinuation(in: "- item", caret: 6)
        XCTAssertEqual(bullet.map { apply($0, to: "- item") }, "- item\n- ")
        XCTAssertEqual(bullet?.selection, NSRange(location: 9, length: 0))
        let number = MarkdownFormatting.listContinuation(in: "  9. nine", caret: 9)
        XCTAssertEqual(number.map { apply($0, to: "  9. nine") }, "  9. nine\n  10. ", "the number climbs and the indent stays")
        let task = MarkdownFormatting.listContinuation(in: "- [x] done", caret: 10)
        XCTAssertEqual(task.map { apply($0, to: "- [x] done") }, "- [x] done\n- [ ] ", "the next task is unticked")
        let quote = MarkdownFormatting.listContinuation(in: "> said", caret: 6)
        XCTAssertEqual(quote.map { apply($0, to: "> said") }, "> said\n> ")
        let empty = MarkdownFormatting.listContinuation(in: "- a\n- ", caret: 6)
        XCTAssertEqual(empty.map { apply($0, to: "- a\n- ") }, "- a\n", "an empty item drops its marker and adds no line")
        XCTAssertEqual(empty?.selection, NSRange(location: 4, length: 0))
        XCTAssertNil(MarkdownFormatting.listContinuation(in: "plain", caret: 5))
        XCTAssertNil(MarkdownFormatting.listContinuation(in: "- item", caret: 1), "a caret inside the marker is an ordinary Return")
        let mid = MarkdownFormatting.listContinuation(in: "- ab", caret: 3)
        XCTAssertEqual(mid.map { apply($0, to: "- ab") }, "- a\n- b", "a split item carries the rest down")
    }
}
