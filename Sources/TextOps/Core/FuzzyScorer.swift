//
//  FuzzyScorer.swift
//  TextOps
//
//  VS Code's fuzzy scorer (src/vs/base/common/fuzzyScorer.ts), ported: scores, match
//  positions, item scoring over label/description/path, and the comparator.
//
//  Created by David Sherlock on 9/20/26.
//

import Foundation

/// A half-open UTF-16 range of a match inside a label or a description.
public struct FuzzyMatchRange: Equatable, Sendable {
    public let start: Int
    public let end: Int
    public init(start: Int, end: Int) { self.start = start; self.end = end }
}

/// One space-separated piece of a query, normalized the way the scorer wants it.
public struct FuzzyQueryPiece: Equatable, Sendable {
    public let original: String
    public let originalLowercase: String
    /// Backslashes turned into the platform separator, so `a\b` finds `a/b`.
    public let pathNormalized: String
    /// `pathNormalized` minus wildcards (`*`), ellipses, whitespace, quotes and a trailing `#`.
    public let normalized: String
    public let normalizedLowercase: String
    /// The piece was quoted: only a contiguous match counts.
    public let expectContiguousMatch: Bool
}

/// A prepared query (VS Code's `prepareQuery`): the whole, plus its space-separated pieces
/// when there is more than one, each scored on its own and summed.
public struct FuzzyQuery: Equatable, Sendable {
    public let original: String
    public let originalLowercase: String
    public let pathNormalized: String
    public let normalized: String
    public let normalizedLowercase: String
    public let expectContiguousMatch: Bool
    public let pieces: [FuzzyQueryPiece]?
    public let containsPathSeparator: Bool

    public init(_ original: String) {
        let (pathNormalized, normalized, normalizedLowercase) = Self.normalize(original)
        self.original = original
        self.originalLowercase = original.lowercased()
        self.pathNormalized = pathNormalized
        self.normalized = normalized
        self.normalizedLowercase = normalizedLowercase
        self.containsPathSeparator = pathNormalized.contains("/")
        self.expectContiguousMatch = Self.expectsExactMatch(original)
        let split = original.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        if split.count > 1 {
            var values: [FuzzyQueryPiece] = []
            for piece in split {
                let (pn, n, nl) = Self.normalize(piece)
                guard !n.isEmpty else { continue }
                values.append(FuzzyQueryPiece(original: piece, originalLowercase: piece.lowercased(), pathNormalized: pn,
                                              normalized: n, normalizedLowercase: nl, expectContiguousMatch: Self.expectsExactMatch(piece)))
            }
            pieces = values.isEmpty ? nil : values
        } else {
            pieces = nil
        }
    }

    /// The query as a single piece — what a one-piece query scores by.
    public var piece: FuzzyQueryPiece {
        FuzzyQueryPiece(original: original, originalLowercase: originalLowercase, pathNormalized: pathNormalized,
                        normalized: normalized, normalizedLowercase: normalizedLowercase, expectContiguousMatch: expectContiguousMatch)
    }

    private static func expectsExactMatch(_ s: String) -> Bool { s.hasPrefix("\"") && s.hasSuffix("\"") }

    private static func normalize(_ original: String) -> (String, String, String) {
        let pathNormalized = original.replacingOccurrences(of: "\\", with: "/")
        var scalars: [Character] = []
        for ch in pathNormalized where ch != "*" && ch != "…" && ch != "\"" && !ch.isWhitespace { scalars.append(ch) }
        var normalized = String(scalars)
        if normalized.count > 1, normalized.hasSuffix("#") { normalized.removeLast() }
        return (pathNormalized, normalized, normalized.lowercased())
    }
}

