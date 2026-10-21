# Swift Text Ops

Dependency-free line transforms for a text editor — sort, dedupe, clean, join/split, re-case, transpose. Every operation is a pure `[String] -> [String]` function with no state, no I/O, and no mutation of its input, so they compose freely and test in microseconds. A companion `TextLines` bridges whole documents in and out, preserving the line terminator and trailing newline it found.

- Module `TextOps` in `Sources/TextOps`; tests in `Tests`; `swift test` is the whole check.
- Swift 6 language mode, tools 6.2, macOS 14+, no dependencies unless the README says so.
- Part of the Sidewatch package family; every package follows the same layout and PR rules.

## Module map

- `Core/` — the engine: AutoClose, BracketMatch (the bracket at the caret and its partner by nesting count, a symmetric cap), CommentToggle (line and block comments; a block unwraps only exactly one comment), FoldPlan (runs of lines and unchanged stretches as `Fold`s; line 1 never hidden), LineStartIndex (line starts with O(log n) lookups, SPLICED through edits — the splice is a predicate, fuzzed against a rescan; the hot path, keep it allocation-light), MultiCaret (merge, caret positions, whole-character Backspace / Delete), ReturnIndent, TextSearch (plain and regex find, never a zero-width match; Replace templates; the caret after Replace All), TrailingWhitespace (trim-on-save, breaks untouched), LineEdits (duplicate / move / delete / indent / unindent as one `TextEdit`, every break read through `LineTerminator` so CRLF, CR and Unicode separators behave like LF), LineOps, TextLines, TextStats, WholeWord, Identifier (+ `isIdentifier` for a whole text), EditorConfig (`.editorconfig` resolution: walk-up, `root`, nearest-wins, the reference cores' globs), MarkdownFormatting (inline and block toggles, link, list continuation, `context`) and MarkdownFormatting+Tables (`table(in:selection:)`, `render`, `table(_:in:selection:)` edits, `insertTable`, `tables(in:)`, `table(_:settingCell:column:to:in:)`), LineNumberMap (git line ↔ editor line over the extra breaks: lone CR, NEL, LS, PS); FuzzyScorer (+Rank: `rank(_:query:order:item:)` — the scorer's own order, or score then input order, or score then the shorter label — and `matches`; `FuzzyQuery.narrows`, which knows a query with a space is not a longer one)
- `Models/` — TextEdit (a range, its replacement and the selection after; `MarkdownFormatting.Edit` is this type), Fold, LineRemap (a mark on a replaced line is dropped; review notes in swift-review-kit keep theirs on the edit's line on purpose)
- `Extensions/` — String+LineFeedCount (`\n` count over UTF-8 at `memchr` speed, for the open-time size check); NSString+TrailingBreak (`endsWithLineBreak`: a final break of ANY kind, so TextKit's empty last line is counted for a lone CR, NEL, LS or PS too)
- `Support/` — pure helpers: NSString+LineWalk (whole lines inside a block, by NSString's breaks), LineTerminator (the break ending a line, of any kind; the text's preferred one), LineBreakScan (one `memchr` pass over a text's UTF-16 units: the `\n` count and the git line of every extra break)
- `Enums/` — enums with no behaviour beyond their cases and labels: LetterCase, LineEnding, SortKey

## Rules

Read `CONTRIBUTING.md` for the folder layout and the pull-request rules.

@CONTRIBUTING.md

- **Auditing? Read `AUDIT.md` first** — what the last full audit checked and fixed, and the known non-issues to skip; extend it, do not redo it.
