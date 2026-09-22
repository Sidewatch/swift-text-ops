//
//  MarkdownFormatting.swift
//  TextOps
//
//  Markdown formatting as pure text edits: inline styles that toggle, block styles per line,
//  a link, and the Return that continues a list.
//
//  Created by David Sherlock on 9/22/26.
//

import Foundation

/// Markdown formatting as pure text edits (22 Sep 2026: Xcode's Markdown bar, "useful for quick
/// edits"). Every call takes the text and a UTF-16 selection and returns ONE replacement plus
/// the selection to land on — the editor applies it as one undo step. Inline styles toggle:
/// a selection already wrapped in the marker (inside it or just around it) is unwrapped, else
/// wrapped, and no selection means the word under the caret. Block styles act on every line
/// the selection touches and toggle off when every line already carries them. `listContinuation`
/// is what Return does on a list line: the next marker, or an empty item ending the list.
public enum MarkdownFormatting {
    public enum Inline: String, CaseIterable, Sendable {
        case bold = "**", italic = "*", strikethrough = "~~", code = "`"
        public var marker: String { rawValue }
    }

    public enum Block: Equatable, Sendable {
        case heading(Int), bullets, numbers, tasks, quote, codeBlock
    }

    /// One replacement and where the selection lands afterwards. UTF-16 ranges, the editor's own.
    public struct Edit: Equatable, Sendable {
        public let range: NSRange
        public let replacement: String
        public let selection: NSRange
        public init(range: NSRange, replacement: String, selection: NSRange) {
            self.range = range; self.replacement = replacement; self.selection = selection
        }
    }

    // MARK: - Inline

    public static func toggle(_ style: Inline, in text: String, selection: NSRange) -> Edit {
        let ns = text as NSString
        let marker = style.marker
        let mLen = (marker as NSString).length
        let target = selection.length > 0 ? clamp(selection, to: ns) : wordRange(in: ns, at: min(selection.location, ns.length))
        let inner = ns.substring(with: target)
        let innerNS = inner as NSString
        // A: the target carries its own markers ("**bold**" selected whole). For italic the
        // pair must be single stars — "**bold**" is bold, and italic on it adds a third star.
        if innerNS.length >= 2 * mLen, inner.hasPrefix(marker), inner.hasSuffix(marker),
           !(style == .italic && (inner.hasPrefix("**") || inner.hasSuffix("**"))) {
            let stripped = innerNS.substring(with: NSRange(location: mLen, length: innerNS.length - 2 * mLen))
            return Edit(range: target, replacement: stripped, selection: NSRange(location: target.location, length: (stripped as NSString).length))
        }
        // B: the markers sit just outside the target ("bold" selected inside "**bold**"). For
        // italic, a single star each side is italic; two each side is bold, untouched; three
        // is bold italic, and the italic comes off leaving the bold.
        let before = NSRange(location: target.location - mLen, length: mLen)
        let after = NSRange(location: NSMaxRange(target), length: mLen)
        if before.location >= 0, NSMaxRange(after) <= ns.length,
           ns.substring(with: before) == marker, ns.substring(with: after) == marker {
            let starsBefore = style == .italic ? run(of: "*", in: ns, endingBefore: target.location) : 0
            let starsAfter = style == .italic ? run(of: "*", in: ns, startingAt: NSMaxRange(target)) : 0
            let italicPair = style != .italic || starsBefore == 1 || starsBefore == 3 || starsAfter == 1 || starsAfter == 3
            if italicPair, style != .italic || (starsBefore != 2 && starsAfter != 2) {
                let outer = NSRange(location: before.location, length: NSMaxRange(after) - before.location)
                return Edit(range: outer, replacement: inner, selection: NSRange(location: before.location, length: innerNS.length))
            }
        }
        return Edit(range: target, replacement: marker + inner + marker,
                    selection: NSRange(location: target.location + mLen, length: innerNS.length))
    }

    // MARK: - Block