/// VS Code's fuzzy scorer. Every position and range is in UTF-16 units, the coordinate an
/// `NSAttributedString` highlight wants. The character rules, in `charScore`: +1 for a match,
/// +1 more for the same case, +8 at the start of the target, +5 after a path separator, +4
/// after another separator, +2 for an upper-case letter starting a new run, and a rising bonus
/// for every consecutive matched character. Non-contiguous matching can be switched off (a
/// quoted query), and then the query must appear whole.
public enum FuzzyScorer {
    public static let pathIdentityScore = 1 << 18
    public static let labelPrefixScoreThreshold = 1 << 17
    public static let labelScoreThreshold = 1 << 16

    /// The score an item got, and where in its label and description the query matched.
    public struct ItemScore: Equatable, Sendable {
        public var score: Int
        public var labelMatch: [FuzzyMatchRange]?
        public var descriptionMatch: [FuzzyMatchRange]?
        public init(score: Int, labelMatch: [FuzzyMatchRange]? = nil, descriptionMatch: [FuzzyMatchRange]? = nil) {
            self.score = score; self.labelMatch = labelMatch; self.descriptionMatch = descriptionMatch
        }
        public static let none = ItemScore(score: 0)
    }

    /// What an item is scored on: a label (a file's name), an optional description (its
    /// folder) and an optional path (the whole thing, for the identity match).
    public struct Item: Equatable, Sendable {
        public let label: String
        public let description: String?
        public let path: String?
        public init(label: String, description: String? = nil, path: String? = nil) {
            self.label = label; self.description = description; self.path = path
        }
    }

    // MARK: - Raw scoring

    /// Scores `query` against `target`. Zero is no match; positions are the UTF-16 offsets of
    /// the matched characters, one per query character.
    public static func score(_ target: String, query: String, queryLower: String, allowNonContiguousMatches: Bool) -> (score: Int, positions: [Int]) {
        guard !target.isEmpty, !query.isEmpty else { return (0, []) }
        let t = Array(target.utf16)
        let q = Array(query.utf16)
        guard t.count >= q.count else { return (0, []) }
        let tl = lowerUnits(t)
        let qlCandidate = Array(queryLower.utf16)
        let ql = qlCandidate.count == q.count ? qlCandidate : lowerUnits(q)
        return doScore(q, ql, t, tl, allowNonContiguousMatches)
    }

    private static func doScore(_ q: [UInt16], _ ql: [UInt16], _ t: [UInt16], _ tl: [UInt16], _ allowNonContiguous: Bool) -> (Int, [Int]) {
        let qn = q.count, tn = t.count
        var scores = [Int](repeating: 0, count: qn * tn)
        var matches = [Int](repeating: 0, count: qn * tn)
        for qi in 0..<qn {
            let rowOffset = qi * tn
            let prevRowOffset = rowOffset - tn
            let qiGtZero = qi > 0
            for ti in 0..<tn {
                let tiGtZero = ti > 0
                let current = rowOffset + ti
                let left = current - 1
                let diag = prevRowOffset + ti - 1
                let leftScore = tiGtZero ? scores[left] : 0
                let diagScore = (qiGtZero && tiGtZero) ? scores[diag] : 0
                let seqLen = (qiGtZero && tiGtZero) ? matches[diag] : 0
                let s: Int
                if diagScore == 0 && qiGtZero { s = 0 }
                else { s = charScore(q[qi], ql[qi], t, tl, ti, seqLen) }
                let valid = s != 0 && diagScore + s >= leftScore
                if valid && (allowNonContiguous || qiGtZero || startsWith(tl, ql, at: ti)) {
                    matches[current] = seqLen + 1
                    scores[current] = diagScore + s
                } else {
                    matches[current] = 0
                    scores[current] = leftScore
                }
            }
        }
        var positions: [Int] = []
        var qi = qn - 1, ti = tn - 1
        while qi >= 0 && ti >= 0 {
            let current = qi * tn + ti
            if matches[current] == 0 { ti -= 1 }
            else { positions.append(ti); qi -= 1; ti -= 1 }
        }
        return (scores[qn * tn - 1], positions.reversed())
    }

