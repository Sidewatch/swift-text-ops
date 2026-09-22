//
//  MarkdownFormatting+Tables.swift
//  TextOps
//
//  Pipe tables as pure text edits: read the table at the caret, format it aligned, insert and
//  delete rows and columns, and insert a new one.
//
//  Created by David Sherlock on 9/22/26.
//

import Foundation

extension MarkdownFormatting {

    /// One edit to the pipe table at the caret.
    public enum TableEdit: Equatable, Sendable, CaseIterable {
        case format, insertRowAbove, insertRowBelow, insertColumnBefore, insertColumnAfter, deleteRow, deleteColumn
    }

    /// A column's alignment, from the separator row's colons (`:---`, `:---:`, `---:`).
    public enum ColumnAlignment: Equatable, Sendable { case none, left, center, right }

    /// The pipe table around a selection, as cells.
    public struct Table: Equatable, Sendable {
        /// The table's lines in the text; the last line's newline is not included.
        public let range: NSRange
        /// The header row, then the body rows (the separator is not a row); every row has
        /// `columns` cells, trimmed, a `\|` kept as written.
        public var rows: [[String]]
        public var alignments: [ColumnAlignment]
        /// The caret's row (0 is the header; a caret on the separator line counts as the
        /// header) and column, clamped into the table.
        public let row: Int
        public let column: Int
        public var columns: Int { alignments.count }

        public init(range: NSRange, rows: [[String]], alignments: [ColumnAlignment], row: Int, column: Int) {
            self.range = range; self.rows = rows; self.alignments = alignments; self.row = row; self.column = column
        }
    }

    // MARK: - Reading

    /// The pipe table whose lines include the selection's line, or `nil`: a run of lines that
    /// carry an unescaped `|`, whose second line is a separator row.
    public static func table(in text: String, selection: NSRange) -> Table? {
        let ns = text as NSString
        let sel = clamp(selection, to: ns)
        let lines = text.components(separatedBy: "\n")
        var starts: [Int] = []
        var pos = 0
        for line in lines { starts.append(pos); pos += (line as NSString).length + 1 }
        guard let caretLine = lines.indices.last(where: { starts[$0] <= sel.location }) else { return nil }
        guard isTableLine(lines[caretLine]) else { return nil }
        var first = caretLine, last = caretLine
        while first > 0, isTableLine(lines[first - 1]) { first -= 1 }
        while last + 1 < lines.count, isTableLine(lines[last + 1]) { last += 1 }
        guard last > first, let alignments = separatorAlignments(lines[first + 1]) else { return nil }
        var rows = ([lines[first]] + lines[(first + 2)...last]).map(cells)
        let columns = max(alignments.count, rows.map(\.count).max() ?? 0)
        rows = rows.map { $0 + Array(repeating: "", count: columns - $0.count) }
        let fullAlignments = alignments + Array(repeating: .none, count: columns - alignments.count)
        let row = caretLine <= first + 1 ? 0 : caretLine - first - 1
        let column = min(columns - 1, max(0, cellIndex(in: lines[caretLine], at: sel.location - starts[caretLine])))
        let range = NSRange(location: starts[first], length: starts[last] + (lines[last] as NSString).length - starts[first])
        return Table(range: range, rows: rows, alignments: fullAlignments, row: row, column: column)
    }

    /// A line that belongs to a table: not blank, with an unescaped `|`.
    static func isTableLine(_ line: String) -> Bool {
        !isBlank(line) && line.contains("|") && !cells(line).isEmpty
    }

    /// The cells of a row: one leading and one trailing `|` dropped, split on unescaped `|`, trimmed.
    static func cells(_ line: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var escaped = false
        for ch in line {
            if escaped { current.append(ch); escaped = false; continue }
            if ch == "\\" { current.append(ch); escaped = true; continue }
            if ch == "|" { parts.append(current); current = "" } else { current.append(ch) }
        }
        parts.append(current)
        let trimmed = parts.map { $0.trimmingCharacters(in: .whitespaces) }
        var out = trimmed
        if out.first == "" && line.trimmingCharacters(in: .whitespaces).hasPrefix("|") { out.removeFirst() }
        if out.last == "" && line.trimmingCharacters(in: .whitespaces).hasSuffix("|") && !line.trimmingCharacters(in: .whitespaces).hasSuffix("\\|") { out.removeLast() }
        return out
    }

    /// The alignments a separator row declares, or `nil` when the line is not one
    /// (every cell `:?-+:?`).
    static func separatorAlignments(_ line: String) -> [ColumnAlignment]? {
        let parts = cells(line)
        guard !parts.isEmpty else { return nil }
        var out: [ColumnAlignment] = []
        for p in parts {
            guard p.range(of: "^:?-+:?$", options: .regularExpression) != nil else { return nil }
            switch (p.hasPrefix(":"), p.hasSuffix(":")) {
            case (true, true): out.append(.center)
            case (true, false): out.append(.left)
            case (false, true): out.append(.right)
            default: out.append(.none)
            }
        }
        return out
    }

    /// The cell the caret sits in on a row line: the unescaped `|`s before it, minus the
    /// leading one when the row has it.
    static func cellIndex(in line: String, at offset: Int) -> Int {
        let ns = line as NSString
        var pipes = 0
        var i = 0
        let end = min(max(0, offset), ns.length)
        while i < end {
            let c = ns.character(at: i)
            if c == 0x5C { i += 2; continue }   // backslash: skip the escaped character
            if c == 0x7C { pipes += 1 }
            i += 1
        }
        return line.trimmingCharacters(in: .whitespaces).hasPrefix("|") ? pipes - 1 : pipes
    }

