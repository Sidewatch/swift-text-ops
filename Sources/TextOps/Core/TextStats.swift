//
//  TextStats.swift
//  SwiftTextOps
//
//  Line / word / character counts for a live readout beside a list.
//
//  Created by David Sherlock on 7/25/26.
//

import Foundation

/// Counts describing a block of lines.
public struct TextStats: Equatable {

    /// How many lines there are.
    public let lines: Int

    /// How many whitespace-separated words there are, across every line.
    public let words: Int

    /// How many characters there are, counting the whitespace inside a line but not the line
    /// terminators between them.
    public let characters: Int

    /// Creates a set of counts.
    ///
    /// - Parameters:
    ///   - lines: The line count.
    ///   - words: The word count.
    ///   - characters: The character count.
    public init(lines: Int, words: Int, characters: Int) {
        self.lines = lines
        self.words = words
        self.characters = characters
    }

    /// Counts `lines`.
    ///
    /// Words are runs of non-whitespace, so punctuation attached to a word doesn't split it and
    /// runs of spaces don't inflate the count. Blank lines still count as lines.
    ///
    /// - Parameter lines: The lines to measure.
    /// - Returns: The counts.
    public static func measure(_ lines: [String]) -> TextStats {
        var words = 0
        var characters = 0
        for line in lines {
            words += line.split(whereSeparator: \.isWhitespace).count
            characters += line.count
        }
        return TextStats(lines: lines.count, words: words, characters: characters)
    }
}