    private static func charScore(_ qc: UInt16, _ qlc: UInt16, _ t: [UInt16], _ tl: [UInt16], _ ti: Int, _ seqLen: Int) -> Int {
        guard considerEqual(qlc, tl[ti]) else { return 0 }
        var s = 1
        if seqLen > 0 { s += min(seqLen, 3) * 6 + max(0, seqLen - 3) * 3 }
        if qc == t[ti] { s += 1 }
        if ti == 0 { s += 8 }
        else {
            let sep = separatorBonus(t[ti - 1])
            if sep > 0 { s += sep }
            else if isUpper(t[ti]) && seqLen == 0 { s += 2 }
        }
        return s
    }

    private static func considerEqual(_ a: UInt16, _ b: UInt16) -> Bool {
        if a == b { return true }
        if a == 47 || a == 92 { return b == 47 || b == 92 }   // "/" and "\" are one separator
        return false
    }

    private static func separatorBonus(_ c: UInt16) -> Int {
        switch c {
        case 47, 92: return 5                                  // / \  — prefer path separators…
        case 95, 45, 46, 32, 39, 34, 58: return 4             // _ - . space ' " :  …over other separators
        default: return 0
        }
    }

    private static func isUpper(_ c: UInt16) -> Bool { c >= 65 && c <= 90 }

    private static func startsWith(_ t: [UInt16], _ q: [UInt16], at index: Int) -> Bool {
        guard index + q.count <= t.count else { return false }
        for i in 0..<q.count where t[index + i] != q[i] { return false }
        return true
    }

    /// Lowercases per UTF-16 unit: ASCII by arithmetic, anything else through the scalar's own
    /// lowercase when that is a single unit — so the array stays aligned with the original.
    static func lowerUnits(_ units: [UInt16]) -> [UInt16] {
        units.map { u in
            if u >= 65 && u <= 90 { return u + 32 }
            if u < 128 { return u }
            guard let scalar = Unicode.Scalar(u) else { return u }
            let lowered = String(Character(scalar)).lowercased().utf16
            return lowered.count == 1 ? lowered.first! : u
        }
    }

    // MARK: - Item scoring

    /// Scores an item: the path itself beats everything; then the label (a prefix match
    /// higher still), then label and description together as one path-like string.
    public static func scoreItem(_ item: Item, query: FuzzyQuery, allowNonContiguousMatches: Bool) -> ItemScore {
        guard !query.normalized.isEmpty, !item.label.isEmpty else { return .none }
        let preferLabel = item.path == nil || !query.containsPathSeparator
        if let path = item.path, query.pathNormalized.caseInsensitiveCompare(path) == .orderedSame {
            return ItemScore(score: pathIdentityScore,
                             labelMatch: [FuzzyMatchRange(start: 0, end: item.label.utf16.count)],
                             descriptionMatch: item.description.map { [FuzzyMatchRange(start: 0, end: $0.utf16.count)] })
        }
        if let pieces = query.pieces, pieces.count > 1 {
            var total = 0
            var labelMatches: [FuzzyMatchRange] = [], descriptionMatches: [FuzzyMatchRange] = []
            for piece in pieces {
                let r = scoreItemSingle(item, piece: piece, preferLabel: preferLabel, allowNonContiguousMatches: allowNonContiguousMatches)
                if r.score == 0 { return .none }
                total += r.score
                labelMatches += r.labelMatch ?? []
                descriptionMatches += r.descriptionMatch ?? []
            }
            return ItemScore(score: total, labelMatch: normalize(labelMatches), descriptionMatch: normalize(descriptionMatches))
        }
        return scoreItemSingle(item, piece: query.piece, preferLabel: preferLabel, allowNonContiguousMatches: allowNonContiguousMatches)
    }

