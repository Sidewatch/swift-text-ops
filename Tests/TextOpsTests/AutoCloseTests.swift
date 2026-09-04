import XCTest
@testable import TextOps

/// Every rule of the auto-closer, pinned. The editor that hosts it only applies the action.
final class AutoCloseTests: XCTestCase {
    private func decide(_ typed: String, _ text: String, caret: Int, length: Int = 0, quotes: Bool = true) -> AutoClose.Action {
        AutoClose.decide(typed: typed, in: text as NSString, at: NSRange(location: caret, length: length), allowQuotes: quotes)
    }

    func testOpenerPairsOnlyBeforeNothingWhitespaceOrACloser() {
        XCTAssertEqual(decide("(", "", caret: 0), .insertPair(open: "(", close: ")"))
        XCTAssertEqual(decide("(", "x ", caret: 1), .insertPair(open: "(", close: ")"))
        XCTAssertEqual(decide("[", "a)", caret: 1), .insertPair(open: "[", close: "]"), "before a closer")
        XCTAssertEqual(decide("(", "foo", caret: 0), .passThrough, "`(` before `foo` must not become `()foo`")
    }

    func testCloserTypedOntoTheSameCloserStepsOver() {
        XCTAssertEqual(decide(")", "()", caret: 1), .stepOver)
        XCTAssertEqual(decide(")", "(x", caret: 2), .passThrough)
        XCTAssertEqual(decide(")", "()", caret: 0, length: 1), .passThrough, "never over a selection")
    }

    func testQuotesNeverPairNextToAWordAndCanBeDisabled() {
        XCTAssertEqual(decide("'", "don", caret: 3), .passThrough, "don't")
        XCTAssertEqual(decide("\"", "foo|bar".replacingOccurrences(of: "|", with: ""), caret: 3), .passThrough, "\"foo|bar")
        XCTAssertEqual(decide("\"", "x = ", caret: 4), .insertPair(open: "\"", close: "\""))
        XCTAssertEqual(decide("\"", "\"\"", caret: 1), .stepOver)
        XCTAssertEqual(decide("\"", "x = ", caret: 4, quotes: false), .passThrough, "prose: quotes are punctuation")
    }

    func testOpenerOverASelectionWraps() {
        XCTAssertEqual(decide("(", "abc", caret: 0, length: 3), .wrap(open: "(", close: ")"))
        XCTAssertEqual(decide("`", "abc", caret: 1, length: 1), .wrap(open: "`", close: "`"))
    }

    func testBackspaceBetweenAnEmptyPairRemovesBoth() {
        XCTAssertTrue(AutoClose.deletesPair(in: "()", at: 1))
        XCTAssertTrue(AutoClose.deletesPair(in: "''", at: 1))
        XCTAssertFalse(AutoClose.deletesPair(in: "(x)", at: 1))
        XCTAssertFalse(AutoClose.deletesPair(in: "()", at: 0), "at the very start there is no pair behind the caret")
        XCTAssertFalse(AutoClose.deletesPair(in: "(]", at: 1), "mismatched closer")
    }

    func testMultiCharacterInputAndUnknownCharactersPassThrough() {
        XCTAssertEqual(decide("ab", "", caret: 0), .passThrough)
        XCTAssertEqual(decide("x", "", caret: 0), .passThrough)
    }
}
