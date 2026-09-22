# Audit log

Last full audit: **17 Sep 2026** — every source file covered by the MECHANICAL checks below (build warnings, tests,
dead-code and risk-pattern scans, docs drift); line-by-line logic review was targeted at the areas changed since
5 Sep 2026, not the whole tree. Nothing needs re-scanning unless it changed after that date. Add a dated line under *History* when you audit again, and keep the
*Known non-issues* list current so the next pass skips them.

## What a full audit checks

1. `swift build` warnings (none allowed except those listed under known non-issues) and `swift test` green.
2. Dead code: every `func`/type/property declared once and referenced nowhere in the app or the family
   (`grep -w` across `*.swift` AND non-Swift files — selectors and MCP names live in strings). Protocol
   requirements, `override`s, `@objc` actions and public API are NOT dead because Sidewatch does not call them.
3. Risky patterns: `Timer` without `invalidate`, `addObserver(forName:)` without `removeObserver`, `as!`, `try!`
   outside literal regexes, `fatalError` outside `init?(coder:)`, `print(` outside harnesses, TODO/FIXME left behind.
4. Docs drift: every name in CLAUDE.md's module map exists; AGENTS.md mirrors CLAUDE.md; README Usage matches the API.

## Result on 17 Sep 2026

- Build: clean. Tests: green.
- Nothing to fix in this package.

## Logic review — 18 Sep 2026 (every source and test file, line by line)

Fixed, each pinned by a test that fails against the old code:

- **A CRLF `.editorconfig` was ignored whole.** `EditorConfig.parse` split the file with
  `split(separator: "\n")`, and in Swift `"\r\n"` is ONE `Character`, so a file authored on Windows
  was never divided into lines at all: no section header was ever seen and the editor fell back to
  its own preference. (Measured on the way: `.whitespaces` does not contain CR either, so even a
  UTF-16 split would have left `true\r`.) Lines now split on `isNewline` and trim
  `.whitespacesAndNewlines`.
- **`/**/` required at least one directory.** `Sources/**/*.swift` did not cover `Sources/c.swift`
  and `**/x` did not cover a top-level `x`. Both reference cores (editorconfig-core-c `ec_glob.c`,
  editorconfig-core-py `fnmatch.py`) translate `/**/` to "a slash, or a slash, anything, a slash" and
  match a slash-bearing pattern joined onto the file's directory; `matches` now gives the subject and
  the pattern a leading slash and `regex(for:)` translates `/**/` the same way.

Reviewed and sound: `AutoClose` (every rule; a lone surrogate half read through `substring` becomes
U+FFFD, never a trap), `Identifier` (a non-BMP letter is two UTF-16 units and never an identifier unit
— an accepted limit of the offset API), `LineOps` (stable sort in both directions, numeric parking,
`leadingNumber`'s sign/decimal scan, `prune` on overlapping triggers), `TextLines` (terminator
counting, the held-back trailing newline, the caller-supplied ending), `TextStats`, `WholeWord`,
`EditorConfig`'s walk-up, `root`, nearest-wins and in-file section order.

## Known non-issues (do not "fix" these again)

- `EditorConfig` does not model `unset` (a nearer `indent_size = unset` cannot cancel a farther
  value — the settings type has no tri-state) nor the `{single}` / `{1..3}` brace forms, and
  `charset` / `end_of_line` are out of scope by design: nothing in the editor would act on them.

## History

- 17 Sep 2026 — full audit (app + all 20 libraries), Claude with David.
- 18 Sep 2026 — logic review (every source and test file, line by line), Claude with David.
- 22 Sep 2026 — `MarkdownFormatting` (from Sidewatch's Markdown bar, earlier that day) documented in the README and module map, which the first commit skipped; pipe tables added (`MarkdownFormatting+Tables`, `MarkdownTablesTests`).
