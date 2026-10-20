//
//  Fold.swift
//  TextOps
//
//  A run of lines collapsed behind the line above it.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// A fold: the 1-based lines in `hidden` collapse behind the visible line at `anchor`.
public struct Fold: Equatable, Hashable, Sendable {
    /// The line that stays visible and carries the fold's marker.
    public let anchor: Int
    /// The lines the fold hides.
    public let hidden: ClosedRange<Int>

    /// A fold of `hidden` behind `anchor`.
    public init(anchor: Int, hidden: ClosedRange<Int>) {
        self.anchor = anchor
        self.hidden = hidden
    }
}
