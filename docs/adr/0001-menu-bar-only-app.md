# ADR 0001 — Menu-bar-only application

**Status**: Accepted (retroactive)
**Date**: 2026-05-22 (documented; original decision predates this)
**Deciders**: original-author
**Related**: [ADR 0005](./0005-nspanel-everywhere.md), [ADR 0012](./0012-sparkle-and-login-item.md)

## Context

Clicky is a cursor companion. The product idea is that the app sits silently in the background until the user holds `ctrl+option`, at which point a blue triangle on the screen reacts to their voice and the AI talks back. The interaction model is ambient — there is no "open the app and use it" step. The user's focus stays in whatever app they're already working in (Xcode, Figma, a browser); Clicky is a layer on top of that.

A full Dock app would be wrong for this. A Dock icon would invite focus-stealing — clicking it would activate the app and pull the user out of their current context. A main window would imply there's a primary workspace inside Clicky, which there isn't. A preferences window would imply settings worth tweaking, but the only settings (model picker, "Show Clicky", "Watch onboarding again") fit in a small dropdown.

The alternatives that existed: (a) a regular Dock app with a hidden main window, (b) a Dock app that auto-minimises on launch, (c) a menu-bar-only `LSUIElement` app, (d) an `LSBackgroundOnly` headless agent with no UI surface at all. Option (d) was rejected because users need *some* place to grant permissions, see onboarding, and pick a model. Options (a) and (b) were rejected because they still surface a Dock icon, which is exactly what we don't want.

See `Info.plist` (`LSUIElement=true`), `leanring_buddyApp.swift:14` (`Settings` scene used as a hidden no-op so SwiftUI is happy with no main window), `MenuBarPanelManager.swift` (status item + dropdown panel), and `docs/reference/01-overview.md` for the user-visible surface.

## Decision

Clicky is a menu-bar-only app. `LSUIElement=true` in `Info.plist` removes the Dock icon and the standard app-menu chrome. The `@main` `App` declares a single `Settings` scene which SwiftUI accepts as a no-op (no window is created). All user-visible UI lives in two surfaces created by `CompanionAppDelegate`:

1. A status-bar item with a borderless dropdown `NSPanel` (`MenuBarPanelManager`).
2. A full-screen transparent cursor overlay (`OverlayWindow`).

There is no main window, no preferences window, no Cmd+, settings shortcut, no Dock right-click menu. Quit is exposed as a button at the bottom of the dropdown panel.

## Consequences

### Positive
- The app feels ambient — it never interrupts whatever the user is doing.
- Push-to-talk works while another app is foreground without any focus dance.
- No risk of a stray "main window" stealing focus on launch or on URL handling.
- Smaller mental footprint for the user: there is exactly one place to find Clicky (the menu bar) and one way to interact with it (the global hotkey).

### Negative
- New users can miss the status-item icon entirely — onboarding has to auto-open the panel on first launch (`leanring_buddyApp.swift:49`) and we still rely on a demo to teach the hotkey.
- No standard macOS affordances like Cmd+, for preferences, Cmd+Q to quit (we wire Cmd+Q through the panel's quit button), Window menu, or Help menu.
- `LSUIElement=true` apps don't get the standard app activation lifecycle, which complicates anything that wants to act like a "frontmost app" (currently nothing does).

### Neutral / trade-offs
- Forces every UI surface into either the dropdown panel or the cursor overlay. This is a constraint that influences every subsequent UI decision — see [ADR 0005](./0005-nspanel-everywhere.md).
- The hidden `Settings` scene is required by SwiftUI to satisfy the `App` protocol; it never instantiates a window. If we ever want a real preferences window we have to remove it carefully.

## Notes

If we ever ship a settings sheet that exceeds the dropdown panel's size budget, the right move is a borderless modal panel triggered from the dropdown — not adding a main window. The whole point of being menu-bar-only is that the user's primary surface is *their* app, not ours.
