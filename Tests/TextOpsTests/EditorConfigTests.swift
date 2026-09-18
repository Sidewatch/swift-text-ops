//
//  EditorConfigTests.swift
//  TextOps
//
//  Tests for `EditorConfig`: glob matching, and resolution across real `.editorconfig` files
//  written to a temp tree.
//
//  Created by David Sherlock on 9/13/26.
//

import XCTest
@testable import TextOps

/// Tests for `EditorConfig`. The resolution tests write actual files to a temp directory and
/// resolve actual paths through them — the walk-up, `root = true` and nearest-wins rules are
/// the whole feature, and a parser exercised only on strings would not touch any of them.
final class EditorConfigTests: XCTestCase {

    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("editorconfig-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    @discardableResult
    private func write(_ body: String, at relativeDir: String) throws -> URL {
        let dir = relativeDir.isEmpty ? scratch! : scratch.appendingPathComponent(relativeDir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(".editorconfig")
        try body.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Globs

    func testGlobMatching() {
        XCTAssertTrue(EditorConfig.matches(pattern: "*", path: "a.swift"))
        XCTAssertTrue(EditorConfig.matches(pattern: "*.swift", path: "a.swift"))
        XCTAssertTrue(EditorConfig.matches(pattern: "*.swift", path: "Sources/Deep/a.swift"),
                      "a pattern with no slash matches the NAME at any depth")
        XCTAssertFalse(EditorConfig.matches(pattern: "*.swift", path: "a.js"))
        XCTAssertTrue(EditorConfig.matches(pattern: "{*.yml,*.yaml}", path: "ci.yaml"))
        XCTAssertFalse(EditorConfig.matches(pattern: "{*.yml,*.yaml}", path: "ci.json"))
        XCTAssertTrue(EditorConfig.matches(pattern: "Sources/**/*.swift", path: "Sources/A/B/c.swift"))
        XCTAssertFalse(EditorConfig.matches(pattern: "Sources/*.swift", path: "Sources/A/c.swift"),
                       "a single star does not cross a path separator")
        XCTAssertTrue(EditorConfig.matches(pattern: "file?.txt", path: "file1.txt"))
        XCTAssertTrue(EditorConfig.matches(pattern: "*.[ch]", path: "main.c"))
    }

    // MARK: - Resolution against real files

    func testIndentStyleAndSizeApplyToMatchingFiles() throws {
        try write("""
        root = true

        [*]
        indent_style = space
        indent_size = 4

        [*.rb]
        indent_size = 2
        """, at: "")

        let swift = EditorConfig.settings(for: scratch.appendingPathComponent("a.swift"))
        XCTAssertEqual(swift.useSpaces, true)
        XCTAssertEqual(swift.indentWidth, 4)

        // Later sections override earlier ones for the files they match.
        let ruby = EditorConfig.settings(for: scratch.appendingPathComponent("a.rb"))
        XCTAssertEqual(ruby.indentWidth, 2)
        XCTAssertEqual(ruby.useSpaces, true, "the [*] section still supplies what [*.rb] omits")
    }

    func testTabsAreReportedAsTabs() throws {
        try write("""
        root = true
        [*.go]
        indent_style = tab
        tab_width = 8
        """, at: "")
        let go = EditorConfig.settings(for: scratch.appendingPathComponent("main.go"))
        XCTAssertEqual(go.useSpaces, false)
        XCTAssertEqual(go.tabWidth, 8)
        XCTAssertEqual(go.indentWidth, 8, "indent_size absent falls back to tab_width")
    }

    func testNearestFileWins() throws {
        try write("""
        root = true
        [*]
        indent_size = 4
        indent_style = space
        """, at: "")
        try write("""
        [*]
        indent_size = 2
        """, at: "web")

        let nested = EditorConfig.settings(for: scratch.appendingPathComponent("web/app.js"))
        XCTAssertEqual(nested.indentWidth, 2, "the nearer file wins")
        XCTAssertEqual(nested.useSpaces, true, "and the further one still fills what it left unsaid")

        let top = EditorConfig.settings(for: scratch.appendingPathComponent("app.js"))
        XCTAssertEqual(top.indentWidth, 4, "a file in a subdirectory does not affect its parent")
    }

    func testRootTrueStopsTheWalk() throws {
        try write("""
        [*]
        indent_size = 8
        """, at: "")
        try write("""
        root = true
        [*]
        indent_style = space
        """, at: "inner")

        let resolved = EditorConfig.settings(for: scratch.appendingPathComponent("inner/a.swift"))
        XCTAssertEqual(resolved.useSpaces, true)
        XCTAssertNil(resolved.indentWidth, "root = true stops the walk before the outer file")
    }

    func testSilenceIsNotADefault() throws {
        try write("""
        root = true
        [*.md]
        indent_size = 2
        """, at: "")
        let swift = EditorConfig.settings(for: scratch.appendingPathComponent("a.swift"))
        XCTAssertTrue(swift.isEmpty, "a file nothing matched must report nothing, not a default")
    }

    func testCommentsAndBlankLinesAreIgnored() throws {
        try write("""
        # a comment
        root = true

        ; another comment
        [*]
        indent_style = space   # an inline comment, which the spec allows after a value
        indent_size = 3 ; and the other comment character
        """, at: "")
        let resolved = EditorConfig.settings(for: scratch.appendingPathComponent("a.txt"))
        XCTAssertEqual(resolved.indentWidth, 3)
        XCTAssertEqual(resolved.useSpaces, true,
                       "an inline comment must not become part of the value")
    }

    func testSaveBehaviourKeys() throws {
        try write("""
        root = true
        [*]
        trim_trailing_whitespace = true
        insert_final_newline = false
        """, at: "")
        let resolved = EditorConfig.settings(for: scratch.appendingPathComponent("a.txt"))
        XCTAssertEqual(resolved.trimTrailingWhitespace, true)
        XCTAssertEqual(resolved.insertFinalNewline, false)
    }

    func testNoEditorConfigAnywhereIsEmptyNotACrash() {
        let resolved = EditorConfig.settings(for: scratch.appendingPathComponent("lonely.swift"))
        XCTAssertTrue(resolved.isEmpty)
    }

    // MARK: - Logic review, 18 Sep 2026

    func testACRLFFileIsReadLikeAnLFOne() throws {
        // An `.editorconfig` authored on Windows ends every line in CRLF. In Swift `"\r\n"` is ONE
        // Character, so a `split(separator: "\n")` never divided the file into lines: no section
        // header was ever seen, the whole file was silently ignored and the editor fell back to
        // its own preference.
        try write("root = true\r\n\r\n[*]\r\nindent_style = space\r\nindent_size = 3\r\n", at: "")
        let resolved = EditorConfig.settings(for: scratch.appendingPathComponent("a.swift"))
        XCTAssertEqual(resolved.useSpaces, true)
        XCTAssertEqual(resolved.indentWidth, 3)
    }

    func testDoubleStarBetweenSlashesMatchesZeroDirectoriesToo() {
        // Both reference cores (editorconfig-core-c `ec_glob.c`, editorconfig-core-py
        // `fnmatch.py`) translate `/**/` to "a slash, or a slash, anything, a slash", so
        // `Sources/**/*.swift` covers `Sources/c.swift` and `**/x` covers a top-level `x`.
        XCTAssertTrue(EditorConfig.matches(pattern: "Sources/**/*.swift", path: "Sources/c.swift"))
        XCTAssertTrue(EditorConfig.matches(pattern: "Sources/**/*.swift", path: "Sources/A/B/c.swift"))
        XCTAssertTrue(EditorConfig.matches(pattern: "**/c.swift", path: "c.swift"), "a leading **/ matches the top level")
        XCTAssertTrue(EditorConfig.matches(pattern: "**/c.swift", path: "A/c.swift"))
        XCTAssertFalse(EditorConfig.matches(pattern: "Sources/**/*.swift", path: "Other/c.swift"))
        XCTAssertFalse(EditorConfig.matches(pattern: "Sources/*.swift", path: "Sources/A/c.swift"),
                       "a single star still stops at a slash")
    }
}
