//
//  TextSearchTests.swift
//  TextOpsTests
//
//  Find and replace: matches, wrapping next and previous, zero-width regexes, templates, the caret.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import TextOps

/// `TextSearch`.
final class TextSearchTests: XCTestCase {
    func testPlainMatchesNeverOverlapAndHonourTheOptions() {
        XCTAssertEqual(TextSearch.ranges(of: "aa", in: "aaaa"), [NSRange(location: 0, length: 2), NSRange(location: 2, length: 2)])
        let accented = "caf\u{E9} cafe\u{301}" as NSString
        XCTAssertEqual(TextSearch.ranges(of: "caf\u{E9}", in: accented).count, 2, "canonical equivalence by default")
        XCTAssertEqual(TextSearch.ranges(of: "caf\u{E9}", in: accented, options: [.literal]).count, 1, ".literal turns it off")
        XCTAssertEqual(TextSearch.ranges(of: "", in: "abc"), [])
    }

    func testTheFindBarsQueryIsCaseFoldedOrARegex() {
        let text = "Foo foo FOO" as NSString
        XCTAssertEqual(TextSearch.ranges(of: "foo", in: text, caseSensitive: false, regex: false).count, 3)
        XCTAssertEqual(TextSearch.ranges(of: "foo", in: text, caseSensitive: true, regex: false).count, 1)
        XCTAssertEqual(TextSearch.ranges(of: "f[o]+", in: text, caseSensitive: false, regex: true).count, 3)
        XCTAssertEqual(TextSearch.ranges(of: "(", in: text, caseSensitive: false, regex: true), [], "an invalid pattern matches nothing")
    }

    func testAZeroWidthRegexMatchesNothingAnywhere() {
        let text = "ab" as NSString
        XCTAssertEqual(TextSearch.ranges(of: "x*", in: text, caseSensitive: false, regex: true), [])
        XCTAssertNil(TextSearch.next("x*", from: 0, in: text, caseSensitive: false, regex: true), "Find Next never selects an empty match")
        XCTAssertEqual(
            TextSearch.next("b*", from: 0, in: text, caseSensitive: false, regex: true), NSRange(location: 1, length: 1),
            "it skips to the real one")
    }

    func testNextAndPreviousWrap() {
        let text = "one two one" as NSString
        XCTAssertEqual(TextSearch.next("one", from: 1, in: text, caseSensitive: true, regex: false), NSRange(location: 8, length: 3))
        XCTAssertEqual(
            TextSearch.next("one", from: 9, in: text, caseSensitive: true, regex: false), NSRange(location: 0, length: 3),
            "wraps to the top")
        XCTAssertEqual(TextSearch.previous("one", before: 8, in: text, caseSensitive: true, regex: false), NSRange(location: 0, length: 3))
        XCTAssertEqual(
            TextSearch.previous("one", before: 2, in: text, caseSensitive: true, regex: false), NSRange(location: 8, length: 3),
            "wraps to the bottom")
        XCTAssertEqual(
            TextSearch.previous("o\\w+", before: 2, in: text, caseSensitive: true, regex: true), NSRange(location: 8, length: 3),
            "regex wraps too")
        XCTAssertEqual(
            TextSearch.previous("o\\w+", before: 8, in: text, caseSensitive: true, regex: true), NSRange(location: 0, length: 3),
            "regex: the one before")
        XCTAssertEqual(
            TextSearch.next("o\\w+", from: 9, in: text, caseSensitive: true, regex: true), NSRange(location: 0, length: 3),
            "regex Find Next wraps to the top")
        XCTAssertNil(TextSearch.next("zzz", from: 0, in: text, caseSensitive: true, regex: false))
    }

    func testReplaceOnlyReplacesASelectionThatIsAMatch() {
        XCTAssertEqual(
            TextSearch.replacement(forSelection: "FOO", query: "foo", template: "bar", caseSensitive: false, regex: false), "bar")
        XCTAssertNil(TextSearch.replacement(forSelection: "FOO", query: "foo", template: "bar", caseSensitive: true, regex: false))
        XCTAssertEqual(
            TextSearch.replacement(forSelection: "x=12", query: "(\\w)=(\\d+)", template: "$2:$1", caseSensitive: true, regex: true), "12:x"
        )
        XCTAssertNil(
            TextSearch.replacement(forSelection: "x=12;", query: "(\\w)=(\\d+)", template: "$2", caseSensitive: true, regex: true),
            "the match must be the whole selection")
    }

    func testReplaceAllExpandsTheTemplatePerMatch() {
        let edits = TextSearch.replaceAll("(\\d+)px", with: "$1rem", in: "1px 20px", caseSensitive: true, regex: true)
        XCTAssertEqual(edits.map(\.replacement), ["1rem", "20rem"])
        XCTAssertEqual(edits.map(\.range), [NSRange(location: 0, length: 3), NSRange(location: 4, length: 4)])
        XCTAssertEqual(
            TextSearch.replaceAll("$1", with: "x", in: "a $1 b", caseSensitive: true, regex: false).map(\.replacement), ["x"],
            "plain mode writes the template as is")
    }

    func testTheCaretFollowsTheReplacementsBeforeIt() {
        let text = "aa x aa y" as NSString
        let edits = TextSearch.replaceAll("aa", with: "b", in: text, caseSensitive: true, regex: false)
        XCTAssertEqual(TextSearch.caret(4, after: edits), 3, "after the first: shifted by its change")
        XCTAssertEqual(TextSearch.caret(6, after: edits), 5, "inside the second: the end of ITS replacement, after the first shifted it")
        XCTAssertEqual(TextSearch.caret(1, after: edits), 1, "inside the first: the end of its replacement")
        XCTAssertEqual(TextSearch.caret(9, after: edits), 7, "past both")
    }
}
