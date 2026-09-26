//
//  RecencyRanking.swift
//  TextOps
//
//  Most-recently-used ordering for a picker, persisted in user defaults.
//
//  Created by David Sherlock on 9/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Remembers which entries of a picker (commands, files) were chosen most recently, so an empty
/// query lists them first. A monotonic sequence stands in for a timestamp — higher is more recent
/// — which needs no clock and sorts trivially. Persisted under `key` in `defaults`.
public final class RecencyRanking: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String
    private let lock = NSLock()
    private var scores: [String: Int]
    private var sequence: Int

    /// A ranking stored under `key`, starting from whatever was stored there before.
    public init(key: String, defaults: UserDefaults = .standard) {
        self.key = key
        self.defaults = defaults
        scores = (defaults.dictionary(forKey: key) as? [String: Int]) ?? [:]
        sequence = scores.values.max() ?? 0
    }

    /// Records a choice of `name`, making it the most recent.
    public func record(_ name: String) {
        lock.lock(); defer { lock.unlock() }
        sequence += 1
        scores[name] = sequence
        defaults.set(scores, forKey: key)
    }

    /// Recency of `name`: higher is more recent, 0 for never chosen.
    public func rank(_ name: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return scores[name] ?? 0
    }

    /// `items` with the most recently chosen first; items never chosen keep their order after them.
    public func ordered<T>(_ items: [T], by name: (T) -> String) -> [T] {
        items.enumerated().sorted { a, b in
            let ra = rank(name(a.element)), rb = rank(name(b.element))
            return ra != rb ? ra > rb : a.offset < b.offset
        }.map(\.element)
    }
}
