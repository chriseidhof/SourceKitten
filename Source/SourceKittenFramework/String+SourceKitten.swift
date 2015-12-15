//
//  String+SourceKitten.swift
//  SourceKitten
//
//  Created by JP Simard on 2015-01-05.
//  Copyright (c) 2015 SourceKitten. All rights reserved.
//

import Foundation

public typealias Line = (index: Int, content: String)

private let whitespaceAndNewlineCharacterSet = NSCharacterSet.whitespaceAndNewlineCharacterSet()

private let commentLinePrefixCharacterSet: NSCharacterSet = {
  let characterSet = NSMutableCharacterSet.whitespaceAndNewlineCharacterSet()
  /**
   * For "wall of asterisk" comment blocks, such as this one.
   */
  characterSet.addCharactersInString("*")
  return characterSet
}()

private var keyByteOffsetCache = "ByteOffsetCache"

extension NSString {
    /**
    ByteOffsetCache caches pairs of byte offset and UTF8Index for referencing by UTF16 based location.
    */
    @objc private class ByteOffsetCache: NSObject {
        struct ByteOffsetIndexPair {
            let byteOffset: Int
            let index: String.UTF8Index
        }
        
        var cache = Dictionary<Int, ByteOffsetIndexPair>()
        let utf8View: String.UTF8View
        
        init(_ string: String) {
            self.utf8View = string.utf8
        }
        
        func byteOffsetFromLocation(location: Int, andIndex index: String.UTF8Index) -> Int {
            if let byteOffsetIndexPair = cache[location] {
                return byteOffsetIndexPair.byteOffset
            } else {
                let byteOffsetIndexPair: ByteOffsetIndexPair
                if let nearestLocation = cache.keys.filter({ $0 < location }).maxElement() {
                    let nearestByteOffsetIndexPair = cache[nearestLocation]!
                    let byteOffset = nearestByteOffsetIndexPair.byteOffset +
                        nearestByteOffsetIndexPair.index.distanceTo(index)
                    byteOffsetIndexPair = ByteOffsetIndexPair(byteOffset: byteOffset, index: index)
                } else {
                    let byteOffset = utf8View.startIndex.distanceTo(index)
                    byteOffsetIndexPair = ByteOffsetIndexPair(byteOffset: byteOffset, index: index)
                }
                cache[location] = byteOffsetIndexPair
                
                return byteOffsetIndexPair.byteOffset
            }
        }
    }
    