    public static func toggle(_ block: Block, in text: String, selection: NSRange) -> Edit {
        let ns = text as NSString
        let lines = ns.lineRange(for: clamp(selection, to: ns))
        var body = ns.substring(with: lines)
        let hadNewline = body.hasSuffix("\n")
        if hadNewline { body.removeLast() }
        var rows = body.components(separatedBy: "\n")
        let content = rows.filter { !isBlank($0) }
        switch block {
        case .heading(let level):
            let prefix = String(repeating: "#", count: max(1, min(6, level))) + " "
            let allAtLevel = !content.isEmpty && content.allSatisfy { $0.hasPrefix(prefix) && !$0.hasPrefix(prefix + "#") }
            rows = rows.map { row in
                if isBlank(row) { return row }
                let bare = stripping(row, pattern: "^#{1,6} ")
                return allAtLevel ? bare : prefix + bare
            }
        case .bullets:
            let allHave = !content.isEmpty && content.allSatisfy { listParts($0)?.kind == .bullet }
            rows = rows.map { row in
                guard !isBlank(row) else { return row }
                let p = listParts(row) ?? (indent: leadingSpace(row), kind: .none, marker: "", rest: row.dropFirst(leadingSpace(row).count).description)
                return allHave ? p.indent + p.rest : p.indent + "- " + p.rest
            }
        case .numbers:
            let allHave = !content.isEmpty && content.allSatisfy { listParts($0)?.kind == .number }
            var n = 0
            rows = rows.map { row in
                guard !isBlank(row) else { return row }
                let p = listParts(row) ?? (indent: leadingSpace(row), kind: .none, marker: "", rest: row.dropFirst(leadingSpace(row).count).description)
                if allHave { return p.indent + p.rest }
                n += 1
                return p.indent + "\(n). " + p.rest
            }
        case .tasks:
            let allHave = !content.isEmpty && content.allSatisfy { listParts($0)?.kind == .task }
            rows = rows.map { row in
                guard !isBlank(row) else { return row }
                let p = listParts(row) ?? (indent: leadingSpace(row), kind: .none, marker: "", rest: row.dropFirst(leadingSpace(row).count).description)
                return allHave ? p.indent + p.rest : p.indent + "- [ ] " + p.rest
            }
        case .quote:
            let allHave = !rows.isEmpty && rows.allSatisfy { $0.hasPrefix(">") || isBlank($0) } && rows.contains { $0.hasPrefix(">") }
            rows = rows.map { row in allHave ? stripping(row, pattern: "^> ?") : (isBlank(row) ? ">" : "> " + row) }
        case .codeBlock:
            if rows.count >= 2, rows.first!.hasPrefix("```"), rows.last! == "```" {
                rows = Array(rows.dropFirst().dropLast())
            } else {
                rows = ["```"] + rows + ["```"]
            }
        }
        let replacement = rows.joined(separator: "\n") + (hadNewline ? "\n" : "")
        let selectedLength = (replacement as NSString).length - (hadNewline ? 1 : 0)
        return Edit(range: lines, replacement: replacement, selection: NSRange(location: lines.location, length: selectedLength))
    }

    // MARK: - Link

    /// `[text](url)`: a selected URL becomes the address with "text" selected to type over;
    /// any other selection (or the word at the caret) becomes the text with "url" selected.
    public static func link(in text: String, selection: NSRange) -> Edit {
        let ns = text as NSString
        let target = selection.length > 0 ? clamp(selection, to: ns) : wordRange(in: ns, at: min(selection.location, ns.length))
        let inner = ns.substring(with: target)
        if inner.hasPrefix("http://") || inner.hasPrefix("https://") {
            return Edit(range: target, replacement: "[text](\(inner))", selection: NSRange(location: target.location + 1, length: 4))
        }
        if inner.isEmpty {
            return Edit(range: target, replacement: "[text](url)", selection: NSRange(location: target.location + 1, length: 4))
        }
        let labelLength = (inner as NSString).length
        return Edit(range: target, replacement: "[\(inner)](url)", selection: NSRange(location: target.location + 1 + labelLength + 2, length: 3))
    }

    // MARK: - Return in a list

