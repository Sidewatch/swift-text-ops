//
//  LineEnding.swift
//  SwiftTextOps
//
//  The three line terminators a text can use, so a transform can put back what it found.
//
//  Created by David Sherlock on 7/25/26.
//

import Foundation

/// A line terminator.
///
/// ``TextLines`` detects which one a text uses so a round-trip through a line transform can
/// re-join with the original terminator rather than silently rewriting the whole file to LF.
public enum LineEnding: String, CaseIterable {

    /// Unix / macOS: `\n`.
    case lf = "\n"

    /// Windows: `\r\n`.
    case crlf = "\r\n"

    /// Classic Mac OS: `\r`.
    case cr = "\r"
}
