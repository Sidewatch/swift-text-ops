//
//  EditorConfig.swift
//  TextOps
//
//  Reads `.editorconfig` files: the project's own answer to how a file should be indented.
//
//  Created by David Sherlock on 9/13/26.
//

import Foundation

/// The settings an `.editorconfig` states for one file.
///
/// Every field is optional and means "the file said nothing about this", which is not the same
/// as a default — a caller keeps its own preference wherever a key is absent, and only defers
/// where the project actually spoke.
public struct EditorConfigSettings: Equatable, Sendable {
    /// `indent_style = space | tab`.
    public var useSpaces: Bool?
    /// `indent_size`, in columns. `indent_size = tab` resolves to `tab_width`.
    public var indentWidth: Int?
    /// `tab_width`, in columns.
    public var tabWidth: Int?
    /// `trim_trailing_whitespace`.
    public var trimTrailingWhitespace: Bool?
    /// `insert_final_newline`.
    public var insertFinalNewline: Bool?

    public init(useSpaces: Bool? = nil, indentWidth: Int? = nil, tabWidth: Int? = nil,
                trimTrailingWhitespace: Bool? = nil, insertFinalNewline: Bool? = nil) {
        self.useSpaces = useSpaces
        self.indentWidth = indentWidth
        self.tabWidth = tabWidth
        self.trimTrailingWhitespace = trimTrailingWhitespace
        self.insertFinalNewline = insertFinalNewline
    }

    /// Whether the file said nothing at all.
    public var isEmpty: Bool { self == EditorConfigSettings() }

    /// Fills this value's gaps from `other`, keeping what is already set.
    ///
    /// The direction matters: `.editorconfig` resolution walks from the file's own directory
    /// UPWARD, and the nearest file wins, so a value already present is never overwritten by
    /// one found further up.
    func filling(from other: EditorConfigSettings) -> EditorConfigSettings {
        EditorConfigSettings(
            useSpaces: useSpaces ?? other.useSpaces,
            indentWidth: indentWidth ?? other.indentWidth,
            tabWidth: tabWidth ?? other.tabWidth,
            trimTrailingWhitespace: trimTrailingWhitespace ?? other.trimTrailingWhitespace,
            insertFinalNewline: insertFinalNewline ?? other.insertFinalNewline)
    }
}

/// Reads `.editorconfig` files and resolves what they say about a given file.
///
/// Supports the parts that change how text is edited — `indent_style`, `indent_size`,
/// `tab_width`, `trim_trailing_whitespace` and `insert_final_newline` — plus the section
/// globbing and `root` / nearest-file-wins rules that decide which of them apply. Deliberately
/// not a complete implementation of the spec: `charset` and `end_of_line` describe how a file is
/// written rather than how it is edited, and nothing here would act on them.
public enum EditorConfig {

    /// Resolves the settings for `file` by walking up from its directory.
    ///
    /// Stops at a file declaring `root = true`, or at the filesystem root. Sections are applied
    /// in the order they appear within a file (later sections override earlier ones, per the
    /// spec), and nearer files win over further ones.
    public static func settings(for file: URL) -> EditorConfigSettings {
        var resolved = EditorConfigSettings()
        var dir = file.deletingLastPathComponent().standardizedFileURL
        while true {
            let candidate = dir.appendingPathComponent(".editorconfig")
            if let text = try? String(contentsOf: candidate, encoding: .utf8) {
                let (settings, isRoot) = parse(text, for: file, relativeTo: dir)
                resolved = resolved.filling(from: settings)
                if isRoot { break }
            }
            let parent = dir.deletingLastPathComponent().standardizedFileURL
            if parent == dir { break }          // filesystem root
            dir = parent
        }
        return resolved
    }

    /// Parses one `.editorconfig` body, returning what applies to `file` and whether the file
    /// declared itself the root of the search.
    ///
    /// `base` is the directory the file sits in, which is what section globs are relative to.
    /// Exposed for testing without touching the filesystem.
    public static func parse(_ text: String, for file: URL,
                             relativeTo base: URL) -> (settings: EditorConfigSettings, isRoot: Bool) {
        var out = EditorConfigSettings()
        var isRoot = false
        var sectionApplies = false          // preamble keys are not in any section
        var inPreamble = true
        let relative = relativePath(of: file, under: base)

        // Split on `isNewline`, never on the Character `"\n"`: in Swift `"\r\n"` is ONE Character,
        // so `split(separator: "\n")` never divided a file authored on Windows at all — the whole
        // file was one "line", no section header was ever seen, and it was silently ignored
        // (18 Sep 2026). The trim is `.whitespacesAndNewlines` for the same reason.
        for rawLine in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") { continue }

            if line.hasPrefix("[") && line.hasSuffix("]") {
                inPreamble = false
                let pattern = String(line.dropFirst().dropLast())
                sectionApplies = relative.map { matches(pattern: pattern, path: $0) } ?? false
                continue
            }

            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[line.startIndex..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            // An inline `#` or `;` comment may follow a value, so the value is everything up to
            // one. Without this, `indent_style = space  # why` parses as the value
            // "space  # why" and silently matches nothing — the setting would appear to be
            // ignored, with the file looking perfectly correct.
            var rawValue = Substring(line[line.index(after: eq)...])
            if let hash = rawValue.firstIndex(where: { $0 == "#" || $0 == ";" }) {
                rawValue = rawValue[rawValue.startIndex..<hash]
            }
            let value = rawValue.trimmingCharacters(in: .whitespaces).lowercased()

            if inPreamble {
                if key == "root" { isRoot = (value == "true") }
                continue
            }
            guard sectionApplies else { continue }

            switch key {
            case "indent_style":
                if value == "space" { out.useSpaces = true }
                else if value == "tab" { out.useSpaces = false }
            case "indent_size":
                if value == "tab" { out.indentWidth = nil }     // resolved from tab_width below
                else if let n = Int(value), n > 0 { out.indentWidth = n }
            case "tab_width":
                if let n = Int(value), n > 0 { out.tabWidth = n }
            case "trim_trailing_whitespace":
                out.trimTrailingWhitespace = (value == "true")
            case "insert_final_newline":
                out.insertFinalNewline = (value == "true")
            default:
                continue
            }
        }
        // `indent_size = tab` (and a bare tab_width) means "indent by a tab stop".
        if out.indentWidth == nil, let tab = out.tabWidth { out.indentWidth = tab }
        return (out, isRoot)
    }

