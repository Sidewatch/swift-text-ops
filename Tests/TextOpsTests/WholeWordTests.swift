//
//  WholeWordTests.swift
//  Tests for TextOps.WholeWord
//
//  Tests for `WholeWord.pattern`: a whole-word query is anchored at both ends and a regex query
//  is wrapped, not escaped.
//
//  Created by David Sherlock on 8/5/26.
//

import XCTest
@testable import TextOps

/// Tests for `WholeWord.pattern`: a whole-word query is anchored at both ends and a regex query
/// is wrapped, not escaped.
final class WholeWordTests: XCTestCase {

    private func matches(_ query: String, in text: String, isRegex: Bool = false) -> Int {
        guard let p = WholeWord.pattern(for: query, isRegex: isRegex),
              let re = try? NSRegularExpression(pattern: p) else { return -1 }
        return re.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    func testWordQueryIsAnchoredBothEnds() {
        XCTAssertEqual(matches("foo", in: "foo bar"), 1)
        XCTAssertEqual(matches("foo", in: "foobar"), 0, "a whole-word search must not match inside a word")
        XCTAssertEqual(matches("foo", in: "bar foo baz"), 1)
    }

    /// THE BUG THIS EXISTS FOR: `\b==\b` compiles fine and matches nothing, because both
    /// sides of `==` are spaces and `\b` needs a word character on one side.
    func testOperatorQueriesStillMatch() {
        for op in ["==", "->", "+=", "!", "&&", "<=", "?？".prefix(1).description] {
            XCTAssertGreaterThan(matches(op, in: "a \(op) b"), 0,
                                 "whole-word search for '\(op)' must not silently match nothing")
        }
    }

    /// Mixed needles anchor only the word-character end.
    func testPartiallyWordQueriesAnchorOnlyTheWordEnd() {
        XCTAssertEqual(WholeWord.pattern(for: "foo("), "\\bfoo\\(")
        XCTAssertEqual(WholeWord.pattern(for: ")bar"), "\\)bar\\b")
        XCTAssertGreaterThan(matches("foo(", in: "call foo(1)"), 0)
        XCTAssertEqual(matches("foo(", in: "callfoo(1)"), 0, "the word end still anchors")
    }

    func testUnderscoreAndDigitsCountAsWordCharacters() {
        XCTAssertTrue(WholeWord.isWordCharacter("_"))
        XCTAssertTrue(WholeWord.isWordCharacter("7"))
        XCTAssertTrue(WholeWord.isWordCharacter("é"))
        XCTAssertFalse(WholeWord.isWordCharacter("-"))
        XCTAssertFalse(WholeWord.isWordCharacter(nil))
        XCTAssertEqual(WholeWord.pattern(for: "_id"), "\\b_id\\b")
    }

    func testRegexSpecialCharactersAreEscapedOnTheLiteralPath() {
        // "a.b" must not match "axb" — the dot is data, not a metacharacter.
        XCTAssertEqual(matches("a.b", in: "axb"), 0)
        XCTAssertEqual(matches("a.b", in: "a.b"), 1)
    }

    /// On the regex path the group is what keeps alternation from swallowing the anchors:
    /// `\bfoo|bar\b` parses as `(\bfoo)|(bar\b)`.
    func testRegexPathGroupsAlternation() {
        XCTAssertEqual(WholeWord.pattern(for: "foo|bar", isRegex: true), "\\b(?:foo|bar)\\b")
        XCTAssertEqual(matches("foo|bar", in: "foobar", isRegex: true), 0)
        XCTAssertEqual(matches("foo|bar", in: "foo bar", isRegex: true), 2)
    }

    /// An empty query has no whole-word pattern: an empty regex does not compile, so
    /// returning one would move the trap rather than remove it. nil makes the caller decide.
    func testEmptyQueryReturnsNil() {
        XCTAssertNil(WholeWord.pattern(for: ""))
        XCTAssertNil(WholeWord.pattern(for: "", isRegex: true))
    }

    /// Every non-empty query must yield a pattern that actually compiles — the property
    /// the old hand-rolled wrap satisfied while still matching nothing.
    func testEveryNonEmptyQueryCompiles() {
        for q in ["a", "==", "->", "_x9", "a.b", "]", "\\", "é", "  ", "?"] {
            guard let p = WholeWord.pattern(for: q) else { return XCTFail("nil for '\(q)'") }
            XCTAssertNoThrow(try NSRegularExpression(pattern: p), "'\(q)' → '\(p)'")
        }
    }
}