    private static func scoreItemSingle(_ item: Item, piece: FuzzyQueryPiece, preferLabel: Bool, allowNonContiguousMatches: Bool) -> ItemScore {
        let allow = allowNonContiguousMatches && !piece.expectContiguousMatch
        if preferLabel || item.description == nil {
            let (labelScore, positions) = score(item.label, query: piece.normalized, queryLower: piece.normalizedLowercase, allowNonContiguousMatches: allow)
            if labelScore > 0 {
                let prefix = prefixMatch(piece.normalized, in: item.label)
                var base: Int
                if let prefix {
                    base = labelPrefixScoreThreshold
                    base += Int((Double(piece.normalized.utf16.count) / Double(item.label.utf16.count) * 100).rounded())
                    return ItemScore(score: base + labelScore, labelMatch: prefix)
                }
                base = labelScoreThreshold
                return ItemScore(score: base + labelScore, labelMatch: ranges(from: positions))
            }
        }
        if let description = item.description {
            let descriptionPrefix = item.path != nil ? description + "/" : description
            let prefixLength = descriptionPrefix.utf16.count
            let (s, positions) = score(descriptionPrefix + item.label, query: piece.normalized, queryLower: piece.normalizedLowercase, allowNonContiguousMatches: allow)
            if s > 0 {
                var labelMatch: [FuzzyMatchRange] = [], descriptionMatch: [FuzzyMatchRange] = []
                for h in ranges(from: positions) {
                    if h.start < prefixLength && h.end > prefixLength {
                        labelMatch.append(FuzzyMatchRange(start: 0, end: h.end - prefixLength))
                        descriptionMatch.append(FuzzyMatchRange(start: h.start, end: prefixLength))
                    } else if h.start >= prefixLength {
                        labelMatch.append(FuzzyMatchRange(start: h.start - prefixLength, end: h.end - prefixLength))
                    } else {
                        descriptionMatch.append(h)
                    }
                }
                return ItemScore(score: s, labelMatch: labelMatch, descriptionMatch: descriptionMatch)
            }
        }
        return .none
    }

    /// Case-insensitive prefix: the range `[0, query)` when `label` starts with `query`.
    static func prefixMatch(_ query: String, in label: String) -> [FuzzyMatchRange]? {
        let qn = query.utf16.count
        guard label.utf16.count >= qn, label.lowercased().hasPrefix(query.lowercased()) else { return nil }
        return qn > 0 ? [FuzzyMatchRange(start: 0, end: qn)] : []
    }

    /// Consecutive positions become one range.
    public static func ranges(from positions: [Int]) -> [FuzzyMatchRange] {
        var out: [FuzzyMatchRange] = []
        for p in positions {
            if let last = out.last, last.end == p { out[out.count - 1] = FuzzyMatchRange(start: last.start, end: p + 1) }
            else { out.append(FuzzyMatchRange(start: p, end: p + 1)) }
        }
        return out
    }

    private static func normalize(_ matches: [FuzzyMatchRange]) -> [FuzzyMatchRange] {
        var out: [FuzzyMatchRange] = []
        for m in matches.sorted(by: { $0.start < $1.start }) {
            if let last = out.last, m.start <= last.end {
                out[out.count - 1] = FuzzyMatchRange(start: last.start, end: max(last.end, m.end))
            } else {
                out.append(m)
            }
        }
        return out
    }

    // MARK: - Comparing

    /// Orders two scored items (VS Code's `compareItemsByFuzzyScore`): an identity match first;
    /// among label matches the higher score, then the tighter match, then the shorter label;
    /// then score; then a label match over a description-only one; then the shorter distance
    /// between first and last hit; then `fallback`. Score each item ONCE and pass the scores —
    /// a comparator that re-scores runs the scorer O(n log n) times.
    public static func compare(_ a: Item, _ scoreA: ItemScore, _ b: Item, _ scoreB: ItemScore, query: FuzzyQuery) -> ComparisonResult {
        let sa = scoreA.score, sb = scoreB.score
        if sa == pathIdentityScore || sb == pathIdentityScore {
            if sa != sb { return sa == pathIdentityScore ? .orderedAscending : .orderedDescending }
        }
        if sa > labelScoreThreshold || sb > labelScoreThreshold {
            if sa != sb { return sa > sb ? .orderedAscending : .orderedDescending }
            if sa < labelPrefixScoreThreshold && sb < labelPrefixScoreThreshold {
                let byLength = compareByMatchLength(scoreA.labelMatch, scoreB.labelMatch)
                if byLength != .orderedSame { return byLength }
            }
            let la = a.label.utf16.count, lb = b.label.utf16.count
            if la != lb { return la < lb ? .orderedAscending : .orderedDescending }
        }
        if sa != sb { return sa > sb ? .orderedAscending : .orderedDescending }
        let aHasLabel = !(scoreA.labelMatch ?? []).isEmpty, bHasLabel = !(scoreB.labelMatch ?? []).isEmpty
        if aHasLabel && !bHasLabel { return .orderedAscending }
        if bHasLabel && !aHasLabel { return .orderedDescending }
        let da = matchDistance(a, scoreA), db = matchDistance(b, scoreB)
        if da != 0 && db != 0 && da != db { return db > da ? .orderedAscending : .orderedDescending }
        return fallback(a, b, query: query)
    }

