import Foundation

/// The auto-close decision for one typed character — pure, so an editor can pin every rule
/// without a text view. The rules are the ones that keep an auto-closer out of the way:
///  - an opener pairs only when what follows is nothing, whitespace or a closer
///    (`(` before `foo` must not become `()foo`);
///  - a closer typed onto the same closer steps over it, whoever put it there;
///  - a quote never pairs next to a word character (`don't`, `it's`, `"foo|bar`);
///  - quotes can be disabled wholesale (prose: apostrophes are punctuation, not delimiters);
///  - an opener over a selection wraps it;
///  - Backspace between an empty pair removes both.
public enum AutoClose {
    public enum Action: Equatable, Sendable {
        case insertPair(open: String, close: String)
        case wrap(open: String, close: String)
        case stepOver
        case passThrough
    }

    public static let brackets: [Character: Character] = ["(": ")", "[": "]", "{": "}"]
    public static let quotes: Set<Character> = ["\"", "'", "`"]

    /// What to do when `typed` lands at `range` (a caret, or a selection to wrap) in `text`.
    public static func decide(typed: String, in text: NSString, at range: NSRange, allowQuotes: Bool) -> Action {
        guard typed.count == 1, let ch = typed.first else { return .passThrough }
        let loc = min(range.location, text.length)
        let end = min(NSMaxRange(range), text.length)
        let prev: Character? = loc > 0 ? Character(text.substring(with: NSRange(location: loc - 1, length: 1))) : nil
        let next: Character? = end < text.length ? Character(text.substring(with: NSRange(location: end, length: 1))) : nil
        func isWord(_ c: Character?) -> Bool { c.map { $0.isLetter || $0.isNumber || $0 == "_" } ?? false }
        func opensBefore(_ c: Character?) -> Bool {
            guard let c else { return true }
            return c.isWhitespace || c.isNewline || ")]};,".contains(c)
        }
        if let close = brackets[ch] {
            if range.length > 0 { return .wrap(open: String(ch), close: String(close)) }
            return opensBefore(next) ? .insertPair(open: String(ch), close: String(close)) : .passThrough
        }
        if brackets.values.contains(ch) {
            return range.length == 0 && next == ch ? .stepOver : .passThrough
        }
        if allowQuotes, quotes.contains(ch) {
            if range.length > 0 { return .wrap(open: String(ch), close: String(ch)) }
            if next == ch { return .stepOver }
            if isWord(prev) || isWord(next) { return .passThrough }
            return opensBefore(next) ? .insertPair(open: String(ch), close: String(ch)) : .passThrough
        }
        return .passThrough
    }

    /// True when the caret sits between an empty pair this engine would have made, so a
    /// Backspace should remove both.
    public static func deletesPair(in text: NSString, at caret: Int) -> Bool {
        guard caret > 0, caret < text.length else { return false }
        let prev = Character(text.substring(with: NSRange(location: caret - 1, length: 1)))
        let next = Character(text.substring(with: NSRange(location: caret, length: 1)))
        if let close = brackets[prev] { return next == close }
        return quotes.contains(prev) && next == prev
    }
}
