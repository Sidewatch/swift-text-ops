# Swift Text Ops

Dependency-free line transforms for a text editor — sort, dedupe, clean, join/split, re-case, transpose. Every operation is a pure `[String] -> [String]` function with no state, no I/O, and no mutation of its input, so they compose freely and test in microseconds. A companion `TextLines` bridges whole documents in and out, preserving the line terminator and trailing newline it found.

- Module `TextOps` in `Sources/TextOps`; tests in `Tests`; `swift test` is the whole check.
- Swift 6 language mode, tools 6.2, macOS 14+, no dependencies unless the README says so.
- Part of the Sidewatch package family; every package follows the same layout and PR rules.

## Module map

- `Core/` — the engine: LineOps, TextLines, TextStats, WholeWord
- `Enums/` — enums with no behaviour beyond their cases and labels: LetterCase, LineEnding, SortKey

## Rules

@CONTRIBUTING.md
