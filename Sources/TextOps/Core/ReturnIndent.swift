//
//  ReturnIndent.swift
//  TextOps
//
//  What Return inserts: the line's indentation carried over, one unit more after an opener.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The edit Return makes in a code editor, as one ``TextEdit``.
///
/// Only the whitespace BEFORE the caret is carried, so Return at column 0 moves an indented line down
/// unchanged. When the text before the caret ends in an opener (`{`, `(` or `[`, any trailing spaces
/// aside) the new line gets one `unit` more. Return BETWEEN a pair — `{|}`, the shape auto-close leaves —
/// puts the closer on its own line at the base indentation and the caret on the indented line between.
/// There is no language table and no dedent on `}`: re-indent and formatting own the rest. Tabs stay
/// tabs, because the indentation is copied, not rebuilt.
public enum ReturnIndent {
    /// The edit for Return over `range` (a caret or a selection, which it replaces), indenting with
    /// `unit`. Nil when a plain newline is already right: nothing to carry and no opener before the caret.
    public static func edit(in text: NSString, at range: NSRange, unit: String) -> TextEdit? {
        let location = min(range.location, text.length)
        let lineStart = text.lineRange(for: NSRange(location: location, length: 0)).location
        let head = text.substring(with: NSRange(location: lineStart, length: location - lineStart))
        let base = String(head.prefix { $0 == " " || $0 == "\t" })
        let opener = head.last { !$0.isWhitespace }
        var indent = base
        if let opener, AutoClose.brackets[opener] != nil { indent += unit }
        let end = min(NSMaxRange(range), text.length)
        if let opener, let close = AutoClose.brackets[opener], end < text.length,
            text.substring(with: NSRange(location: end, length: 1)) == String(close)
        {
            let caret = range.location + 1 + (indent as NSString).length
            return TextEdit(range: range, replacement: "\n" + indent + "\n" + base, selection: NSRange(location: caret, length: 0))
        }
        guard !indent.isEmpty else { return nil }
        let replacement = "\n" + indent
        return TextEdit(
            range: range, replacement: replacement,
            selection: NSRange(location: range.location + (replacement as NSString).length, length: 0))
    }
}
