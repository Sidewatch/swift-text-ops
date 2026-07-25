//
//  SortKey.swift
//  SwiftTextOps
//
//  What a line is sorted *by* — its text, its leading number, or its length.
//
//  Created by David Sherlock on 7/25/26.
//

import Foundation

/// The value a sort compares lines on.
public enum SortKey: String, CaseIterable {

    /// The line text itself, compared lexicographically by Unicode scalar order.
    ///
    /// - Note: Scalar order puts every uppercase letter before every lowercase one, so `"Zebra"`
    ///   sorts before `"apple"`. Pass `caseInsensitive: true` to
    ///   ``LineOps/sort(_:by:descending:caseInsensitive:)`` for the friendlier ordering.
    case alphabetical

    /// The first number appearing anywhere in the line, compared numerically.
    ///
    /// Lines with no number are never sorted — they keep their relative order and collect at the
    /// end of the result, in ascending *and* descending directions.
    case numeric

    /// The line's character count.
    case length
}
