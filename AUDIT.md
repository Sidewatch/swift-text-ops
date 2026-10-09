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

## Line numbers — 9 Oct 2026

Added, pinned by tests that fail without it:

- **`LineNumberMap`** (`Core/`, scanner in `Support/LineBreakScan`): git numbers lines by `\n`
  alone; TextKit and `NSString.lineRange` also break on a lone `\r`, U+0085, U+2028 and U+2029
  (measured: U+000B and U+000C are not breaks to `lineRange`, `\r\n` is one). Every such unit
  put the editor one line past git for the rest of the file. The map records the git line of
  each extra break and converts both ways by binary search; both directions are monotone,
  1-based and clamp past either end. `LineNumberMapTests` holds `NSString.getLineStart` as the
  oracle for every line of every sample in both directions (`assertAgreesWithTheOracle`), the
  worked example `a\u{2028}b\nc\nd` (git line 2 is editor line 3; editor line 2 is git line 1),
  lone CR (including one ending the text), every kind mixed with CRLF, a 400-line pseudo-random
  mix with the round trip, clamping, and the chunk boundary (a `\r` on a chunk's last unit sees
  the `\n` on the next chunk's first). Mutants: U+2028 dropped from the breaks (2,406 failures);
  no lookahead across the chunk boundary (4 failures in the boundary test); `>=` for `>` in
  `gitLine(forUnicodeLine:)` (235 failures).
- **Cost, measured in the debug build `swift test` runs:** 10,000,032 UTF-16 units (20 MB) of
  code-like text scan in 22 ms through a Swift-bridged `NSString` (`getCharacters` in 64K-unit
  chunks) and 17 ms through an `NSMutableString`; the scan is five `memchr` sweeps per chunk, in
  libc, after a plain per-unit loop measured 94–180 ms in debug and a fast-reject loop 34 ms.
  `testScanningTwentyMegabytesStaysWellUnder50ms` guards both at 50 ms and prints them. The
  pathological case, 500,000 lone-CR lines in 20 MB, is 65 ms in debug (per-hit array work;
  about 10 ms in release) and is guarded at 100 ms. Mutant: the plain loop in place of
  `memchr` — 180 ms bridged, 156 ms native, both guards fail.
- `CFStringGetCharactersPtr` hands out a direct pointer only for small CF-backed strings
  (measured: a 10-unit `NSMutableString` yes; a 4,000-unit one, an `NSBigMutableString` and a
  bridged Swift `String` no), so the chunked path is the one that runs on an editor's storage;
  `testTheDirectPointerPathAgreesWithTheChunkedPath` keeps the two in step.

## Known non-issues (do not "fix" these again)

- `EditorConfig` does not model `unset` (a nearer `indent_size = unset` cannot cancel a farther
  value — the settings type has no tri-state) nor the `{single}` / `{1..3}` brace forms, and
  `charset` / `end_of_line` are out of scope by design: nothing in the editor would act on them.

## History

- 17 Sep 2026 — full audit (app + all 20 libraries), Claude with David.
- 18 Sep 2026 — logic review (every source and test file, line by line), Claude with David.
- 22 Sep 2026 — `MarkdownFormatting` (from Sidewatch's Markdown bar, earlier that day) documented in the README and module map, which the first commit skipped; pipe tables added (`MarkdownFormatting+Tables`, `MarkdownTablesTests`).
- 22 Sep 2026 (later) — `tables(in:)` and `table(_:settingCell:column:to:in:)` for a rendered preview's cell edits.
- 9 Oct 2026 — `LineNumberMap` + `LineBreakScan` (git line ↔ editor line over lone CR / NEL / LS / PS), with the
  `NSString.getLineStart` oracle and the 20 MB guard (numbers above).
