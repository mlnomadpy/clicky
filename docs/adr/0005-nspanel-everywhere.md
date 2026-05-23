# ADR 0005 — Borderless non-activating NSPanels for every window surface

**Status**: Accepted (retroactive)
**Date**: 2026-05-22 (documented; original decision predates this)
**Deciders**: original-author
**Related**: [ADR 0001](./0001-menu-bar-only-app.md)

## Context

Clicky has exactly two on-screen surfaces (see `docs/reference/01-overview.md` § "User-visible surface"):

1. The menu-bar dropdown panel that appears when the user clicks the status item.
2. The cursor overlay — one per `NSScreen` — that hosts the blue triangle, the waveform, the spinner, and the response bubble.

Both have a hard non-negotiable requirement: **they must never steal keyboard focus from the user's frontmost app**. The whole product premise (see [ADR 0001](./0001-menu-bar-only-app.md)) is that the user keeps working in some other app while Clicky is running. If clicking the menu-bar icon — or worse, showing the overlay — yanks focus away from the user's Xcode/Figma/Chrome, the app is broken.

The standard candidates were:

- **`NSPopover` for the dropdown.** Free menu-bar attachment, system shadow, system corner radius. Rejected because the visual chrome doesn't match the rest of the app (light, system-styled), and `NSPopover` can be finicky about staying open during system permission prompts.
- **`NSMenu` for the dropdown.** Too inflexible — can't host arbitrary SwiftUI, can't host a text field for email entry, can't keep state across opens.
- **`NSWindow` for the overlay.** Defaults to becoming key on `.makeKeyAndOrderFront(_:)`, which steals focus. Can be configured to behave correctly but the panel APIs were designed for this exact use case.
- **`NSPanel`** — designed to be a secondary, floating utility window. Supports `.nonactivatingPanel` style mask which is exactly the "don't take focus" behaviour we need.

A subtle requirement: the dropdown panel hosts a `TextField` for the onboarding email. `NSPanel` defaults to `canBecomeKey = false` for non-activating panels. Without overriding that, the text field never receives focus and the user can't type. The fix is a one-line `NSPanel` subclass (`KeyablePanel`) that overrides `canBecomeKey = true`. The overlay does *not* need this — it never has interactive controls.

See `MenuBarPanelManager.swift` (panel lifecycle), `OverlayWindow.swift` (per-screen overlay), and `docs/reference/02-system-design.md` § "Why three windows live in `NSPanel`s, not `NSWindow`s".

## Decision

Every visible window in Clicky is an `NSPanel` with `.nonactivatingPanel` in its style mask:

- **The menu-bar dropdown** is a `KeyablePanel` (an `NSPanel` subclass that overrides `canBecomeKey` to `true`) with `.borderless | .nonactivatingPanel`. Positioned beneath the status item; auto-dismisses on outside click via `NSEvent.addGlobalMonitorForEvents` with a 300 ms delay so a system permission dialog (triggered by an in-panel Grant button) doesn't immediately dismiss the panel.
- **The cursor overlay** is one `OverlayWindow : NSWindow` per `NSScreen`. Despite the class name `NSWindow`, it is configured at runtime with the same panel-style flags: `.borderless`, `level = .screenSaver`, `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]`, `ignoresMouseEvents = true`, and the window never becomes key or main.

SwiftUI content is bridged in via `NSHostingView` in both cases.

## Consequences

### Positive
- Clicking the menu-bar icon, showing the overlay, or pressing the hotkey never pulls focus from the user's current app.
- The overlay floats above all Spaces and full-screen apps because of `[.canJoinAllSpaces, .fullScreenAuxiliary]` — Clicky still works when the user is in a full-screen Xcode.
- `ignoresMouseEvents = true` on the overlay makes the whole transparent window click-through, so clicking "behind" the triangle interacts with the app under it.
- Full visual control: the dropdown's dark rounded look and the overlay's transparent click-through behaviour are both achievable because we own the window, not the OS.

### Negative
- We give up everything `NSPopover` and `NSMenu` provide for free — system shadows, system corner radii, system focus management. We re-implement the parts we want in SwiftUI (`DesignSystem.swift`).
- The `KeyablePanel` override is non-obvious. If someone adds another interactive control inside the overlay (today there are none), they'll trip over the same `canBecomeKey = false` default.
- Outside-click dismissal of the dropdown is hand-rolled via `NSEvent.addGlobalMonitorForEvents` rather than the system handling it. The 300 ms delay is a load-bearing hack to keep the panel open while a system permission prompt is on top.

### Neutral / trade-offs
- Each overlay is created and destroyed when the user toggles "Show Clicky" or moves between Spaces. `OverlayWindowManager` owns the lifecycle.
- The dropdown panel positions itself manually via `positionPanelBelowStatusItem` using the hosting view's `fittingSize`. This means the panel hugs its SwiftUI content but we have to keep the layout logic correct ourselves.

## Notes

If we ever want a settings sheet larger than the dropdown panel allows, the right pattern is a separate borderless `NSPanel` opened from the dropdown — not switching to `NSWindow` and not opening a main window. The "never steal focus" rule is what makes the rest of the app behave well.
