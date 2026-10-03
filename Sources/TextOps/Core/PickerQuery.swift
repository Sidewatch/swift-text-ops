//
//  PickerQuery.swift
//  TextOps
//
//  The one-box picker's query language (VS Code / Zed style): a leading `>`, `@`, `#` or `:`
//  picks the mode, the rest is what to match; a file query may end in `:123`.
//
//  Created by David Sherlock on 10/3/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The one-box picker's query language (VS Code / Zed style). With no prefix the query names a
/// file and may end in `:123` to land on a line; a leading `>` lists commands, `@` the current
/// file's outline, `#` the project's symbols, and `:` jumps to a line in the current file.
/// Deleting the prefix returns the query to files.
public struct PickerQuery: Equatable, Sendable {
    /// What the list holds.
    public enum Mode: Equatable, Sendable, CaseIterable {
        /// Project files (no prefix).
        case files
        /// Commands (`>`).
        case commands
        /// The current file's outline (`@`).
        case outline
        /// Symbols defined anywhere in the project (`#`).
        case projectSymbols
        /// A line in the current file (`:`).
        case line

        /// The character that selects this mode, nil for files (no prefix).
        public var prefix: Character? {
            switch self {
            case .files: nil
            case .commands: ">"
            case .outline: "@"
            case .projectSymbols: "#"
            case .line: ":"
            }
        }
    }

    /// The mode the query selects.
    public let mode: Mode
    /// The text to match, without the prefix (or the `:123` suffix of a file query), trimmed.
    public let text: String
    /// The line a `:123` query (or a file query's `:123` suffix) names; nil when none is typed.
    public let line: Int?

    /// Creates a parsed query directly.
    public init(mode: Mode, text: String, line: Int?) {
        self.mode = mode
        self.text = text
        self.line = line
    }

    /// Parses what is typed into the picker's field.
    public init(_ raw: String) {
        guard let first = raw.first, let mode = Mode.allCases.first(where: { $0.prefix == first }) else {
            let (name, line) = Self.splitLineSuffix(raw)
            self.init(mode: .files, text: name.trimmingCharacters(in: .whitespaces), line: line)
            return
        }
        let rest = raw.dropFirst().trimmingCharacters(in: .whitespaces)
        if mode == .line {
            self.init(mode: .line, text: "", line: rest.isEmpty || !rest.allSatisfy(\.isNumber) ? nil : Int(rest))
        } else {
            self.init(mode: mode, text: rest, line: nil)
        }
    }

    /// Splits a trailing all-digits `:123` off a file query (`main.swift:42` → `main.swift`, 42).
    /// A bare trailing colon (`main.swift:`) filters by the name while the number is still being
    /// typed; anything else passes through untouched.
    public static func splitLineSuffix(_ query: String) -> (name: String, line: Int?) {
        guard let colon = query.lastIndex(of: ":") else { return (query, nil) }
        let suffix = query[query.index(after: colon)...]
        guard suffix.allSatisfy(\.isNumber) else { return (query, nil) }
        return (String(query[..<colon]), Int(suffix))
    }
}
