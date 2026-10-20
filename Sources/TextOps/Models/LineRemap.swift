//
//  LineRemap.swift
//  TextOps
//
//  Where a line-anchored mark goes when an edit adds or removes lines.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// One edit's effect on line numbers, for anything anchored to a line (diff bands, tints, folds): marks
/// at or before the edit's line stay, marks on a line whose text the edit replaced are dropped (their
/// anchor text changed), and marks after it slide by the edit's line delta.
public struct LineRemap: Equatable, Sendable {
    /// The 1-based line the edit began on.
    public let editLine: Int
    /// The last 1-based line the edit's replaced span touched.
    public let spanEndLine: Int
    /// How many lines the edit added (negative: removed).
    public let lineDelta: Int

    /// The remap for an edit beginning on `editLine`, replacing through `spanEndLine`, adding `lineDelta`.
    public init(editLine: Int, spanEndLine: Int, lineDelta: Int) {
        self.editLine = editLine
        self.spanEndLine = spanEndLine
        self.lineDelta = lineDelta
    }

    /// Where a mark on 1-based `line` goes, or nil when the edit replaced its line.
    @inlinable
    public func line(_ line: Int) -> Int? {
        if line <= editLine { return line }
        if line <= spanEndLine { return nil }
        return line + lineDelta
    }
}
