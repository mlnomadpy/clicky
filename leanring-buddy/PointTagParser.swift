//
//  PointTagParser.swift
//  leanring-buddy
//
//  Parses the [POINT:x,y:label:screenN] / [POINT:none] tag that Claude
//  appends to the end of its voice-response text. The protocol is
//  documented in docs/adr/0010-text-based-point-protocol.md and the
//  system prompt itself lives in ClaudeSystemPrompts.swift.
//
//  Extracted from CompanionManager per docs/specs/15-feature-improvements.md
//  §1.3 so it can be unit-tested in isolation (see
//  docs/specs/14-testing-strategy.md).
//

import Foundation
import CoreGraphics

/// Result of parsing a `[POINT:...]` tag from Claude's response.
struct PointingParseResult {
    /// The response text with the `[POINT:...]` tag removed — this is what gets spoken.
    let spokenText: String
    /// The parsed pixel coordinate (in the screenshot's pixel space, top-left origin),
    /// or `nil` if Claude said `[POINT:none]` or no tag was found.
    let coordinate: CGPoint?
    /// Short label describing the element (e.g. `"run button"`), or `"none"` when Claude
    /// explicitly opted out of pointing.
    let elementLabel: String?
    /// Which screen the coordinate refers to (1-based), or `nil` to default to the cursor screen.
    let screenNumber: Int?
}

enum PointTagParser {

    /// Parses a `[POINT:x,y:label:screenN]` or `[POINT:none]` tag from the end of Claude's
    /// response. Returns the spoken text (tag removed) and the optional coordinate + label
    /// + screen number.
    ///
    /// The tag must appear at the very end of the response (trailing whitespace is allowed
    /// but no other text after it). Both `label` and `:screenN` are optional. The full
    /// grammar:
    ///
    ///   `[POINT:none]`
    ///   `[POINT:<x>,<y>]`
    ///   `[POINT:<x>,<y>:<label>]`
    ///   `[POINT:<x>,<y>:<label>:screen<N>]`
    static func parse(_ responseText: String) -> PointingParseResult {
        // Match [POINT:none] or [POINT:123,456:label] or [POINT:123,456:label:screen2]
        let pattern = #"\[POINT:(?:none|(\d+)\s*,\s*(\d+)(?::([^\]:\s][^\]:]*?))?(?::screen(\d+))?)\]\s*$"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: responseText, range: NSRange(responseText.startIndex..., in: responseText)) else {
            // No tag found at all
            return PointingParseResult(spokenText: responseText, coordinate: nil, elementLabel: nil, screenNumber: nil)
        }

        // Remove the tag from the spoken text
        let tagRange = Range(match.range, in: responseText)!
        let spokenText = String(responseText[..<tagRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if it's [POINT:none]
        guard match.numberOfRanges >= 3,
              let xRange = Range(match.range(at: 1), in: responseText),
              let yRange = Range(match.range(at: 2), in: responseText),
              let x = Double(responseText[xRange]),
              let y = Double(responseText[yRange]) else {
            return PointingParseResult(spokenText: spokenText, coordinate: nil, elementLabel: "none", screenNumber: nil)
        }

        var elementLabel: String? = nil
        if match.numberOfRanges >= 4, let labelRange = Range(match.range(at: 3), in: responseText) {
            elementLabel = String(responseText[labelRange]).trimmingCharacters(in: .whitespaces)
        }

        var screenNumber: Int? = nil
        if match.numberOfRanges >= 5, let screenRange = Range(match.range(at: 4), in: responseText) {
            screenNumber = Int(responseText[screenRange])
        }

        return PointingParseResult(
            spokenText: spokenText,
            coordinate: CGPoint(x: x, y: y),
            elementLabel: elementLabel,
            screenNumber: screenNumber
        )
    }
}
