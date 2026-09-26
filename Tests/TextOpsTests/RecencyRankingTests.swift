//
//  RecencyRankingTests.swift
//  TextOpsTests
//
//  Most recent first, the rest in their own order, and the order surviving a relaunch.
//
//  Created by David Sherlock on 9/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import TextOps

final class RecencyRankingTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUp() {
        suite = "recency-\(UUID())"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() { defaults.removePersistentDomain(forName: suite) }

    func testTheMostRecentChoiceLeadsAndTheRestKeepTheirOrder() {
        let r = RecencyRanking(key: "k", defaults: defaults)
        r.record("b"); r.record("d")
        XCTAssertEqual(r.ordered(["a", "b", "c", "d", "e"], by: { $0 }), ["d", "b", "a", "c", "e"])
        XCTAssertEqual(r.rank("zzz"), 0)
    }

    func testChoosingAgainMovesAnEntryBackToTheFront() {
        let r = RecencyRanking(key: "k", defaults: defaults)
        r.record("a"); r.record("b"); r.record("a")
        XCTAssertEqual(r.ordered(["a", "b"], by: { $0 }), ["a", "b"])
    }

    func testTheRankingSurvivesANewInstance() {
        RecencyRanking(key: "k", defaults: defaults).record("x")
        let later = RecencyRanking(key: "k", defaults: defaults)
        later.record("y")
        XCTAssertEqual(later.ordered(["x", "y", "z"], by: { $0 }), ["y", "x", "z"],
                       "the sequence resumes above what was stored, so the new choice outranks the old")
    }
}
