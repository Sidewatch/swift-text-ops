//
//  LineEdits.swift
//  TextOps
//
//  The editor's line commands — duplicate, move, delete, indent, unindent — as pure edits.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The editor's line commands as pure functions from a text and its selection to one ``TextEdit``:
/// duplicate the line or block (⌥⇧↑ / ⌥⇧↓), move it (⌥↑ / ⌥↓), delete it (⌃⇧K), indent and unindent
/// a block (Tab / ⇧Tab). The editor applies the edit as one undoable change.
///
/// Lines are NSString's (`lineRange(for:)`), and every break is read through ``LineTerminator``, so a
/// CRLF, CR or Unicode-separated file behaves exactly like an LF one: no stray `\r` left behind, no
/// two lines welded together, no break doubled. A command that has nothing to do returns nil.
public enum LineEdits {
    // MARK: - Duplicate

    /// A copy of the line or selected block inserted at its own start. With `followCopy` false the
    /// selection stays on the UPPER copy (⌥⇧↑); true, it moves to the LOWER one (⌥⇧↓). An unterminated
    /// last line gets the text's own break added to its copy, so the two never weld.
    public static func duplicate(in text: String, selection: NSRange, followCopy: Bool) -> TextEdit? {
        let ns = text as NSString
        guard ns.length > 0 else { return nil }
        let lines = ns.lineRange(for: selection)
        var block = ns.substring(with: lines)
        if LineTerminator.of(lines, in: ns).isEmpty { block += LineTerminator.preferred(in: ns) }
        let inserted = (block as NSString).length
        let start = selection.location + (followCopy ? inserted : 0)
        return TextEdit(
            range: NSRange(location: lines.location, length: 0), replacement: block,
            selection: NSRange(location: start, length: selection.length))
    }

    // MARK: - Move

    /// The line or selected block swapped with the line above, the selection moving with it; nil on
    /// the first line. Moving the unterminated last line up takes the break from the line it passes.
    public static func moveUp(in text: String, selection: NSRange) -> TextEdit? {
        let ns = text as NSString
        guard ns.length > 0 else { return nil }
        let current = ns.lineRange(for: selection)
        guard current.location > 0 else { return nil }
        let above = ns.lineRange(for: NSRange(location: current.location - 1, length: 0))
        var currentText = ns.substring(with: current), aboveText = ns.substring(with: above)
        let aboveBreak = LineTerminator.of(above, in: ns)
        if LineTerminator.of(current, in: ns).isEmpty, !aboveBreak.isEmpty {
            currentText += aboveBreak
            aboveText = String((aboveText as NSString).substring(to: (aboveText as NSString).length - (aboveBreak as NSString).length))
        }
        let span = NSRange(location: above.location, length: NSMaxRange(current) - above.location)
        let start = above.location + (selection.location - current.location)
        return TextEdit(range: span, replacement: currentText + aboveText, selection: NSRange(location: start, length: selection.length))
    }

    /// The line or selected block swapped with the line below, the selection moving with it; nil on
    /// the last line. Passing the unterminated last line hands it the block's break.
    public static func moveDown(in text: String, selection: NSRange) -> TextEdit? {
        let ns = text as NSString
        guard ns.length > 0 else { return nil }
        let current = ns.lineRange(for: selection)
        guard NSMaxRange(current) < ns.length else { return nil }
        let below = ns.lineRange(for: NSRange(location: NSMaxRange(current), length: 0))
        var currentText = ns.substring(with: current), belowText = ns.substring(with: below)
        let currentBreak = LineTerminator.of(current, in: ns)
        if LineTerminator.of(below, in: ns).isEmpty, !currentBreak.isEmpty {
            belowText += currentBreak
            currentText = String(
                (currentText as NSString).substring(to: (currentText as NSString).length - (currentBreak as NSString).length))
        }
        let span = NSRange(location: current.location, length: NSMaxRange(below) - current.location)
        let start = current.location + (belowText as NSString).length + (selection.location - current.location)
        return TextEdit(range: span, replacement: belowText + currentText, selection: NSRange(location: start, length: selection.length))
    }

    // MARK: - Delete

    /// The line (or selected lines) removed with its break, the caret where it started. The last line
    /// takes the break BEFORE it instead — the whole break, two units for CRLF — so no blank line and
    /// no stray `\r` is left.
    public static func deleteLine(in text: String, selection: NSRange) -> TextEdit? {
        let ns = text as NSString
        guard ns.length > 0 else { return nil }
        var lines = ns.lineRange(for: selection)
        if NSMaxRange(lines) == ns.length, lines.location > 0 {
            let before = LineTerminator.length(endingAt: lines.location, in: ns)
            lines = NSRange(location: lines.location - before, length: lines.length + before)
        }
        let caret = min(lines.location, ns.length - lines.length)
        return TextEdit(range: lines, replacement: "", selection: NSRange(location: caret, length: 0))
    }

    // MARK: - Indent

    /// One `unit` added at the start of every line a multi-line selection touches, the block left
    /// selected; nil for an empty or single-line selection (Tab inserts there instead). A line start
    /// at the very end of the block — after its final break — is not indented.
    public static func indent(in text: String, selection: NSRange, unit: String) -> TextEdit? {
        let ns = text as NSString
        guard selection.length > 0, spansLines(ns, selection) else { return nil }
        let lines = ns.lineRange(for: selection)
        var out = ""
        ns.forEachLine(of: lines) { line in out += unit + ns.substring(with: line) }
        return TextEdit(range: lines, replacement: out, selection: NSRange(location: lines.location, length: (out as NSString).length))
    }

    /// One level of indentation removed from every line the selection touches (the caret's line
    /// when nothing is selected): a leading tab, or up to `width` leading spaces; the block is left
    /// selected. Nil when no line had any.
    public static func unindent(in text: String, selection: NSRange, width: Int) -> TextEdit? {
        let ns = text as NSString
        let lines = ns.lineRange(for: selection)
        var out = "", changed = false
        ns.forEachLine(of: lines) { line in
            let s = ns.substring(with: line)
            let drop = s.hasPrefix("\t") ? 1 : s.prefix(max(0, width)).prefix { $0 == " " }.count
            if drop > 0 { changed = true }
            out += String(s.dropFirst(drop))
        }
        guard changed else { return nil }
        return TextEdit(range: lines, replacement: out, selection: NSRange(location: lines.location, length: (out as NSString).length))
    }

    // MARK: - Lines

    /// Whether the selected text holds a line break of any kind (so it touches more than a run of one line's characters).
    private static func spansLines(_ ns: NSString, _ selection: NSRange) -> Bool {
        ns.substring(with: selection).rangeOfCharacter(from: .newlines) != nil
    }
}
