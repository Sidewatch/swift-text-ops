//
//  LetterCase.swift
//  SwiftTextOps
//
//  The case transforms a line can be re-cased into.
//
//  Created by David Sherlock on 7/25/26.
//

import Foundation

/// A whole-line case transform.
public enum LetterCase: String, CaseIterable {

    /// Everything lowercased.
    case lower

    /// Everything uppercased.
    case upper

    /// Each word's first letter uppercased, the rest lowercased.
    ///
    /// - Note: This is Foundation's `capitalized`, which lowercases the remainder of every word —
    ///   so intercapped words are flattened (`"iPhone"` becomes `"Iphone"`). That is the standard
    ///   title-case behaviour, not a bug.
    case title
}
