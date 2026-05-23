//
//  PointCoordinateMath.swift
//  leanring-buddy
//
//  Converts a point that Claude returned in screenshot pixel coordinates
//  (top-left origin) into a global AppKit point (bottom-left origin),
//  applying the screenshot→display scale and the display's screen offset.
//
//  Extracted from CompanionManager.swift per
//  docs/specs/15-feature-improvements.md §1.3 — the same ~15 lines lived
//  in two places (the main voice-response path and the onboarding demo)
//  and were drifting apart.
//
//  See docs/reference/02-system-design.md §"Coordinate math" for the
//  three coordinate systems involved.
//

import Foundation
import CoreGraphics

enum PointCoordinateMath {

    /// Converts a Claude-returned point from screenshot pixel coords (top-left origin)
    /// to a global AppKit coordinate (bottom-left origin) on the display whose pixel /
    /// point dimensions and origin are passed in.
    ///
    /// Steps:
    /// 1. Clamp the point to the screenshot's pixel bounds.
    /// 2. Scale from screenshot pixels to display points using the per-axis ratio.
    /// 3. Flip Y so the origin moves from top-left (screenshot) to bottom-left (AppKit).
    /// 4. Translate by the display's global origin so the result is in AppKit's
    ///    global coordinate space.
    static func globalLocation(
        forScreenshotPixel point: CGPoint,
        screenshotSize: CGSize,
        displaySize: CGSize,
        displayFrame: CGRect
    ) -> CGPoint {
        // 1. Clamp to screenshot coordinate space
        let clampedX = max(0, min(point.x, screenshotSize.width))
        let clampedY = max(0, min(point.y, screenshotSize.height))

        // 2. Scale from screenshot pixels to display points
        let displayLocalX = clampedX * (displaySize.width / screenshotSize.width)
        let displayLocalY = clampedY * (displaySize.height / screenshotSize.height)

        // 3. Convert from top-left origin (screenshot) to bottom-left origin (AppKit)
        let appKitY = displaySize.height - displayLocalY

        // 4. Convert display-local coords to global screen coords
        return CGPoint(
            x: displayLocalX + displayFrame.origin.x,
            y: appKitY + displayFrame.origin.y
        )
    }
}
