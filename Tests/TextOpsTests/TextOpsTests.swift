//
//  TextOpsTests.swift
//  Tests for SwiftTextOps
//
//  Created by David Sherlock on 7/25/26.
//

import XCTest
@testable import TextOps

final class TextOpsTests: XCTestCase {

    // MARK: - Sorting

    func testAlphabeticalSortIsScalarOrderAndReversible() {
        let lines = ["banana", "Apple", "cherry"]
        // Scalar order: uppercase sorts ahead of lowercase.
        XCTAssertEqual(LineOps.sort(lines), ["Apple", "banana", "cherry"])
        XCTAssertEqual(LineOps.sort(lines, descending: true), ["cherry", "banana", "Apple"])
    }

    func testAlphabeticalSortCaseInsensitive() {
        let lines = ["banana", "Apple", "cherry"]
        XCTAssertEqual(LineOps.sort(lines, caseInsensitive: true), ["Apple", "banana", "cherry"])
        XCTAssertEqual(LineOps.sort(["b", "A", "a", "B"], caseInsensitive: true), ["A", "a", "b", "B"])
    }

    func testSortIsStableInBothDirections() {
        // All four compare equal on length, so every one must keep its input order — and stay in
        // that order when the direction flips (the classic reversed-ties bug).
        let lines = ["aa", "bb", "cc", "dd"]
        XCTAssertEqual(LineOps.sort(lines, by: .length), lines)
        XCTAssertEqual(LineOps.sort(lines, by: .length, descending: true), lines)
    }

    func testLengthSort() {
        XCTAssertEqual(LineOps.sort(["ccc", "a", "bb"], by: .length), ["a", "bb", "ccc"])
        XCTAssertEqual(LineOps.sort(["ccc", "a", "bb"], by: .length, descending: true), ["ccc", "bb", "a"])
    }

    func testNumericSortReadsTheFirstNumberAnywhereInTheLine() {
        let lines = ["item 10", "item 9", "item 100"]
        XCTAssertEqual(LineOps.sort(lines, by: .numeric), ["item 9", "item 10", "item 100"])
    }

    func testNumericSortHandlesSignsDecimalsAndNumberedLists() {
        XCTAssertEqual(LineOps.sort(["3.5", "-2", "10"], by: .numeric), ["-2", "3.5", "10"])
        // "12." must not be read as unparseable and dropped to the end.
        XCTAssertEqual(LineOps.sort(["12. Widgets", "2. Apples"], by: .numeric),
                       ["2. Apples", "12. Widgets"])
        XCTAssertEqual(LineOps.sort(["v10", "v2"], by: .numeric), ["v2", "v10"])
    }

    func testNumericSortParksNumberlessLinesAtTheEndInBothDirections() {
        let lines = ["5", "banana", "1", "apple"]
        XCTAssertEqual(LineOps.sort(lines, by: .numeric), ["1", "5", "banana", "apple"])
        // Descending flips the numbers but the numberless tail keeps both its place and its order.
        XCTAssertEqual(LineOps.sort(lines, by: .numeric, descending: true), ["5", "1", "banana", "apple"])
    }

    func testReverse() {
        XCTAssertEqual(LineOps.reverse(["a", "b", "c"]), ["c", "b", "a"])
        XCTAssertEqual(LineOps.reverse([]), [])
    }

    func testShuffleIsAPermutationAndSeedable() {
        let lines = (1...50).map(String.init)
        var generator = SeededGenerator(seed: 42)
        let shuffled = LineOps.shuffle(lines, using: &generator)
        XCTAssertEqual(shuffled.sorted(), lines.sorted())

        // Same seed, same permutation.
        var replay = SeededGenerator(seed: 42)
        XCTAssertEqual(LineOps.shuffle(lines, using: &replay), shuffled)
    }

    // MARK: - Deduplication

    func testUniqueKeepsFirstOccurrenceAndPreservesOrder() {
        XCTAssertEqual(LineOps.unique(["b", "a", "b", "c", "a"]), ["b", "a", "c"])
    }

    func testUniqueCaseInsensitiveKeepsTheFirstSpelling() {
        XCTAssertEqual(LineOps.unique(["Apple", "APPLE", "apple", "Pear"], caseInsensitive: true),
                       ["Apple", "Pear"])
        // Case-sensitive by default: nothing collapses.
        XCTAssertEqual(LineOps.unique(["Apple", "APPLE"]), ["Apple", "APPLE"])
    }

    // MARK: - Cleaning

    func testRemoveBlankLinesDropsWhitespaceOnlyLines() {
        XCTAssertEqual(LineOps.removeBlankLines(["a", "", "  ", "\t", "b"]), ["a", "b"])
    }

    func testCollapseBlankRunsKeepsOneSeparator() {
        XCTAssertEqual(LineOps.collapseBlankRuns(["a", "", "", "", "b", "", "c"]),
                       ["a", "", "b", "", "c"])
        // A whitespace-only line counts as blank, and the survivor is the first of the run.
        XCTAssertEqual(LineOps.collapseBlankRuns(["a", "  ", "", "b"]), ["a", "  ", "b"])
    }

    func testTrimTrailingWhitespacePreservesIndentation() {
        XCTAssertEqual(LineOps.trimTrailingWhitespace(["    indented   ", "plain\t", "   "]),
                       ["    indented", "plain", ""])
    }

    // MARK: - Joining & splitting

    func testJoin() {
        XCTAssertEqual(LineOps.join(["a", "b", "c"]), ["a b c"])
        XCTAssertEqual(LineOps.join(["a", "b"], separator: ", "), ["a, b"])
    }

