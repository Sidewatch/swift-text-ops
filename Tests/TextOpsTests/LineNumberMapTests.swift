//
//  LineNumberMapTests.swift
//  TextOpsTests
//
//  Tests for `LineNumberMap`: identity for LF and CRLF texts, one editor line per extra break
//  (lone CR, NEL, LS, PS) with `NSString.lineRange` as the oracle, both directions, clamping,
//  the chunk boundary, and the cost of scanning 20 MB.
//
//  Created by David Sherlock on 10/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import TextOps

/// Tests for `LineNumberMap`: identity for LF and CRLF texts, one editor line per extra break
/// (lone CR, NEL, LS, PS) with `NSString.lineRange` as the oracle, both directions, clamping,
/// the chunk boundary, and the cost of scanning 20 MB.
final class LineNumberMapTests: XCTestCase {

    // MARK: - Oracle

    /// The UTF-16 offset where each editor line starts, by `NSString.getLineStart`: a new line
    /// starts after every terminator, including a final one.
    private func unicodeLineStarts(_ text: NSString) -> [Int] {
        var starts = [0]
        var position = 0
        while position < text.length {
            var start = 0, end = 0, contentsEnd = 0
            text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: position, length: 0))
            if end > contentsEnd { starts.append(end) }
            position = end
        }
        return starts
    }

    /// The UTF-16 offset where each git line starts: after every `\n`.
    private func gitLineStarts(_ text: NSString) -> [Int] {
        var starts = [0]
        for i in 0..<text.length where text.character(at: i) == 0x0A { starts.append(i + 1) }
        return starts
    }

    /// Every line of `text` in both directions against the two numberings computed the slow
    /// way: a git line maps to the editor line starting where it starts, an editor line to the
    /// git line that holds its start.
    private func assertAgreesWithTheOracle(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let ns = text as NSString
        let map = LineNumberMap(text: ns)
        let unicode = unicodeLineStarts(ns)
        let git = gitLineStarts(ns)
        XCTAssertEqual(map.gitLineCount, git.count, "git lines", file: file, line: line)
        XCTAssertEqual(map.unicodeLineCount, unicode.count, "editor lines", file: file, line: line)
        for g in 1...git.count {
            let expected = unicode.firstIndex(of: git[g - 1])! + 1
            XCTAssertEqual(map.unicodeLine(forGitLine: g), expected, "git line \(g)", file: file, line: line)
        }
        for u in 1...unicode.count {
            let expected = git.lastIndex { $0 <= unicode[u - 1] }! + 1
            XCTAssertEqual(map.gitLine(forUnicodeLine: u), expected, "editor line \(u)", file: file, line: line)
        }
    }

    // MARK: - Identity

    func testLineFeedTextIsTheIdentity() {
        let map = LineNumberMap(text: "a\nb\nc\n")
        XCTAssertTrue(map.isIdentity)
        XCTAssertEqual(map.extraBreakCount, 0)
        XCTAssertEqual(map.gitLineCount, 4, "the line after the final newline counts, as an editor numbers it")
        XCTAssertEqual(map.unicodeLineCount, 4)
        for n in 1...4 {
            XCTAssertEqual(map.unicodeLine(forGitLine: n), n)
            XCTAssertEqual(map.gitLine(forUnicodeLine: n), n)
        }
        assertAgreesWithTheOracle("a\nb\nc\n")
    }

    func testCRLFTextIsTheIdentity() {
        let map = LineNumberMap(text: "a\r\nb\r\nc")
        XCTAssertTrue(map.isIdentity, "\\r\\n is one break to git and to the editor alike")
        XCTAssertEqual(map.gitLineCount, 3)
        XCTAssertEqual(map.unicodeLineCount, 3)
        assertAgreesWithTheOracle("a\r\nb\r\nc")
    }

    func testEmptyTextIsOneLineBothWays() {
        let map = LineNumberMap(text: "")
        XCTAssertTrue(map.isIdentity)
        XCTAssertEqual(map.gitLineCount, 1)
        XCTAssertEqual(map.unicodeLine(forGitLine: 1), 1)
        XCTAssertEqual(map.gitLine(forUnicodeLine: 1), 1)
    }

    // MARK: - Extra breaks

    func testLineSeparatorShiftsEveryGitLineBelowIt() {
        // Git: 1 "a<LS>b", 2 "c", 3 "d". Editor: 1 "a", 2 "b", 3 "c", 4 "d".
        let map = LineNumberMap(text: "a\u{2028}b\nc\nd")
        XCTAssertFalse(map.isIdentity)
        XCTAssertEqual(map.extraBreakCount, 1)
        XCTAssertEqual(map.gitLineCount, 3)
        XCTAssertEqual(map.unicodeLineCount, 4)
        XCTAssertEqual(map.unicodeLine(forGitLine: 1), 1)
        XCTAssertEqual(map.unicodeLine(forGitLine: 2), 3, "git's line 2 (\"c\") is the editor's line 3")
        XCTAssertEqual(map.unicodeLine(forGitLine: 3), 4)
        XCTAssertEqual(map.gitLine(forUnicodeLine: 1), 1)
        XCTAssertEqual(map.gitLine(forUnicodeLine: 2), 1, "\"b\" is still inside git's line 1")
        XCTAssertEqual(map.gitLine(forUnicodeLine: 3), 2)
        XCTAssertEqual(map.gitLine(forUnicodeLine: 4), 3)
        assertAgreesWithTheOracle("a\u{2028}b\nc\nd")
    }

    func testLoneCarriageReturnIsABreakToTheEditorOnly() {
        // Git: 1 "a\rb", 2 "c". Editor: 1 "a", 2 "b", 3 "c".
        let map = LineNumberMap(text: "a\rb\nc")
        XCTAssertEqual(map.extraBreakCount, 1)
        XCTAssertEqual(map.unicodeLine(forGitLine: 2), 3)
        XCTAssertEqual(map.gitLine(forUnicodeLine: 2), 1)
        XCTAssertEqual(map.gitLine(forUnicodeLine: 3), 2)
        assertAgreesWithTheOracle("a\rb\nc")

        let trailing = LineNumberMap(text: "a\r")
        XCTAssertEqual(trailing.extraBreakCount, 1, "a \\r ending the text has no \\n after it")
        XCTAssertEqual(trailing.unicodeLineCount, 2)
        assertAgreesWithTheOracle("a\r")
    }

    func testEveryExtraBreakKindMixedWithCRLF() {
        // Git: 1 "x\r", 2 "y<NEL>z\rw", 3 "<PS>v". Editor: "x", "y", "z", "w", "", "v".
        let text = "x\r\ny\u{85}z\rw\n\u{2029}v"
        let map = LineNumberMap(text: text)
        XCTAssertEqual(map.extraBreakCount, 3)
        XCTAssertEqual(map.gitLineCount, 3)
        XCTAssertEqual(map.unicodeLineCount, 6)
        XCTAssertEqual((1...3).map { map.unicodeLine(forGitLine: $0) }, [1, 2, 5])
        XCTAssertEqual((1...6).map { map.gitLine(forUnicodeLine: $0) }, [1, 2, 2, 2, 3, 3])
        assertAgreesWithTheOracle(text)
    }

    func testVerticalTabAndFormFeedAreNotBreaks() {
        XCTAssertTrue(LineNumberMap(text: "a\u{0B}b\u{0C}c\n").isIdentity)
        assertAgreesWithTheOracle("a\u{0B}b\u{0C}c\n")
    }

    func testBothDirectionsAreMonotoneAndRoundTripOnAMixedText() {
        var text = ""
        let breaks = ["\n", "\r\n", "\r", "\u{85}", "\u{2028}", "\u{2029}", "", ""]
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        for i in 0..<400 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            text += "line \(i)" + breaks[Int(seed >> 61)]
        }
        assertAgreesWithTheOracle(text)
        let map = LineNumberMap(text: text)
        XCTAssertFalse(map.isIdentity)
        for g in 1...map.gitLineCount {
            XCTAssertEqual(map.gitLine(forUnicodeLine: map.unicodeLine(forGitLine: g)), g)
        }
        for u in 2...map.unicodeLineCount {
            XCTAssertLessThanOrEqual(map.gitLine(forUnicodeLine: u - 1), map.gitLine(forUnicodeLine: u))
        }
        for g in 2...map.gitLineCount {
            XCTAssertLessThan(map.unicodeLine(forGitLine: g - 1), map.unicodeLine(forGitLine: g))
        }
    }

    // MARK: - Clamping

    func testNumbersPastEitherEndClampToTheLastLine() {
        let map = LineNumberMap(text: "a\u{2028}b\nc")
        XCTAssertEqual(map.unicodeLine(forGitLine: 0), 1)
        XCTAssertEqual(map.unicodeLine(forGitLine: -5), 1)
        XCTAssertEqual(map.unicodeLine(forGitLine: 99), 3, "the last git line is 2, which starts on editor line 3")
        XCTAssertEqual(map.gitLine(forUnicodeLine: 0), 1)
        XCTAssertEqual(map.gitLine(forUnicodeLine: 99), 2)
    }

    // MARK: - Chunk boundary

    func testACarriageReturnOnTheChunkBoundarySeesItsLineFeed() {
        let chunk = LineBreakScan.chunk
        let crlf = String(repeating: "a", count: chunk - 1) + "\r\n" + "b"
        XCTAssertTrue(LineNumberMap(text: crlf).isIdentity, "\\r at the chunk's last unit, \\n at the next chunk's first")
        assertAgreesWithTheOracle(crlf)

        let lone = String(repeating: "a", count: chunk - 1) + "\r" + "b"
        XCTAssertEqual(LineNumberMap(text: lone).extraBreakCount, 1)
        assertAgreesWithTheOracle(lone)

        let atEnd = String(repeating: "a", count: chunk - 1) + "\r"
        XCTAssertEqual(LineNumberMap(text: atEnd).extraBreakCount, 1, "a \\r on the chunk's last unit and the text's")
    }

    func testTheDirectPointerPathAgreesWithTheChunkedPath() {
        // NSMutableString keeps a UTF-16 store that CFStringGetCharactersPtr can hand out
        // directly; a Swift String bridged to NSString takes the chunked getCharacters path.
        let text = "a\u{2028}b\r\nc\rd\u{85}e\u{2029}f\n" + String(repeating: "x\n", count: 1000) + "\r"
        let direct = NSMutableString(string: text)
        XCTAssertEqual(LineNumberMap(text: direct), LineNumberMap(text: text))
        assertAgreesWithTheOracle(text)
    }

    // MARK: - Cost

    private func milliseconds(_ body: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        body()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    func testScanningTwentyMegabytesStaysWellUnder50ms() {
        // Code-like text: parentheses share a low byte with U+2028 / U+2029 and are the
        // worst case for the byte sweep; a lone CR, NEL, LS and PS at the end keep the map honest.
        let line = "    let value = compute(a, b) + helper(c)    // note (x)\n"
        var text = ""
        text.reserveCapacity(10_000_000)
        while text.utf16.count < 10_000_000 { text += line }
        text += "a\rb\u{85}c\u{2028}d\u{2029}e"
        let bridged = text as NSString
        let native = NSMutableString(string: text)
        let units = bridged.length
        XCTAssertGreaterThanOrEqual(units * 2, 20_000_000)

        var map: LineNumberMap?
        let chunked = milliseconds { map = LineNumberMap(text: bridged) }
        XCTAssertEqual(map?.extraBreakCount, 4)
        XCTAssertEqual(map?.gitLineCount, text.utf16.filter { $0 == 0x0A }.count + 1)
        var native_: LineNumberMap?
        let direct = milliseconds { native_ = LineNumberMap(text: native) }
        XCTAssertEqual(native_, map)
        print("LineNumberMap: \(units) UTF-16 units (\(units * 2 / 1_000_000) MB): bridged \(chunked) ms, native \(direct) ms")
        XCTAssertLessThan(chunked, 50)
        XCTAssertLessThan(direct, 50)

        // A classic Mac text: one extra break per line, the scan's worst case.
        let cr = NSMutableString(string: String(repeating: "line of classic text\r", count: 500_000))
        var crMap: LineNumberMap?
        let crTime = milliseconds { crMap = LineNumberMap(text: cr) }
        XCTAssertEqual(crMap?.extraBreakCount, 500_000)
        XCTAssertEqual(crMap?.gitLineCount, 1)
        XCTAssertEqual(crMap?.gitLine(forUnicodeLine: 400_000), 1)
        XCTAssertEqual(crMap?.unicodeLineCount, 500_001)
        print("LineNumberMap: \(cr.length) units, 500000 lone CRs: \(crTime) ms")
        XCTAssertLessThan(crTime, 100)
    }
}
