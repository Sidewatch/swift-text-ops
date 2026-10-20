//
//  StringLineFeedCountTests.swift
//  TextOpsTests
//
//  `String.lineFeedCount`: every LF once, CRLF once, nothing else.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import TextOps

/// `String.lineFeedCount`.
final class StringLineFeedCountTests: XCTestCase {
    func testLineFeedCountCountsEveryLFOnce() {
        XCTAssertEqual("".lineFeedCount, 0)
        XCTAssertEqual("a\nb\n".lineFeedCount, 2)
        XCTAssertEqual("a\n\n\nb".lineFeedCount, 3, "adjacent line feeds, each counted")
        XCTAssertEqual("a\r\nb\r\n".lineFeedCount, 2, "a CRLF is one line feed")
        XCTAssertEqual("a\rb\u{2028}c".lineFeedCount, 0, "a lone CR and a separator are not line feeds")
        XCTAssertEqual("é\n😀\n".lineFeedCount, 2, "multi-byte characters around them")
        XCTAssertEqual(String(repeating: "line\n", count: 70_000).lineFeedCount, 70_000, "past memchr's first hit many times")
    }
}