    /// `file`'s path relative to `base`, or nil when it is not under it.
    private static func relativePath(of file: URL, under base: URL) -> String? {
        let f = file.standardizedFileURL.pathComponents
        let b = base.standardizedFileURL.pathComponents
        guard f.count > b.count, Array(f.prefix(b.count)) == b else { return nil }
        return f.dropFirst(b.count).joined(separator: "/")
    }

    /// Whether an `.editorconfig` section pattern matches a path relative to that file.
    ///
    /// Implements the glob subset the format actually uses: `*` (within a path segment), `**`
    /// (across segments; `/**/` also matches a single `/`), `?`, character classes, and `{a,b}`
    /// alternation. A pattern with no slash matches the file's NAME at any depth, which is what
    /// makes `[*.swift]` mean what everyone expects.
    static func matches(pattern: String, path: String) -> Bool {
        var patterns = [pattern]
        if let expanded = expandBraces(pattern) { patterns = expanded }
        let name = path.split(separator: "/").last.map(String.init) ?? path
        for p in patterns {
            // The reference cores (editorconfig-core-c, -py) join a slash-bearing pattern onto the
            // `.editorconfig`'s own directory and match the whole path, which is what lets `/**/`
            // stand for zero directories at the START of a pattern too (`**/x` covers a top-level
            // `x`). Giving both the subject and the pattern a leading slash has the same effect.
            let anchored = p.hasPrefix("/") ? String(p.dropFirst()) : p
            let subject = p.contains("/") ? "/" + path : name
            let glob = p.contains("/") ? "/" + anchored : anchored
            if regex(for: glob).map({ subject.wholeMatch(of: $0) != nil }) == true { return true }
        }
        return false
    }

    /// Expands one level of `{a,b,c}` alternation, or nil when there is none.
    private static func expandBraces(_ pattern: String) -> [String]? {
        guard let open = pattern.firstIndex(of: "{"),
              let close = pattern[open...].firstIndex(of: "}") else { return nil }
        let head = String(pattern[pattern.startIndex..<open])
        let tail = String(pattern[pattern.index(after: close)...])
        let body = pattern[pattern.index(after: open)..<close]
        return body.split(separator: ",", omittingEmptySubsequences: false).flatMap { part -> [String] in
            let candidate = head + part + tail
            return expandBraces(candidate) ?? [candidate]
        }
    }

    /// Translates a glob into an anchored regular expression.
    private static func regex(for glob: String) -> Regex<AnyRegexOutput>? {
        var out = ""
        var chars = Array(glob)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            switch c {
            case "*":
                if i + 1 < chars.count, chars[i + 1] == "*" { out += ".*"; i += 2; continue }
                out += "[^/]*"
            case "?":
                out += "[^/]"
            case "/":
                // `/**/` is "a slash, or a slash, anything, a slash" — the reference cores'
                // translation, so `Sources/**/*.swift` covers `Sources/c.swift` as well as
                // `Sources/A/B/c.swift`. A bare `**` elsewhere still crosses separators.
                if i + 3 < chars.count, chars[i + 1] == "*", chars[i + 2] == "*", chars[i + 3] == "/" {
                    out += "(?:/|/.*/)"
                    i += 4
                    continue
                }
                out += "/"
            case "[":
                guard let close = chars[i...].firstIndex(of: "]"), close > i + 1 else { out += "\\["; break }
                var cls = String(chars[(i + 1)...(close - 1)])
                if cls.hasPrefix("!") { cls = "^" + cls.dropFirst() }
                out += "[" + cls + "]"
                i = close + 1
                continue
            default:
                out += NSRegularExpression.escapedPattern(for: String(c))
            }
            i += 1
        }
        return try? Regex(out)
    }
}
