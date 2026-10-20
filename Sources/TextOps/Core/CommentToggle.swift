//
//  CommentToggle.swift
//  TextOps
//
//  Toggling line and block comments as one edit.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Comment toggles as pure edits: the caller supplies the language's delimiters and applies the
/// ``TextEdit`` as one undoable change.
public enum CommentToggle {
    /// Comments or uncomments every line the selection touches with `token` (`//`, `#`, `--`…).
    ///
    /// When every non-blank line already starts with the token (after its indentation) they are all
    /// uncommented — the token and one following space removed; otherwise every non-blank line gets
    /// `token` and a space after its indentation. Blank lines are left alone either way, and every
    /// line keeps its own break, whatever kind it is. The block is left selected.
    public static func line(in text: NSString, selection: NSRange, token: String) -> TextEdit {
        let block = text.lineRange(for: selection)
        var lines: [(content: String, terminator: String)] = []
        text.forEachLine(of: block) { line in
            let terminator = LineTerminator.of(line, in: text)
            let content = text.substring(with: NSRange(location: line.location, length: line.length - terminator.utf16.count))
            lines.append((content, terminator))
        }
        let nonBlank = lines.map(\.content).filter { !isBlank($0) }
        let uncomment = !nonBlank.isEmpty && nonBlank.allSatisfy { leadingIndent($0).rest.hasPrefix(token) }
        let out = lines.map { line -> String in
            guard !isBlank(line.content) else { return line.content + line.terminator }
            let (indent, rest) = leadingIndent(line.content)
            guard uncomment else { return indent + token + " " + rest + line.terminator }
            var body = rest.dropFirst(token.count)
            if body.hasPrefix(" ") { body = body.dropFirst() }
            return indent + body + line.terminator
        }.joined()
        return TextEdit(range: block, replacement: out, selection: NSRange(location: block.location, length: (out as NSString).length))
    }

    /// Wraps the selection's content in `open … close`, or unwraps it when it is exactly ONE such
    /// comment; with no selection, the content of the caret's line. Nil when there is no content
    /// (a blank line, or only whitespace selected).
    ///
    /// The delimiters wrap the content, not its surrounding whitespace, so the toggle round-trips to
    /// the original text: wrapping adds one space inside each delimiter and unwrapping removes at most
    /// one. A selection that starts with `open` and ends with `close` but closes earlier —
    /// `/* a */ x /* b */` — is two comments, and is wrapped, never unwrapped into broken code.
    public static func block(in text: NSString, selection: NSRange, open: String, close: String) -> TextEdit? {
        let outer = selection.length > 0 ? selection : text.lineRange(for: selection)
        let range = contentRange(within: outer, in: text)
        guard range.length > 0 else { return nil }
        let core = text.substring(with: range)
        let result: String
        if isOneComment(core, open: open, close: close) {
            var inner = Substring(core).dropFirst(open.count).dropLast(close.count)
            if inner.hasPrefix(" ") { inner = inner.dropFirst() }
            if inner.hasSuffix(" ") { inner = inner.dropLast() }
            result = String(inner)
        } else {
            result = open + " " + core + " " + close
        }
        return TextEdit(
            range: range, replacement: result, selection: NSRange(location: range.location, length: (result as NSString).length))
    }

    /// Whether `core` is exactly one comment: it opens with `open`, and the FIRST `close` after that is
    /// its end. The length guard covers text that is only the delimiters, and delimiters that are the
    /// same (AsciiDoc's `////`), whose two ends would otherwise overlap.
    private static func isOneComment(_ core: String, open: String, close: String) -> Bool {
        guard core.hasPrefix(open), core.hasSuffix(close), core.count >= open.count + close.count else { return false }
        let afterOpen = core.index(core.startIndex, offsetBy: open.count)
        return core.range(of: close, range: afterOpen..<core.endIndex).map { $0.upperBound == core.endIndex } ?? false
    }

    /// Whether a line holds nothing but whitespace.
    private static func isBlank(_ content: String) -> Bool { content.allSatisfy(\.isWhitespace) }

    /// A line's leading spaces and tabs, and the rest of it.
    private static func leadingIndent(_ content: String) -> (indent: String, rest: Substring) {
        let indent = content.prefix { $0 == " " || $0 == "\t" }
        return (String(indent), content.dropFirst(indent.count))
    }

    /// `range` shrunk past any leading and trailing whitespace or line breaks; zero-length when it
    /// holds nothing else.
    private static func contentRange(within range: NSRange, in text: NSString) -> NSRange {
        let space = CharacterSet.whitespacesAndNewlines
        var start = range.location, end = NSMaxRange(range)
        while start < end, let u = Unicode.Scalar(text.character(at: start)), space.contains(u) { start += 1 }
        while end > start, let u = Unicode.Scalar(text.character(at: end - 1)), space.contains(u) { end -= 1 }
        return NSRange(location: start, length: end - start)
    }
}
