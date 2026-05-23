# ADR 0004 — ScreenCaptureKit for multi-monitor screenshots

**Status**: Accepted (retroactive)
**Date**: 2026-05-22 (documented; original decision predates this)
**Deciders**: original-author
**Related**: [ADR 0010](./0010-text-based-point-protocol.md), [ADR 0007](./0007-sandbox-disabled.md)

## Context

Every push-to-talk turn captures a screenshot of every connected display and sends them to Claude. The screenshots are the model's only view of what the user is looking at, so they have to be (a) reliable on multi-monitor setups, (b) free of the app's own UI (no recursion where Clicky sees the cursor overlay it just drew), and (c) compatible with macOS's evolving screen-recording permission model.

Two APIs were available:

1. **`CGWindowListCreateImage` / `CGDisplayCreateImage`** — the long-standing Core Graphics path. Works on every macOS version Clicky targets. As of macOS 12 it shows a yellow recording indicator and requires Screen Recording permission. On macOS 14 it was deprecated, with Apple pushing developers toward ScreenCaptureKit.
2. **`SCScreenshotManager.captureImage(contentFilter:configuration:)`** — the ScreenCaptureKit one-shot capture API (macOS 14.0+; the picker permission and stable cross-display behaviour we rely on landed in 14.2). First-class support for `SCContentFilter.init(display:excludingWindows:)`, which lets us pass our own windows in the exclude list and capture every display in parallel.

The exclude-windows capability is the decisive feature. With `CGWindowList` we would have had to hide our overlay before each capture and re-show it after — race-prone and would visibly flicker the cursor. With `SCScreenshotManager` we filter out windows whose `owningApplication?.bundleIdentifier` matches our own bundle and capture normally; the overlay never appears in the image sent to Claude.

See `CompanionScreenCaptureUtility.swift` for the implementation, `docs/reference/03-features.md` § 4 for the full flow, and `leanring-buddy.entitlements` for the `com.apple.screencapturekit.picker` mach-lookup exception.

## Decision

`CompanionScreenCaptureUtility.captureAllScreensAsJPEG()` uses ScreenCaptureKit:

1. `SCShareableContent.current` enumerates displays and on-screen windows.
2. For each `SCDisplay`, a `SCContentFilter(display:excludingWindows:)` excludes every window owned by `Bundle.main.bundleIdentifier`.
3. `SCScreenshotManager.captureImage(contentFilter:configuration:)` captures the display in parallel.
4. Each capture is mapped from `SCDisplay.displayID` to an `NSScreen` so the returned `displayFrame` is in AppKit (bottom-left) coordinates, matching the overlay's frame.
5. The cursor-containing display is sorted first in the returned array.
6. Long edge is clamped to 1280 px, aspect preserved, encoded as JPEG at compression factor 0.8.

macOS 14.2 is the minimum deployment target because of this dependency.

## Consequences

### Positive
- The menu-bar panel and the cursor overlay are never visible to Claude — no AI-sees-itself recursion.
- Each display is captured independently in parallel; latency stays low even on triple-monitor rigs.
- The labeled image stream (`"screen 1 of 2 — cursor is on this screen (primary focus) (image dimensions: 1280x800 pixels)"`) gives Claude exactly the coordinate space it needs to emit `[POINT:...]` tags (see [ADR 0010](./0010-text-based-point-protocol.md)).
- ScreenCaptureKit is the API Apple is investing in; CG-based screen capture is on a deprecation curve.

### Negative
- Hard floor of macOS 14.2. Users on older macOS versions cannot run Clicky.
- ScreenCaptureKit ships *two* permission gates: Screen Recording (the standard TCC one) and the ScreenCaptureKit picker grant (`com.apple.screencapturekit.picker` mach-lookup). The picker grant is a separate first-time prompt that we have to detect and latch in `UserDefaults["hasScreenContentPermission"]` because the OS never re-asks once granted.
- The `excludingWindows` filter is built every capture from `SCShareableContent.current`, which is itself an async call. This adds 20–80 ms to the start of each capture cycle.

### Neutral / trade-offs
- The `SCDisplay → NSScreen` mapping has to be done carefully because the two coordinate spaces disagree on multi-monitor setups (one is top-left origin, the other bottom-left). The conversion lives in `CompanionScreenCaptureUtility` and is the single source of truth for "display frame in AppKit coordinates".
- We cap the long edge at 1280 px before JPEG encoding. This is well below the model's input limit but keeps the request payload small enough that the TLS cold-start is rare (see [ADR 0009](./0009-tls-warmup-and-shared-urlsession.md)).

## Notes

If a future macOS forces ScreenCaptureKit to bring up the picker dialog on every capture (Apple has hinted at this in WWDC talks), we will need to revisit. Today the one-time grant model holds and the `requestScreenContentPermission()` flow on first launch is sufficient.
