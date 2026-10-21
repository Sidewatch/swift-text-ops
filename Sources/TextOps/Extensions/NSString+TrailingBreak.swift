//
//  NSString+TrailingBreak.swift
//  TextOps
//
//  Whether a text ends in a line break of any kind — and so has TextKit's empty last line.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

public extension NSString {
    /// Whether the text ends in a line break of any kind — `\n`, `\r\n`, a lone `\r`, NEL, LS or PS. TextKit
    /// lays out an empty last line after any of them (its extra line fragment), so a gutter numbers one
    /// more line and a caret at the very end sits on it; testing for `\n` alone misses a file that ends in
    /// any other break.
    var endsWithLineBreak: Bool { LineTerminator.length(endingAt: length, in: self) > 0 }
}
