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
- 🪶 **Zero dependencies** — Foundation only
- 🍎 **Cross-platform** — iOS, macOS, tvOS, watchOS, visionOS

## Requirements

- iOS 13.0+ / macOS 10.15+ / tvOS 13.0+ / watchOS 6.0+ / visionOS 1.0+
- Swift 5.9+

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/Sidewatch/swift-text-ops.git", from: "1.0.0")
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

## For agents

Read `CONTRIBUTING.md` first: the folder layout and the PR rules. `swift test` is the whole
check, and a new test must fail before the change it covers. `CLAUDE.md` / `AGENTS.md` carry a
module map.

## License

MIT © 2026 David Sherlock (ArrayPress)