    /// What Return does with the caret on a list, task or quote line: nil for any other line
    /// (the editor's own Return applies); otherwise a newline plus the next marker — a number
    /// one higher, a task unticked — or, on an EMPTY item with the caret at its end, the
    /// marker removed and no newline, which is how a list ends.
    public static func listContinuation(in text: String, caret: Int) -> Edit? {
        let ns = text as NSString
        guard caret >= 0, caret <= ns.length else { return nil }
        let lineRange = ns.lineRange(for: NSRange(location: caret, length: 0))
        var line = ns.substring(with: lineRange)
        if line.hasSuffix("\n") { line.removeLast() }
        let lineNS = line as NSString
        guard let parts = listParts(line) ?? quoteParts(line) else { return nil }
        let head = parts.indent + parts.marker
        let headLength = (head as NSString).length
        let markerEnd = lineRange.location + headLength
        guard caret >= markerEnd else { return nil }   // the caret inside the marker: an ordinary Return
        if isBlank(parts.rest), caret == lineRange.location + lineNS.length {
            return Edit(range: NSRange(location: lineRange.location, length: headLength), replacement: "",
                        selection: NSRange(location: lineRange.location, length: 0))
        }
        let next: String
        switch parts.kind {
        case .number: next = "\((Int(parts.marker.trimmingCharacters(in: CharacterSet(charactersIn: ". "))) ?? 0) + 1). "
        case .task: next = String(parts.marker.prefix(2)) + "[ ] "
        default: next = parts.marker
        }
        let insert = "\n" + parts.indent + next
        return Edit(range: NSRange(location: caret, length: 0), replacement: insert,
                    selection: NSRange(location: caret + (insert as NSString).length, length: 0))
    }

    // MARK: - Pieces

    enum ListKind { case none, bullet, number, task, quote }
    typealias Parts = (indent: String, kind: ListKind, marker: String, rest: String)

    /// The leading whitespace, the list marker and the rest of a line, or nil for a plain line.
    static func listParts(_ line: String) -> Parts? {
        guard let m = listRegex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) else { return nil }
        let ns = line as NSString
        func group(_ i: Int) -> String { m.range(at: i).location == NSNotFound ? "" : ns.substring(with: m.range(at: i)) }
        let marker = group(2)
        let kind: ListKind = marker.contains("[") ? .task : (marker.first?.isNumber == true ? .number : .bullet)
        return (group(1), kind, marker, group(3))
    }

    static func quoteParts(_ line: String) -> Parts? {
        guard let m = quoteRegex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) else { return nil }
        let ns = line as NSString
        return (ns.substring(with: m.range(at: 1)), .quote, ns.substring(with: m.range(at: 2)), ns.substring(with: m.range(at: 3)))
    }

    private static let listRegex = try! NSRegularExpression(pattern: "^([ \\t]*)((?:[-*+] \\[[ xX]\\] )|(?:[-*+] )|(?:[0-9]+\\. ))(.*)$")
    private static let quoteRegex = try! NSRegularExpression(pattern: "^([ \\t]*)(> ?)(.*)$")

    private static func stripping(_ row: String, pattern: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return row }
        return re.stringByReplacingMatches(in: row, range: NSRange(location: 0, length: (row as NSString).length), withTemplate: "")
    }

    private static func isBlank(_ s: String) -> Bool { s.trimmingCharacters(in: .whitespaces).isEmpty }
    private static func leadingSpace(_ s: String) -> String { String(s.prefix { $0 == " " || $0 == "\t" }) }

    private static func clamp(_ r: NSRange, to ns: NSString) -> NSRange {
        let loc = min(max(0, r.location), ns.length)
        return NSRange(location: loc, length: min(r.length, ns.length - loc))
    }

    /// How many `ch` in a row end just before `endingBefore` / begin at `startingAt`.
    private static func run(of ch: Character, in ns: NSString, endingBefore: Int) -> Int {
        var n = 0, i = endingBefore - 1
        while i >= 0, character(in: ns, at: i) == ch { n += 1; i -= 1 }
        return n
    }
    private static func run(of ch: Character, in ns: NSString, startingAt: Int) -> Int {
        var n = 0, i = startingAt
        while character(in: ns, at: i) == ch { n += 1; i += 1 }
        return n
    }

    private static func character(in ns: NSString, at i: Int) -> Character? {
        guard i >= 0, i < ns.length else { return nil }
        return Character(ns.substring(with: NSRange(location: i, length: 1)))
    }

    /// The word (letters, digits, underscore) around `at`; an empty range there when none.
    static func wordRange(in ns: NSString, at: Int) -> NSRange {
        func isWord(_ i: Int) -> Bool {
            guard let c = character(in: ns, at: i) else { return false }
            return c.isLetter || c.isNumber || c == "_"
        }
        var start = at, end = at
        while start > 0, isWord(start - 1) { start -= 1 }
        while isWord(end) { end += 1 }
        return NSRange(location: start, length: end - start)
    }
}
