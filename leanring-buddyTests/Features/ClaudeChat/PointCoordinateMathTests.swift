//
//  PointCoordinateMathTests.swift
//  leanring-buddyTests
//
//  Tests for the screenshot-pixel → display-point → AppKit-global
//  coordinate conversion extracted from CompanionManager in
//  phase-0/extract-parsers. See docs/reference/02-system-design.md
//  §"Coordinate math" for the three coordinate systems involved.
//

import Testing
import CoreGraphics
@testable import leanring_buddy

struct PointCoordinateMathTests {

    // MARK: - Single-monitor case (display at origin, no scaling)

    @Test func identityCaseWhenScreenshotMatchesDisplayAndOrigin() async throws {
        // Screenshot pixels == display points, display at AppKit origin.
        // Only the Y flip and the screenshot→display scale (1×1) apply.
        let result = PointCoordinateMath.globalLocation(
            forScreenshotPixel: CGPoint(x: 100, y: 200),
            screenshotSize: CGSize(width: 1280, height: 800),
            displaySize: CGSize(width: 1280, height: 800),
            displayFrame: CGRect(x: 0, y: 0, width: 1280, height: 800)
        )

        // x stays at 100, y flips: 800 - 200 = 600
        #expect(result == CGPoint(x: 100, y: 600))
    }

    @Test func topLeftScreenshotPixelMapsToTopLeftAppKit() async throws {
        // (0,0) in screenshot = top-left = (0, displayHeight) in AppKit
        let result = PointCoordinateMath.globalLocation(
            forScreenshotPixel: CGPoint(x: 0, y: 0),
            screenshotSize: CGSize(width: 1280, height: 800),
            displaySize: CGSize(width: 1280, height: 800),
            displayFrame: CGRect(x: 0, y: 0, width: 1280, height: 800)
        )

        #expect(result == CGPoint(x: 0, y: 800))
    }

    @Test func bottomRightScreenshotPixelMapsToBottomRightAppKit() async throws {
        // (width, height) in screenshot = bottom-right = (width, 0) in AppKit
        let result = PointCoordinateMath.globalLocation(
            forScreenshotPixel: CGPoint(x: 1280, y: 800),
            screenshotSize: CGSize(width: 1280, height: 800),
            displaySize: CGSize(width: 1280, height: 800),
            displayFrame: CGRect(x: 0, y: 0, width: 1280, height: 800)
        )

        #expect(result == CGPoint(x: 1280, y: 0))
    }

    // MARK: - Retina / scaled screenshots

    @Test func screenshotPixelsScaleToDisplayPoints() async throws {
        // Realistic case: ScreenCaptureKit yields 1280px-wide JPEG of a
        // 1512-point-wide MacBook Air display. Claude returns a screenshot-
        // pixel coordinate; we scale up to display points.
        let result = PointCoordinateMath.globalLocation(
            forScreenshotPixel: CGPoint(x: 640, y: 400), // middle of the screenshot
            screenshotSize: CGSize(width: 1280, height: 800),
            displaySize: CGSize(width: 1512, height: 982),
            displayFrame: CGRect(x: 0, y: 0, width: 1512, height: 982)
        )

        // Expected display-local: (640 * 1512/1280, 400 * 982/800) = (756, 491)
        // Y flip: 982 - 491 = 491
        #expect(result == CGPoint(x: 756, y: 491))
    }

    // MARK: - Clamping

    @Test func coordinatesAreClampedToScreenshotBounds() async throws {
        // A negative X should clamp to 0
        let result = PointCoordinateMath.globalLocation(
            forScreenshotPixel: CGPoint(x: -50, y: 200),
            screenshotSize: CGSize(width: 1280, height: 800),
            displaySize: CGSize(width: 1280, height: 800),
            displayFrame: CGRect(x: 0, y: 0, width: 1280, height: 800)
        )

        #expect(result.x == 0)
    }

    @Test func oversizedCoordinatesClampToScreenshotEdge() async throws {
        // X above width clamps to width; Y above height clamps to height
        let result = PointCoordinateMath.globalLocation(
            forScreenshotPixel: CGPoint(x: 9999, y: 9999),
            screenshotSize: CGSize(width: 1280, height: 800),
            displaySize: CGSize(width: 1280, height: 800),
            displayFrame: CGRect(x: 0, y: 0, width: 1280, height: 800)
        )

        // x clamped to 1280, y clamped to 800; y flip: 800 - 800 = 0
        #expect(result == CGPoint(x: 1280, y: 0))
    }

    // MARK: - Multi-monitor offsets

    @Test func displayOriginIsAppliedAsGlobalOffset() async throws {
        // Secondary display sits to the right of the main one in AppKit coords.
        // A center-screenshot point on the secondary display should land at
        // (offsetX + halfWidth, halfHeight-flipped).
        let result = PointCoordinateMath.globalLocation(
            forScreenshotPixel: CGPoint(x: 640, y: 400),
            screenshotSize: CGSize(width: 1280, height: 800),
            displaySize: CGSize(width: 1280, height: 800),
            displayFrame: CGRect(x: 1512, y: 0, width: 1280, height: 800)
        )

        // Display-local middle is (640, 400) → flip Y → (640, 400) → translate by (1512, 0)
        #expect(result == CGPoint(x: 1512 + 640, y: 400))
    }

    @Test func secondaryDisplayBelowMainPicksUpNegativeYOrigin() async throws {
        // Secondary display below the main one: displayFrame.origin.y is negative.
        let result = PointCoordinateMath.globalLocation(
            forScreenshotPixel: CGPoint(x: 0, y: 0),
            screenshotSize: CGSize(width: 1280, height: 800),
            displaySize: CGSize(width: 1280, height: 800),
            displayFrame: CGRect(x: 0, y: -800, width: 1280, height: 800)
        )

        // Display-local (0,0) → flip Y → (0, 800) → translate by (0, -800) → (0, 0)
        #expect(result == CGPoint(x: 0, y: 0))
    }
}
