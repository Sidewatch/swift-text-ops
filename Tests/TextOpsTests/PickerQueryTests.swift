//
//  PickerQueryTests.swift
//  TextOpsTests
//
//  Tests for `PickerQuery`: each prefix selects its mode, a file query keeps its `:123`, and
//  removing the prefix returns to files.
//
//  Created by David Sherlock on 10/3/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import TextOps

/// Tests for `PickerQuery`: each prefix selects its mode, a file query keeps its `:123`, and
/// removing the prefix returns to files.
final class PickerQueryTests: XCTestCase {
    func testEachPrefixSelectsItsMode() {
        XCTAssertEqual(PickerQuery(">git push"), PickerQuery(mode: .commands, text: "git push", line: nil))
        XCTAssertEqual(PickerQuery("@ render"), PickerQuery(mode: .outline, text: "render", line: nil))
        XCTAssertEqual(PickerQuery("#ProjectIndex"), PickerQuery(mode: .projectSymbols, text: "ProjectIndex", line: nil))
        XCTAssertEqual(PickerQuery(":42"), PickerQuery(mode: .line, text: "", line: 42))
        XCTAssertEqual(PickerQuery("main"), PickerQuery(mode: .files, text: "main", line: nil))
    }

    func testABarePrefixIsItsModeWithNothingToMatch() {
        XCTAssertEqual(PickerQuery(">").mode, .commands)
        XCTAssertEqual(PickerQuery(">").text, "")
        XCTAssertEqual(PickerQuery(":"), PickerQuery(mode: .line, text: "", line: nil), "a bare colon waits for a number")
        XCTAssertEqual(PickerQuery(":4x").line, nil, "not a number: no line")
        XCTAssertEqual(PickerQuery(""), PickerQuery(mode: .files, text: "", line: nil))
    }

    func testAFileQueryKeepsItsLineSuffix() {
        XCTAssertEqual(PickerQuery("main.swift:120"), PickerQuery(mode: .files, text: "main.swift", line: 120))
        XCTAssertEqual(PickerQuery("main.swift:"), PickerQuery(mode: .files, text: "main.swift", line: nil))
        XCTAssertEqual(PickerQuery("a:b"), PickerQuery(mode: .files, text: "a:b", line: nil), "a colon inside a name is kept")
    }

    func testDeletingThePrefixReturnsToFiles() {
        XCTAssertEqual(PickerQuery(">open").mode, .commands)
        XCTAssertEqual(PickerQuery("open").mode, .files)
    }

    func testOnlyALeadingPrefixCounts() {
        XCTAssertEqual(PickerQuery("a>b").mode, .files)
        XCTAssertEqual(PickerQuery("issue#12").mode, .files)
    }

    func testEveryModeButFilesHasAPrefix() {
        XCTAssertNil(PickerQuery.Mode.files.prefix)
        XCTAssertEqual(PickerQuery.Mode.allCases.compactMap(\.prefix), [">", "@", "#", ":"])
    }
}