    /**
     ByteOffsetCache instance is stored to instance of NSString as associated object.
    */
    private var byteOffsetCache: ByteOffsetCache {
        if let cache = objc_getAssociatedObject(self, &keyByteOffsetCache) as? ByteOffsetCache {
            return cache
        } else {
            let cache = ByteOffsetCache(self as String)
            objc_setAssociatedObject(self, &keyByteOffsetCache, cache, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return cache
        }
    }
    
    public func lineAndCharacterForCharacterOffset(offset: Int) -> (line: Int, character: Int)? {
        let range = NSRange(location: offset, length: 0)
        var numberOfLines = 0, index = 0, lineRangeStart = 0, previousIndex = 0
        while index < length {
            numberOfLines++
            if index > range.location {
                break
            }
            lineRangeStart = numberOfLines
            previousIndex = index
            index = NSMaxRange(lineRangeForRange(NSRange(location: index, length: 1)))
        }
        return (lineRangeStart, range.location - previousIndex + 1)
    }

    /**
    Returns a copy of `self` with the trailing contiguous characters belonging to `characterSet`
    removed.

    - parameter characterSet: Character set to check for membership.
    */
    public func stringByTrimmingTrailingCharactersInSet(characterSet: NSCharacterSet) -> String {
        if length == 0 {
            return self as String
        }
        var charBuffer = [unichar](count: length, repeatedValue: 0)
        getCharacters(&charBuffer)
        for newLength in (1...length).reverse() {
            if !characterSet.characterIsMember(charBuffer[newLength - 1]) {
                return substringWithRange(NSRange(location: 0, length: newLength))
            }
        }
        return ""
    }

    /**
    Returns self represented as an absolute path.

    - parameter rootDirectory: Absolute parent path if not already an absolute path.
    */
    public func absolutePathRepresentation(rootDirectory: String = NSFileManager.defaultManager().currentDirectoryPath) -> String {
        if absolutePath {
            return self as String
        }
        return (NSString.pathWithComponents([rootDirectory, self as String]) as NSString).stringByStandardizingPath
    }

    /**
    Converts a range of byte offsets in `self` to an `NSRange` suitable for filtering `self` as an
    `NSString`.

    - parameter start: Starting byte offset.
    - parameter length: Length of bytes to include in range.

    - returns: An equivalent `NSRange`.
    */
    public func byteRangeToNSRange(start start: Int, length: Int) -> NSRange? {
        let string = self as String
        let startUTF8Index = string.utf8.startIndex.advancedBy(start)
        let endUTF8Index = startUTF8Index.advancedBy(length)
        
        let utf16View = string.utf16
        guard let startUTF16Index = startUTF8Index.samePositionIn(utf16View),
            let endUTF16Index = endUTF8Index.samePositionIn(utf16View) else {
                return nil
        }
        
        let location = utf16View.startIndex.distanceTo(startUTF16Index)
        let length = startUTF16Index.distanceTo(endUTF16Index)
        return NSRange(location: location, length: length)
    }

    /**
    Converts an `NSRange` suitable for filtering `self` as an
    `NSString` to a range of byte offsets in `self`.

    - parameter start: Starting character index in the string.
    - parameter length: Number of characters to include in range.

    - returns: An equivalent `NSRange`.
    */
    public func NSRangeToByteRange(start start: Int, length: Int) -> NSRange? {
        let string = self as String
        
        let utf16View = string.utf16
        let startUTF16Index = utf16View.startIndex.advancedBy(start)
        let endUTF16Index = startUTF16Index.advancedBy(length)
        
        let utf8View = string.utf8
        guard let startUTF8Index = startUTF16Index.samePositionIn(utf8View),
            let endUTF8Index = endUTF16Index.samePositionIn(utf8View) else {
                return nil
        }
        
        // Don't using `ByteOffsetCache` if string is short.
        // There are two reasons for:
        // 1. Avoid using associatedObject on NSTaggedPointerString (< 7 bytes) because that does
        //    not free associatedObject.
        // 2. Using cache is overkill for short string.
        let byteOffset: Int
        if utf16View.count > 50 {
            byteOffset = byteOffsetCache.byteOffsetFromLocation(start, andIndex: startUTF8Index)
        } else {
            byteOffset = utf8View.startIndex.distanceTo(startUTF8Index)
        }
        
        // `byteOffsetCache` will hit for below, but that will be calculated from startUTF8Index
        // in most case.
        let length = startUTF8Index.distanceTo(endUTF8Index)
        return NSRange(location: byteOffset, length: length)
    }

    /**
    Returns a substring with the provided byte range.

    - parameter start: Starting byte offset.
    - parameter length: Length of bytes to include in range.
    */
    public func substringWithByteRange(start start: Int, length: Int) -> String? {
        return byteRangeToNSRange(start: start, length: length).map(substringWithRange)
    }

    /**
    Returns a substring starting at the beginning of `start`'s line and ending at the end of `end`'s
    line. Returns `start`'s entire line if `end` is nil.

    - parameter start: Starting byte offset.
    - parameter length: Length of bytes to include in range.
    */
    public func substringLinesWithByteRange(start start: Int, length: Int) -> String? {
        return byteRangeToNSRange(start: start, length: length).map { range in
            var lineStart = 0, lineEnd = 0
            getLineStart(&lineStart, end: &lineEnd, contentsEnd: nil, forRange: range)
            return substringWithRange(NSRange(location: lineStart, length: lineEnd - lineStart))
        }
    }

    /**
    Returns line numbers containing starting and ending byte offsets.

    - parameter start: Starting byte offset.
    - parameter length: Length of bytes to include in range.
    */
    public func lineRangeWithByteRange(start start: Int, length: Int) -> (start: Int, end: Int)? {
        return byteRangeToNSRange(start: start, length: length).flatMap { range in
            var numberOfLines = 0, index = 0, lineRangeStart = 0
            while index < self.length {
                numberOfLines++
                if index <= range.location {
                    lineRangeStart = numberOfLines
                }
                index = NSMaxRange(lineRangeForRange(NSRange(location: index, length: 1)))
                if index > NSMaxRange(range) {
                    return (lineRangeStart, numberOfLines)
                }
            }
            return nil
        }
    }

    /**
    Returns an array of Lines for each line in the file.
    */
    public func lines() -> [Line] {
        var lines = [Line]()
        var lineIndex = 1
        enumerateLinesUsingBlock { line, _ in
            lines.append((lineIndex++, line))
        }
        return lines
    }

    /**
    Returns true if self is an Objective-C header file.
    */
    public func isObjectiveCHeaderFile() -> Bool {
        return ["h", "hpp", "hh"].contains(pathExtension)
    }

    /**
    Returns true if self is a Swift file.
    */
    public func isSwiftFile() -> Bool {
        return pathExtension == "swift"
    }

    /**
    Returns a substring from a start and end SourceLocation.
    */
    public func substringWithSourceRange(start: SourceLocation, end: SourceLocation) -> String? {
        return substringWithByteRange(start: Int(start.offset), length: Int(end.offset - start.offset))
    }
}

extension String {
    /// Returns the `#pragma mark`s in the string.
    /// Just the content; no leading dashes or leading `#pragma mark`.
    public func pragmaMarks(filename: String, excludeRanges: [NSRange], limitRange: NSRange?) -> [SourceDeclaration] {
        let regex = try! NSRegularExpression(pattern: "(#pragma\\smark|@name)[ -]*([^\\n]+)", options: []) // Safe to force try
        let range: NSRange
        if let limitRange = limitRange {
            range = NSRange(location: limitRange.location, length: min(utf16.count - limitRange.location, limitRange.length))
        } else {
            range = NSRange(location: 0, length: utf16.count)
        }
        let matches = regex.matchesInString(self, options: [], range: range)

        return matches.flatMap { match in
            let markRange = match.rangeAtIndex(2)
            for excludedRange in excludeRanges {
                if NSIntersectionRange(excludedRange, markRange).length > 0 {
                    return nil
                }
            }
            let markString = (self as NSString).substringWithRange(markRange)
                .stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceCharacterSet())
            if markString.isEmpty {
                return nil
            }
            guard let markByteRange = self.NSRangeToByteRange(start: markRange.location, length: markRange.length) else {
                return nil
            }
            let location = SourceLocation(file: filename,
                line: UInt32((self as NSString).lineRangeWithByteRange(start: markByteRange.location, length: 0)!.start),
                column: 1, offset: UInt32(markByteRange.location))
            return SourceDeclaration(type: .Mark, location: location, extent: (location, location), name: markString,
                usr: nil, declaration: nil, documentation: nil, commentBody: nil, children: [])
        }
    }

