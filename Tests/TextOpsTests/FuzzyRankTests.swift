//
//  FuzzyRankTests.swift
//  TextOpsTests
//
//  Ranking with each tie-break policy, the keep-filter, and when a query may narrow the last one's hits.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import TextOps

/// `FuzzyScorer.rank`, `FuzzyScorer.matches` and `FuzzyQuery.narrows`.
final class FuzzyRankTests: XCTestCase {
    private func labels(_ ranked: [FuzzyScorer.Ranked<String>]) -> [String] { ranked.map(\.element) }

    func testOnlyMatchesAreRankedBestFirst() {
        let ranked = FuzzyScorer.rank(["readme.md", "main.swift", "Makefile"], query: FuzzyQuery("main"), order: .scorer) {
            FuzzyScorer.Item(label: $0)
        }
        XCTAssertEqual(labels(ranked), ["main.swift"])
        XCTAssertFalse(ranked[0].score.labelMatch?.isEmpty ?? true, "the ranges to emphasise come along")
    }

    func testEqualScoresKeepInputOrderOrPreferTheShorterLabel() {
        // Two elements with ONE label score exactly alike: only the tie-break orders them.
        let tied = [(id: "second", label: "fooBar"), (id: "first", label: "fooBar"), (id: "short", label: "foo")]
        let query = FuzzyQuery("foo")
        let inputOrder = FuzzyScorer.rank(tied, query: query, order: .scoreThenInputOrder) { FuzzyScorer.Item(label: $0.label) }
        let fooBars = inputOrder.map(\.element.id).filter { $0 != "short" }
        XCTAssertEqual(fooBars, ["second", "first"], "ties keep the input's order")
        let shorter = FuzzyScorer.rank(tied, query: query, order: .scoreThenShorterLabel) { FuzzyScorer.Item(label: $0.label) }
        XCTAssertEqual(shorter.first?.element.id, "short", "the exact name leads")
        // Equal scores, different lengths: only the shorter-label rule orders them.
        let lengths = FuzzyScorer.rank(["abfoo", "afoo"], query: FuzzyQuery("foo"), order: .scoreThenShorterLabel) {
            FuzzyScorer.Item(label: $0)
        }
        XCTAssertEqual(lengths.map(\.score.score).count, 2)
        XCTAssertEqual(Set(lengths.map(\.score.score)).count, 1, "a premise: the two score alike")
        XCTAssertEqual(lengths.map(\.element), ["afoo", "abfoo"], "then the shorter label")
    }

    func testAPiecedQueryMatchesInAnyOrder() {
        let item = FuzzyScorer.Item(label: "main.swift", description: "Sources/App", path: "Sources/App/main.swift")
        XCTAssertTrue(FuzzyScorer.matches(item, query: FuzzyQuery("swift main")), "pieces in any order")
        XCTAssertTrue(FuzzyScorer.matches(item, query: FuzzyQuery("app main")), "a piece may match the folder")
        XCTAssertFalse(FuzzyScorer.matches(item, query: FuzzyQuery("zzz main")))
        XCTAssertEqual(
            FuzzyScorer.score("main.swift", query: "swift main", queryLower: "swift main", allowNonContiguousMatches: true).score, 0,
            "the raw scorer reads the space literally — why a filter must go through FuzzyQuery")
    }

    func testANarrowingQueryNeverLosesAMatch() {
        XCTAssertTrue(FuzzyQuery("foob").narrows(FuzzyQuery("foo")), "typing on")
        XCTAssertTrue(FuzzyQuery("foo b").narrows(FuzzyQuery("foo")), "a new piece after the old text")
        XCTAssertFalse(FuzzyQuery("foo b").narrows(FuzzyQuery("foob")), "a space splits the old text into pieces")
        XCTAssertFalse(FuzzyQuery("foob").narrows(FuzzyQuery("foo b")), "the old query had pieces")
        XCTAssertFalse(FuzzyQuery("foob").narrows(FuzzyQuery("\"foo\"")), "the old query was contiguous-only")
        XCTAssertFalse(FuzzyQuery("bar").narrows(FuzzyQuery("foo")))
        XCTAssertFalse(FuzzyQuery("foo").narrows(FuzzyQuery("")))
        // The case narrowing used to get wrong: a hit of `foo b` that is no hit of `foob`.
        let barFoo = FuzzyScorer.Item(label: "barFoo")
        XCTAssertTrue(FuzzyScorer.matches(barFoo, query: FuzzyQuery("foo b")))
        XCTAssertFalse(FuzzyScorer.matches(barFoo, query: FuzzyQuery("foob")))
    }
}
