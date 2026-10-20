//
//  CommentToggleTests.swift
//  TextOpsTests
//
//  Line and block comment toggles: round trips, blank lines, every break kind, two comments.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import TextOps

/// `CommentToggle`.
final class CommentToggleTests: XCTestCase {
    private func lineToggle(_ text: String, _ selection: NSRange, token: String = "//") -> String {
        let edit = CommentToggle.line(in: text as NSString, selection: selection, token: token)
        return (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
    }

    private func blockToggle(_ text: String, _ selection: NSRange) -> String? {
        guard let edit = CommentToggle.block(in: text as NSString, selection: selection, open: "/*", close: "*/") else { return nil }
        return (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
    }

    func testLineCommentsGoAfterTheIndentAndRoundTrip() {
        let text = "  a()\n\n\tb()\nc()"
        let all = NSRange(location: 0, length: (text as NSString).length)
        let commented = lineToggle(text, all)
        XCTAssertEqual(commented, "  // a()\n\n\t// b()\n// c()", "blank lines untouched")
        XCTAssertEqual(lineToggle(commented, NSRange(location: 0, length: (commented as NSString).length)), text)
    }

    func testAMixOfCommentedAndPlainLinesComments() {
        XCTAssertEqual(lineToggle("// a\nb\n", NSRange(location: 0, length: 6)), "// // a\n// b\n")
    }

    func testEveryLineKeepsItsOwnBreak() {
        let text = "a\r\nb\rc\u{2028}d\n"
        let out = lineToggle(text, NSRange(location: 0, length: (text as NSString).length), token: "#")
        XCTAssertEqual(out, "# a\r\n# b\r# c\u{2028}# d\n", "CRLF, a lone CR and LS each end a line")
    }

    func testABlankCRLFLineDoesNotBlockUncommenting() {
        let text = "// a\r\n\r\n// b\r\n"
        XCTAssertEqual(lineToggle(text, NSRange(location: 0, length: (text as NSString).length)), "a\r\n\r\nb\r\n")
    }

    func testTheCaretsLineAloneWithoutASelection() {
        XCTAssertEqual(lineToggle("a\nb\nc", NSRange(location: 2, length: 0)), "a\n// b\nc")
    }

    func testBlockCommentsWrapTheContentAndRoundTrip() throws {
        let text = "  value + 1  \n"
        let wrapped = try XCTUnwrap(blockToggle(text, NSRange(location: 0, length: 0)))
        XCTAssertEqual(wrapped, "  /* value + 1 */  \n", "the content, not the whitespace around it")
        XCTAssertEqual(blockToggle(wrapped, NSRange(location: 0, length: 0)), text)
    }

    func testTwoCommentsAreWrappedNotUnwrapped() {
        let text = "/* a */ x /* b */"
        XCTAssertEqual(blockToggle(text, NSRange(location: 0, length: 17)), "/* /* a */ x /* b */ */")
    }

    func testOnlyDelimitersOrBlankIsHandled() {
        XCTAssertEqual(blockToggle("/**/", NSRange(location: 0, length: 4)), "", "just the delimiters unwrap to nothing")
        XCTAssertNil(blockToggle("   \n", NSRange(location: 0, length: 0)), "a blank line has no content")
    }
}
