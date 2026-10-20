//
//  TextEdit.swift
//  TextOps
//
//  One replacement in a text and where the selection lands afterwards.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// One replacement in a text and where the selection lands afterwards — what an editing command
/// computes, for the editor to apply as one undoable change. UTF-16 ranges, the editor's own.
public struct TextEdit: Equatable, Sendable {
    /// The range of the original text to replace.
    public let range: NSRange
    /// The text written over `range`.
    public let replacement: String
    /// The selection after the replacement, in the edited text's coordinates.
    public let selection: NSRange

    /// An edit.
    public init(range: NSRange, replacement: String, selection: NSRange) {
        self.range = range
        self.replacement = replacement
        self.selection = selection
    }
}
