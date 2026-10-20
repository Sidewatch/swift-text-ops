//
//  NSString+LineWalk.swift
//  TextOps
//
//  Walking the whole lines inside a block, by NSString's own line breaks.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

extension NSString {
    /// Calls `body` with each whole line (content and break) inside `block`, in order. Lines are
    /// `lineRange(for:)`'s, so every break kind — LF, CRLF, a lone CR, NEL, LS, PS — ends one.
    func forEachLine(of block: NSRange, _ body: (NSRange) -> Void) {
        var at = block.location
        while at < NSMaxRange(block) {
            let line = lineRange(for: NSRange(location: at, length: 0))
            body(line)
            at = NSMaxRange(line)
        }
    }
}
