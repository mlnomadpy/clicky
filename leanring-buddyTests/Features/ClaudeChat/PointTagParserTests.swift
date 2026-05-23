//
//  PointTagParserTests.swift
//  leanring-buddyTests
//
//  Tests for the [POINT:...] tag parser extracted from CompanionManager
//  in phase-0/extract-parsers. The parser is described in
//  docs/adr/0010-text-based-point-protocol.md and the example phrases
//  inside ClaudeSystemPrompts.companionVoiceResponse are the load-bearing
//  contract — these tests guard against drift.
//

import Testing
import CoreGraphics
@testable import leanring_buddy

struct PointTagParserTests {

    // MARK: - Happy paths from the system-prompt examples

    @Test func parsesBasicCoordinateAndLabel() async throws {
        let response = "you'll want to open the color inspector — it's right up in the top right area of the toolbar. click that and you'll get all the color wheels and curves. [POINT:1100,42:color inspector]"
        let result = PointTagParser.parse(response)

        #expect(result.coordinate == CGPoint(x: 1100, y: 42))
        #expect(result.elementLabel == "color inspector")
        #expect(result.screenNumber == nil)
        #expect(result.spokenText.hasSuffix("color wheels and curves."))
        #expect(!result.spokenText.contains("[POINT"))
    }

    @Test func parsesScreenNumberSuffix() async throws {
        let response = "that's over on your other monitor — see the terminal window? [POINT:400,300:terminal:screen2]"
        let result = PointTagParser.parse(response)

        #expect(result.coordinate == CGPoint(x: 400, y: 300))
        #expect(result.elementLabel == "terminal")
        #expect(result.screenNumber == 2)
    }

    @Test func parsesPointNoneAsNoCoordinate() async throws {
        let response = "html stands for hypertext markup language, it's basically the skeleton of every web page. curious how it connects to the css you're looking at? [POINT:none]"
        let result = PointTagParser.parse(response)

        #expect(result.coordinate == nil)
        #expect(result.elementLabel == "none")
        #expect(result.screenNumber == nil)
        #expect(result.spokenText.hasSuffix("you're looking at?"))
    }

    // MARK: - Edge cases

    @Test func responseWithoutTagReturnsUnchangedSpokenText() async throws {
        let response = "just answering normally with no pointing"
        let result = PointTagParser.parse(response)

        #expect(result.coordinate == nil)
        #expect(result.elementLabel == nil)
        #expect(result.screenNumber == nil)
        #expect(result.spokenText == "just answering normally with no pointing")
    }

    @Test func coordinatesWithoutLabelStillParse() async throws {
        let response = "look there. [POINT:50,75]"
        let result = PointTagParser.parse(response)

        #expect(result.coordinate == CGPoint(x: 50, y: 75))
        #expect(result.elementLabel == nil)
        #expect(result.screenNumber == nil)
    }

    @Test func trailingWhitespaceAfterTagIsTolerated() async throws {
        let response = "click here [POINT:10,20:button]   \n  "
        let result = PointTagParser.parse(response)

        #expect(result.coordinate == CGPoint(x: 10, y: 20))
        #expect(result.elementLabel == "button")
        #expect(result.spokenText == "click here")
    }

    @Test func tagMustBeAtEndOfResponse() async throws {
        let response = "I said [POINT:1,2:fake] and then kept talking"
        let result = PointTagParser.parse(response)

        // Tag is mid-string, not at end — should NOT parse out
        #expect(result.coordinate == nil)
        #expect(result.spokenText == "I said [POINT:1,2:fake] and then kept talking")
    }

    @Test func spokenTextHasNoTrailingWhitespace() async throws {
        // The trim happens BEFORE the tag is removed; verify both ends are clean.
        let response = "  click that thing.   [POINT:5,6:thing]"
        let result = PointTagParser.parse(response)

        #expect(result.spokenText == "click that thing.")
    }

    @Test func multiDigitScreenNumberWorks() async throws {
        let response = "way over there [POINT:99,99:label:screen12]"
        let result = PointTagParser.parse(response)

        #expect(result.screenNumber == 12)
        #expect(result.elementLabel == "label")
    }

    @Test func zeroZeroCoordinateParses() async throws {
        let response = "top left [POINT:0,0:origin]"
        let result = PointTagParser.parse(response)

        #expect(result.coordinate == CGPoint(x: 0, y: 0))
        #expect(result.elementLabel == "origin")
    }
}