    // MARK: - Writing

    /// The table laid out aligned: every column as wide as its widest cell (at least three),
    /// cells padded per the column's alignment, the separator carrying the colons.
    public static func render(_ table: Table) -> String {
        let widths = (0..<table.columns).map { c in max(3, table.rows.map { $0[c].count }.max() ?? 0) }
        func line(_ cells: [String]) -> String {
            "| " + cells.enumerated().map { c, cell in pad(cell, to: widths[c], table.alignments[c]) }.joined(separator: " | ") + " |"
        }
        let separator = "| " + widths.enumerated().map { c, w in
            switch table.alignments[c] {
            case .none: return String(repeating: "-", count: w)
            case .left: return ":" + String(repeating: "-", count: w - 1)
            case .right: return String(repeating: "-", count: w - 1) + ":"
            case .center: return ":" + String(repeating: "-", count: w - 2) + ":"
            }
        }.joined(separator: " | ") + " |"
        guard let header = table.rows.first else { return separator }
        return ([line(header), separator] + table.rows.dropFirst().map(line)).joined(separator: "\n")
    }

    private static func pad(_ cell: String, to width: Int, _ alignment: ColumnAlignment) -> String {
        let extra = max(0, width - cell.count)
        switch alignment {
        case .right: return String(repeating: " ", count: extra) + cell
        case .center: return String(repeating: " ", count: extra / 2) + cell + String(repeating: " ", count: extra - extra / 2)
        default: return cell + String(repeating: " ", count: extra)
        }
    }

    /// `edit` applied to the table at the selection, or `nil` when there is none or the edit
    /// does not apply (deleting the header row, deleting the only column). The selection lands
    /// on the caret's cell in the rewritten table — the new row or column when one was added.
    public static func table(_ edit: TableEdit, in text: String, selection: NSRange) -> Edit? {
        guard var t = table(in: text, selection: selection) else { return nil }
        var row = t.row, column = t.column
        let empty = Array(repeating: "", count: t.columns)
        switch edit {
        case .format: break
        case .insertRowBelow: t.rows.insert(empty, at: row + 1); row += 1
        case .insertRowAbove: row = max(1, row); t.rows.insert(empty, at: row)   // never above the header
        case .deleteRow:
            guard row > 0 else { return nil }
            t.rows.remove(at: row)
            row = min(row, t.rows.count - 1)
        case .insertColumnBefore, .insertColumnAfter:
            let at = edit == .insertColumnBefore ? column : column + 1
            t.rows = t.rows.map { var r = $0; r.insert("", at: at); return r }
            t.alignments.insert(.none, at: at)
            column = at
        case .deleteColumn:
            guard t.columns > 1 else { return nil }
            t.rows = t.rows.map { var r = $0; r.remove(at: column); return r }
            t.alignments.remove(at: column)
            column = min(column, t.columns - 1)
        }
        let rendered = render(t)
        return Edit(range: t.range, replacement: rendered,
                    selection: NSRange(location: t.range.location + cellOffset(in: t, rendered: rendered, row: row, column: column), length: 0))
    }

    /// Where the text of cell (`row`, `column`) starts in `rendered`.
    private static func cellOffset(in table: Table, rendered: String, row: Int, column: Int) -> Int {
        let lines = rendered.components(separatedBy: "\n")
        let lineIndex = row == 0 ? 0 : row + 1
        var offset = 0
        for l in lines.prefix(lineIndex) { offset += (l as NSString).length + 1 }
        let widths = (0..<table.columns).map { c in max(3, table.rows.map { $0[c].count }.max() ?? 0) }
        var inLine = 2
        for c in 0..<column { inLine += widths[c] + 3 }
        let field = pad(table.rows[row][column], to: widths[column], table.alignments[column])
        let lead = field.prefix { $0 == " " }.count
        return offset + inLine + (field.trimmingCharacters(in: .whitespaces).isEmpty ? 0 : lead)
    }

    /// A new table on its own paragraph at the caret's line — in place of a blank line, or
    /// after a line with text — with "Column 1" selected to type over.
    public static func insertTable(in text: String, selection: NSRange, columns: Int = 3, rows: Int = 2) -> Edit {
        let ns = text as NSString
        let sel = clamp(selection, to: ns)
        let cols = max(1, columns)
        let header = (1...cols).map { "Column \($0)" }
        let body = Array(repeating: Array(repeating: "", count: cols), count: max(0, rows))
        let rendered = render(Table(range: NSRange(location: 0, length: 0), rows: [header] + body,
                                    alignments: Array(repeating: .none, count: cols), row: 0, column: 0))
        let lineRange = ns.lineRange(for: NSRange(location: sel.location, length: 0))
        var line = ns.substring(with: lineRange)
        let hadNewline = line.hasSuffix("\n")
        if hadNewline { line.removeLast() }
        if isBlank(line) {
            return Edit(range: lineRange, replacement: rendered + (hadNewline ? "\n" : ""),
                        selection: NSRange(location: lineRange.location + 2, length: (header[0] as NSString).length))
        }
        let end = lineRange.location + (line as NSString).length
        return Edit(range: NSRange(location: end, length: 0), replacement: "\n\n" + rendered,
                    selection: NSRange(location: end + 4, length: (header[0] as NSString).length))
    }
}
