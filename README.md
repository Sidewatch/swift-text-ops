# Swift Text Ops

Dependency-free line transforms for a text editor — sort, dedupe, clean, join/split, re-case, transpose. Every operation is a pure `[String] -> [String]` function with no state, no I/O, and no mutation of its input, so they compose freely and test in microseconds. A companion `TextLines` bridges whole documents in and out, preserving the line terminator and trailing newline it found.

## Features

- 🔤 **Sorting** — `LineOps.sort(_:by:descending:caseInsensitive:)` over three keys: `.alphabetical`, `.numeric` (the first number appearing anywhere in the line), and `.length`
- 🧷 **Stable** — lines that compare equal keep their original relative order, in ascending *and* descending directions
- 🔢 **Sensible numeric sort** — reads signs and decimals, handles numbered lists (`"12. Widgets"` sorts as 12) and version-ish text (`"v2"` before `"v10"`); lines with no number keep their order and park at the end rather than drifting with the direction
- 🎲 **Reverse & shuffle** — `shuffle(_:using:)` takes a generator, so a shuffle can be seeded and asserted on
- 🧹 **Dedupe & clean** — `unique` (keeps the first occurrence, order preserved, optionally case-insensitive), `removeBlankLines`, `collapseBlankRuns` (runs of blanks down to one, paragraphs intact), `trimTrailingWhitespace` (leading indentation untouched)
- ✂️ **Join & split** — join every line into one on any separator; split every line on a delimiter into its own line
- 🅰️ **Case** — lower, upper, title
- 🔀 **Transpose** — rows to columns on any delimiter; ragged rows pad to rectangular, so it round-trips when applied twice
- 📄 **Round-trip safe** — `TextLines.transform(_:_:)` detects CRLF / CR / LF, hides the empty element a trailing newline produces so a sort can't drag it into the middle of the file, and restores both
- ⌨️ **Auto-close** — `AutoClose.decide(typed:in:at:allowQuotes:)`: the bracket/quote pairing decision an editor applies (pair, wrap, step over, pass through) and `deletesPair` for Backspace; pure, every rule pinned by tests
- ✍️ **Markdown formatting** — `MarkdownFormatting`: inline styles that toggle (`**`, `*`, `~~`, `` ` ``, from inside or around the selection, the word at the caret when there is none), block styles per line that toggle off when every line has them (headings 1–6 and Paragraph, bulleted / numbered / task lists, quote, fenced code), a link, `listContinuation` for the Return that continues or ends a list, and `context(in:selection:)` for a bar that shows the caret's styles; every call returns one `Edit` (range, replacement, selection) for one undo step
- 📊 **Pipe tables** — `MarkdownFormatting.table(in:selection:)` reads the table at the caret as cells with its alignments; `table(.format, …)` lays it out aligned (colons kept, cells padded per column), `.insertRowAbove/Below`, `.insertColumnBefore/After`, `.deleteRow`, `.deleteColumn` edit it around the caret's cell; `insertTable(in:selection:columns:rows:)` starts one on its own paragraph with "Column 1" selected; `tables(in:)` lists every table in order and `table(_:settingCell:column:to:in:)` sets one cell of the nth — what a cell edited in a rendered preview writes back
- 🧭 **`.editorconfig`** — `EditorConfig.settings(for:)` resolves `indent_style`, `indent_size`, `tab_width`, `trim_trailing_whitespace` and `insert_final_newline` for a file: walks up to `root = true`, nearest file wins, sections apply in order, globs read the way the reference cores read them (`*`, `**`, `/**/`, `?`, `[…]`, `{a,b}`), CRLF files included; every field is optional, so silence is never a default
- 🪶 **Zero dependencies** — Foundation only
- 🍎 **Cross-platform** — iOS, macOS, tvOS, watchOS, visionOS

## Requirements

- macOS 14+ (Foundation only; other Apple platforms at SwiftPM's default minimums)
- Swift 6.2+ (Swift 6 language mode)

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/Sidewatch/swift-text-ops.git", from: "0.1.0")
]
```

## Usage

```swift
import TextOps

// Operate on lines directly.
LineOps.sort(["banana", "Apple", "cherry"], caseInsensitive: true)
// ["Apple", "banana", "cherry"]

LineOps.sort(["item 10", "item 9", "item 100"], by: .numeric)
// ["item 9", "item 10", "item 100"]

LineOps.unique(["b", "a", "b", "c", "a"])
// ["b", "a", "c"]        — first occurrence wins, order preserved

LineOps.collapseBlankRuns(["a", "", "", "", "b"])
// ["a", "", "b"]

LineOps.transpose(["a\tb\tc", "d\te\tf"])
// ["a\td", "b\te", "c\tf"]
```

Or transform a whole document — the terminator and trailing newline survive:

```swift
// CRLF in, CRLF out; the trailing newline stays at the end instead of sorting to the top.
TextLines.transform("b\r\na\r\n") { LineOps.sort($0) }
// "a\r\nb\r\n"

// Compose freely.
TextLines.transform(source) { lines in
    LineOps.sort(LineOps.unique(LineOps.trimTrailingWhitespace(lines)))
}
```

### Markdown

```swift
// One undoable edit per call: the range to replace, the text, and where the selection lands.
let e = MarkdownFormatting.toggle(.bold, in: "make it bold", selection: NSRange(location: 8, length: 4))
// e.replacement == "**bold**", e.selection == (10, 4)

MarkdownFormatting.context(in: "## Title", selection: NSRange(location: 3, length: 0)).block   // .heading(2)

// The table at the caret, formatted; a column after the caret's; a new table.
MarkdownFormatting.table(.format, in: text, selection: caret)
MarkdownFormatting.table(.insertColumnAfter, in: text, selection: caret)   // nil outside a table
MarkdownFormatting.insertTable(in: text, selection: caret, columns: 3, rows: 2)
```

## For agents

Read `CONTRIBUTING.md` first: the folder layout and the PR rules. `swift test` is the whole
check, and a new test must fail before the change it covers. `CLAUDE.md` / `AGENTS.md` carry a
module map.

## License

MIT © 2026 David Sherlock (ArrayPress)
