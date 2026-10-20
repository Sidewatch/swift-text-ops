//
//  FoldPlanTests.swift
//  TextOpsTests
//
//  Fold planning: runs of lines, unchanged stretches around changes, and line 1 kept visible.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import TextOps

/// `FoldPlan`.
final class FoldPlanTests: XCTestCase {
    func testConsecutiveLinesFoldAsOneRunBehindTheLineAbove() {
        XCTAssertEqual(
            FoldPlan.runs(of: [3, 4, 5, 9, 12, 13]),
            [Fold(anchor: 2, hidden: 3...5), Fold(anchor: 8, hidden: 9...9), Fold(anchor: 11, hidden: 12...13)])
        XCTAssertEqual(FoldPlan.runs(of: []), [])
        XCTAssertEqual(FoldPlan.runs(of: [1, 2]), [Fold(anchor: 1, hidden: 1...2)], "line 1 anchors itself, until keepingTheFirstLine")
    }

    func testUnchangedStretchesFoldOutsideTheContext() {
        // A change on line 10 of 30 keeps 8...12 in view; 1...7 and 13...30 fold.
        XCTAssertEqual(
            FoldPlan.unchangedRuns(changed: [10], total: 30),
            [Fold(anchor: 1, hidden: 1...7), Fold(anchor: 12, hidden: 13...30)])
    }

    func testAStretchShorterThanTheMinimumStaysOpen() {
        // Changes on 3 and 11 keep 1...5 and 9...13; 6...8 is three lines, under five.
        XCTAssertEqual(FoldPlan.unchangedRuns(changed: [3, 11], total: 13), [])
        XCTAssertEqual(FoldPlan.unchangedRuns(changed: [3, 11], total: 13, minimumRun: 3), [Fold(anchor: 5, hidden: 6...8)])
    }

    func testNoChangesFoldNothing() {
        XCTAssertEqual(FoldPlan.unchangedRuns(changed: [], total: 100), [])
    }

    func testLineOneIsNeverHidden() {
        XCTAssertEqual(
            FoldPlan.keepingTheFirstLine([Fold(anchor: 1, hidden: 1...7), Fold(anchor: 1, hidden: 1...1), Fold(anchor: 4, hidden: 5...6)]),
            [Fold(anchor: 1, hidden: 2...7), Fold(anchor: 4, hidden: 5...6)])
    }
}