    /**
    Returns whether or not the `token` can be documented. Either because it is a
    `SyntaxKind.Identifier` or because it is a function treated as a `SyntaxKind.Keyword`:

    - `subscript`
    - `init`
    - `deinit`

    - parameter token: Token to process.
    */
    public func isTokenDocumentable(token: SyntaxToken) -> Bool {
        if token.type == SyntaxKind.Keyword.rawValue {
            let keywordFunctions = ["subscript", "init", "deinit"]
            return ((self as NSString).substringWithByteRange(start: token.offset, length: token.length))
                .map(keywordFunctions.contains) ?? false
        }
        return token.type == SyntaxKind.Identifier.rawValue
    }

    /**
    Find integer offsets of documented Swift tokens in self.

    - parameter syntaxMap: Syntax Map returned from SourceKit editor.open request.

    - returns: Array of documented token offsets.
    */
    public func documentedTokenOffsets(syntaxMap: SyntaxMap) -> [Int] {
        let documentableOffsets = syntaxMap.tokens.filter(isTokenDocumentable).map {
            $0.offset
        }

        let regex = try! NSRegularExpression(pattern: "(///.*\\n|\\*/\\n)", options: []) // Safe to force try
        let range = NSRange(location: 0, length: utf16.count)
        let matches = regex.matchesInString(self, options: [], range: range)

        return matches.flatMap { match in
            documentableOffsets.filter({ $0 >= match.range.location }).first
        }
    }