    func testSplitOnDelimiter() {
        XCTAssertEqual(LineOps.split(["a,b", "c"], on: ","), ["a", "b", "c"])
        // An empty delimiter is a no-op rather than an explosion into characters.
        XCTAssertEqual(LineOps.split(["a,b"], on: ""), ["a,b"])
    }

    // MARK: - Decorating

    func testAddAffixes() {
        XCTAssertEqual(LineOps.addAffixes(["a", "b"], prefix: "<", suffix: ">"), ["<a>", "<b>"])
        XCTAssertEqual(LineOps.addAffixes(["a"], prefix: "- "), ["- a"])
        // Both empty is a no-op, not a rewrite.
        XCTAssertEqual(LineOps.addAffixes(["a"]), ["a"])
    }

    func testNumber() {
        XCTAssertEqual(LineOps.number(["a", "b", "c"]), ["1. a", "2. b", "3. c"])
        XCTAssertEqual(LineOps.number(["a", "b"], startingAt: 0, separator: ") "), ["0) a", "1) b"])
    }

    func testPruneStripsOnlyWhereTheTriggerIsPresent() {
        XCTAssertEqual(LineOps.prune(["- a", "b", "- c"], leading: "- "), ["a", "b", "c"])
        XCTAssertEqual(LineOps.prune(["a;", "b"], trailing: ";"), ["a", "b"])
        XCTAssertEqual(LineOps.prune(["<a>"], leading: "<", trailing: ">"), ["a"])
        XCTAssertEqual(LineOps.prune(["a"]), ["a"])
    }

    func testPruneHandlesOverlappingTriggers() {
        // Stripping both ends must not run past the middle of a short line.
        XCTAssertEqual(LineOps.prune(["aa"], leading: "a", trailing: "a"), [""])
        XCTAssertEqual(LineOps.prune(["a"], leading: "a", trailing: "a"), [""])
    }

    // MARK: - Stats

    func testMeasureCountsWordsAcrossLines() {
        let stats = TextStats.measure(["the quick brown", "fox"])
        XCTAssertEqual(stats.lines, 2)
        XCTAssertEqual(stats.words, 4)
        XCTAssertEqual(stats.characters, 18)
    }

    func testMeasureIgnoresRunsOfWhitespaceAndCountsBlankLines() {
        let stats = TextStats.measure(["a    b", "", "   "])
        XCTAssertEqual(stats.lines, 3)
        XCTAssertEqual(stats.words, 2)
        XCTAssertEqual(TextStats.measure([]), TextStats(lines: 0, words: 0, characters: 0))
    }

    // MARK: - Case

    func testApplyCase() {
        XCTAssertEqual(LineOps.applyCase(["Hello World"], .lower), ["hello world"])
        XCTAssertEqual(LineOps.applyCase(["Hello World"], .upper), ["HELLO WORLD"])
        XCTAssertEqual(LineOps.applyCase(["hello world"], .title), ["Hello World"])
    }

    // MARK: - Transpose

    func testTransposeFlipsRowsAndColumns() {
        let rows = ["a\tb\tc", "d\te\tf"]
        XCTAssertEqual(LineOps.transpose(rows), ["a\td", "b\te", "c\tf"])
        // Rectangular input round-trips.
        XCTAssertEqual(LineOps.transpose(LineOps.transpose(rows)), rows)
    }

    func testTransposePadsRaggedRows() {
        XCTAssertEqual(LineOps.transpose(["a,b,c", "d"], delimiter: ","), ["a,d", "b,", "c,"])
    }

    func testTransposeEdgeCases() {
        XCTAssertEqual(LineOps.transpose([]), [])
        XCTAssertEqual(LineOps.transpose(["a\tb"], delimiter: ""), ["a\tb"])
    }

    // MARK: - TextLines round trips

    func testDetectEndingPrefersCRLF() {
        XCTAssertEqual(TextLines.detectEnding("a\r\nb"), .crlf)
        XCTAssertEqual(TextLines.detectEnding("a\rb"), .cr)
        XCTAssertEqual(TextLines.detectEnding("a\nb"), .lf)
        XCTAssertEqual(TextLines.detectEnding("no terminator"), .lf)
    }

    func testTransformPreservesCRLF() {
        let result = TextLines.transform("b\r\na") { LineOps.sort($0) }
        XCTAssertEqual(result, "a\r\nb")
    }

    func testTransformPreservesTrailingNewlineWithoutSortingIt() {
        // The empty element a trailing newline produces must not be sorted to the top.
        XCTAssertEqual(TextLines.transform("b\na\n") { LineOps.sort($0) }, "a\nb\n")
        XCTAssertEqual(TextLines.transform("b\na") { LineOps.sort($0) }, "a\nb")
    }

    func testTransformOnEmptyAndSingleLineText() {
        XCTAssertEqual(TextLines.transform("") { LineOps.sort($0) }, "")
        XCTAssertEqual(TextLines.transform("solo") { LineOps.sort($0) }, "solo")
        // A lone newline is one trailing terminator, not a line to reorder.
        XCTAssertEqual(TextLines.transform("\n") { LineOps.sort($0) }, "\n")
    }

    func testTransformNormalizesMixedTerminatorsToTheDetectedOne() {
        // Mixed input: CRLF wins detection, so the whole result comes back CRLF.
        XCTAssertEqual(TextLines.transform("b\r\na\nc") { LineOps.sort($0) }, "a\r\nb\r\nc")
    }
}

// MARK: - Helpers

/// A deterministic `RandomNumberGenerator` so shuffle tests can assert on a fixed permutation.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { self.state = seed &+ 0x9E3779B97F4A7C15 }

    mutating func next() -> UInt64 {
        // SplitMix64.
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