    private static func matchDistance(_ item: Item, _ score: ItemScore) -> Int {
        var start = -1, end = -1
        if let d = score.descriptionMatch, !d.isEmpty { start = d[0].start }
        else if let l = score.labelMatch, !l.isEmpty { start = l[0].start }
        if let l = score.labelMatch, !l.isEmpty {
            end = l[l.count - 1].end
            if let d = score.descriptionMatch, !d.isEmpty, let desc = item.description { end += desc.utf16.count }
        } else if let d = score.descriptionMatch, !d.isEmpty {
            end = d[d.count - 1].end
        }
        return end - start
    }

    private static func compareByMatchLength(_ a: [FuzzyMatchRange]?, _ b: [FuzzyMatchRange]?) -> ComparisonResult {
        let ae = a ?? [], be = b ?? []
        if ae.isEmpty && be.isEmpty { return .orderedSame }
        if be.isEmpty { return .orderedAscending }
        if ae.isEmpty { return .orderedDescending }
        let la = ae[ae.count - 1].end - ae[0].start, lb = be[be.count - 1].end - be[0].start
        return la == lb ? .orderedSame : (lb < la ? .orderedDescending : .orderedAscending)
    }

    private static func fallback(_ a: Item, _ b: Item, query: FuzzyQuery) -> ComparisonResult {
        let la = a.label.utf16.count + (a.description?.utf16.count ?? 0)
        let lb = b.label.utf16.count + (b.description?.utf16.count ?? 0)
        if la != lb { return la < lb ? .orderedAscending : .orderedDescending }
        if let pa = a.path, let pb = b.path, pa.utf16.count != pb.utf16.count {
            return pa.utf16.count < pb.utf16.count ? .orderedAscending : .orderedDescending
        }
        if a.label != b.label { return compareAnything(a.label, b.label, lookFor: query.normalized) }
        if let da = a.description, let db = b.description, da != db { return compareAnything(da, db, lookFor: query.normalized) }
        if let pa = a.path, let pb = b.path, pa != pb { return compareAnything(pa, pb, lookFor: query.normalized) }
        return .orderedSame
    }

    /// VS Code's `compareAnything`: a prefix match first (the shorter of two), then a suffix
    /// match, then Finder-style file-name order, then plain locale order.
    static func compareAnything(_ one: String, _ other: String, lookFor: String) -> ComparisonResult {
        let a = one.lowercased(), b = other.lowercased(), q = lookFor.lowercased()
        let ap = a.hasPrefix(q), bp = b.hasPrefix(q)
        if ap != bp { return ap ? .orderedAscending : .orderedDescending }
        if ap && bp, a.count != b.count { return a.count < b.count ? .orderedAscending : .orderedDescending }
        let asuf = a.hasSuffix(q), bsuf = b.hasSuffix(q)
        if asuf != bsuf { return asuf ? .orderedAscending : .orderedDescending }
        let names = a.localizedStandardCompare(b)
        if names != .orderedSame { return names }
        if a != b { return a < b ? .orderedAscending : .orderedDescending }
        return a.localizedCompare(b)
    }
}