    /**
    Returns the body of the comment if the string is a comment.
    
    - parameter range: Range to restrict the search for a comment body.
    */
    public func commentBody(range: NSRange? = nil) -> String? {
        let nsString = self as NSString
        let patterns: [(pattern: String, options: NSRegularExpressionOptions)] = [
            ("^\\s*\\/\\*\\*\\s*(.*?)\\*\\/", [.AnchorsMatchLines, .DotMatchesLineSeparators]), // multi: ^\s*\/\*\*\s*(.*?)\*\/
            ("^\\s*\\/\\/\\/(.+)?",           .AnchorsMatchLines)                               // single: ^\s*\/\/\/(.+)?
        ]
        let range = range ?? NSRange(location: 0, length: nsString.length)
        for pattern in patterns {
            let regex = try! NSRegularExpression(pattern: pattern.pattern, options: pattern.options) // Safe to force try
            let matches = regex.matchesInString(self, options: [], range: range)
            let bodyParts = matches.flatMap { match -> [String] in
                let numberOfRanges = match.numberOfRanges
                if numberOfRanges < 1 {
                    return []
                }
                return (1..<numberOfRanges).map { rangeIndex in
                    let range = match.rangeAtIndex(rangeIndex)
                    if range.location == NSNotFound {
                        return "" // empty capture group, return empty string
                    }
                    var lineStart = 0
                    var lineEnd = nsString.length
                    guard let indexRange = self.byteRangeToNSRange(start: range.location, length: 0) else {
                        return "" // out of range, return empty string
                    }
                    nsString.getLineStart(&lineStart, end: &lineEnd, contentsEnd: nil, forRange: indexRange)
                    let leadingWhitespaceCountToAdd = nsString.substringWithRange(NSRange(location: lineStart, length: lineEnd - lineStart)).countOfLeadingCharactersInSet(whitespaceAndNewlineCharacterSet)
                    let leadingWhitespaceToAdd = String(count: leadingWhitespaceCountToAdd, repeatedValue: Character(" "))

                    let bodySubstring = nsString.substringWithRange(range)
                    if bodySubstring.containsString("@name") {
                        return "" // appledoc directive, return empty string
                    }
                    return leadingWhitespaceToAdd + bodySubstring
                }
            }
            if bodyParts.count > 0 {
                return bodyParts
                    .joinWithSeparator("\n")
                    .stringByTrimmingTrailingCharactersInSet(whitespaceAndNewlineCharacterSet)
                    .stringByRemovingCommonLeadingWhitespaceFromLines()
            }
        }
        return nil
    }

    /// Returns a copy of `self` with the leading whitespace common in each line removed.
    public func stringByRemovingCommonLeadingWhitespaceFromLines() -> String {
        var minLeadingCharacters = Int.max

        enumerateLines { line, _ in
            let lineLeadingWhitespace = line.countOfLeadingCharactersInSet(whitespaceAndNewlineCharacterSet)
            let lineLeadingCharacters = line.countOfLeadingCharactersInSet(commentLinePrefixCharacterSet)
            // Is this prefix smaller than our last and not entirely whitespace?
            if lineLeadingCharacters < minLeadingCharacters && lineLeadingWhitespace != line.characters.count {
                minLeadingCharacters = lineLeadingCharacters
            }
        }
        var lines = [String]()
        enumerateLines { line, _ in
            if line.characters.count >= minLeadingCharacters {
                lines.append(line[line.startIndex.advancedBy(minLeadingCharacters)..<line.endIndex])
            } else {
                lines.append(line)
            }
        }
        return lines.joinWithSeparator("\n")
    }

    /**
    Returns the number of contiguous characters at the start of `self` belonging to `characterSet`.
    
    - parameter characterSet: Character set to check for membership.
    */
    public func countOfLeadingCharactersInSet(characterSet: NSCharacterSet) -> Int {
        let utf16View = utf16
        var count = 0
        for char in utf16View {
            if !characterSet.characterIsMember(char) {
                break
            }
            count++
        }
        return count
    }

    /// Returns a copy of the string by trimming whitespace and the opening curly brace (`{`).
    internal func stringByTrimmingWhitespaceAndOpeningCurlyBrace() -> String? {
        let unwantedSet = whitespaceAndNewlineCharacterSet.mutableCopy() as! NSMutableCharacterSet
        unwantedSet.addCharactersInString("{")
        return stringByTrimmingCharactersInSet(unwantedSet)
    }
}
