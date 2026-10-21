//
//  FuzzyScorer+Rank.swift
//  TextOps
//
//  Ranking a list with the fuzzy scorer, and when a longer query may search the last one's hits.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

public extension FuzzyScorer {
    /// How matches that are not told apart by the scorer's own rules are ordered.
    enum RankOrder: Sendable {
        /// ``FuzzyScorer/compare(_:_:_:_:query:)``: VS Code's full comparison (label match, prefix,
        /// length, path), for files and commands.
        case scorer
        /// Score alone; equal scores keep the input's order (an outline keeps document order).
        case scoreThenInputOrder
        /// Score, then the shorter label (a symbol-name list where the exact name should lead).
        case scoreThenShorterLabel
    }

    /// One ranked element and its score (with the match ranges to emphasise).
    struct Ranked<Element> {
        /// The element.
        public let element: Element
        /// Its score.
        public let score: ItemScore
    }

    /// `elements` that match `query`, best first. Each element's scorer item is built once and each
    /// element scored once; the sort only compares stored scores (a comparator that re-scored ran the
    /// scorer O(n log n) times over 10,000 files). `query` must not be empty — callers show their own
    /// unfiltered list then.
    static func rank<Element>(_ elements: [Element], query: FuzzyQuery, order: RankOrder, item: (Element) -> Item) -> [Ranked<Element>] {
        var scored: [(ranked: Ranked<Element>, item: Item, index: Int, length: Int)] = []
        for (index, element) in elements.enumerated() {
            let entry = item(element)
            let score = scoreItem(entry, query: query, allowNonContiguousMatches: true)
            if score.score > 0 {
                scored.append((Ranked(element: element, score: score), entry, index, entry.label.utf16.count))
            }
        }
        switch order {
        case .scorer:
            scored.sort { compare($0.item, $0.ranked.score, $1.item, $1.ranked.score, query: query) == .orderedAscending }
        case .scoreThenInputOrder:
            scored.sort {
                $0.ranked.score.score != $1.ranked.score.score ? $0.ranked.score.score > $1.ranked.score.score : $0.index < $1.index
            }
        case .scoreThenShorterLabel:
            scored.sort {
                $0.ranked.score.score != $1.ranked.score.score ? $0.ranked.score.score > $1.ranked.score.score : $0.length < $1.length
            }
        }
        return scored.map(\.ranked)
    }

    /// Whether `item` answers `query` the way a picker ranking it would (space-separated pieces in any
    /// order, quotes, the path) — for a filter that keeps rather than ranks.
    static func matches(_ item: Item, query: FuzzyQuery) -> Bool {
        scoreItem(item, query: query, allowNonContiguousMatches: true).score > 0
    }
}

public extension FuzzyQuery {
    /// Whether every match of this query is also a match of `previous`, so a picker may search only
    /// `previous`'s hits as the person types on. True only when `previous` is one unquoted piece and
    /// this query's FIRST piece extends it: every piece must match, and a fuzzy match of a longer piece
    /// is a match of its prefix. Normalised text alone is not enough — `foob` and `foo b` normalise
    /// alike, but `foo b` matches `barFoo` in either order where `foob` does not.
    func narrows(_ previous: FuzzyQuery) -> Bool {
        guard previous.pieces == nil, !previous.expectContiguousMatch, !previous.normalizedLowercase.isEmpty else { return false }
        let first = pieces?.first?.normalizedLowercase ?? normalizedLowercase
        return first.hasPrefix(previous.normalizedLowercase)
    }
}
