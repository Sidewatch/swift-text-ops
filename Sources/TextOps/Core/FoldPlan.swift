//
//  FoldPlan.swift
//  TextOps
//
//  Which lines a review lens folds: runs of chosen lines, and the unchanged stretches between changes.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Planning a set of ``Fold``s from line numbers (1-based), for an editor's review lenses: fold every
/// comment run, or fold everything far from a change. Deciding WHICH lines are comments is the caller's
/// (it needs the highlighter's colours); turning them into folds is here.
public enum FoldPlan {
    /// One fold per run of consecutive lines in `lines` (ascending), each behind the line just above it.
    public static func runs(of lines: [Int]) -> [Fold] {
        var folds: [Fold] = []
        var start: Int?, previous = Int.min
        for line in lines + [Int.max] {
            if line != previous &+ 1 {
                if let start { folds.append(Fold(anchor: max(1, start - 1), hidden: start...previous)) }
                start = line
            }
            previous = line
        }
        return folds
    }

    /// The stretches of a `total`-line text more than `context` lines from every line in `changed`,
    /// folded when at least `minimumRun` long. A text with no changes folds nothing: with nothing to
    /// keep in view, the whole document would collapse into one marker.
    public static func unchangedRuns(changed: Set<Int>, total: Int, context: Int = 2, minimumRun: Int = 5) -> [Fold] {
        guard !changed.isEmpty, total > 0 else { return [] }
        var folds: [Fold] = []
        var start: Int?
        for line in 1...(total + 1) {
            let nearChange = (line - context...line + context).contains { changed.contains($0) }
            if line <= total, !nearChange {
                if start == nil { start = line }
            } else if let run = start {
                if line - run >= minimumRun { folds.append(Fold(anchor: max(1, run - 1), hidden: run...(line - 1))) }
                start = nil
            }
        }
        return folds
    }

    /// `folds` with line 1 never hidden, since a fold needs a visible anchor above it: a fold starting
    /// at line 1 is moved to start at line 2 behind line 1, and one hiding ONLY line 1 is dropped.
    public static func keepingTheFirstLine(_ folds: [Fold]) -> [Fold] {
        folds.compactMap { fold in
            guard fold.hidden.lowerBound == 1 else { return fold }
            guard fold.hidden.upperBound >= 2 else { return nil }
            return Fold(anchor: 1, hidden: 2...fold.hidden.upperBound)
        }
    }
}
