# ADR 0003 — Listen-only CGEvent tap for the global push-to-talk shortcut

**Status**: Accepted (retroactive)
**Date**: 2026-05-22 (documented; original decision predates this)
**Deciders**: original-author
**Related**: [ADR 0007](./0007-sandbox-disabled.md), [ADR 0001](./0001-menu-bar-only-app.md)

## Context

The whole point of Clicky is that the user keeps working in some other app — Xcode, Figma, a browser — and holds a global hotkey to talk to it. That hotkey is `ctrl+option` (modifiers only, no character key). The app must detect press and release reliably while it is *not* the frontmost app.

macOS offers two ways to listen to keystrokes globally:

1. **`NSEvent.addGlobalMonitorForEvents(matching:handler:)`** — the AppKit-blessed path. Listens to events delivered to other apps. Cheap, no Accessibility permission required for most event masks. Has two problems for this use case: it skips `.flagsChanged` events for modifier-only shortcuts unreliably while the app is in the background, and it suppresses repeats in ways that are hard to predict. In testing, modifier-only shortcuts (`ctrl+option`) were dropped on perhaps 1 in 8 presses when the app wasn't frontmost.
2. **`CGEventTap`** at `cgSessionEventTap`. The lower-level Quartz event-tap API. Sees every event in the session before it reaches any app. Modifier transitions are first-class via `.flagsChanged`. Requires Accessibility permission. Can be `.listenOnly` (read but never modify events) or active.

Active taps can swallow events or rewrite them, which is exactly the kind of foot-gun we don't need — if the tap crashes or hangs, every keystroke on the machine stalls. Listen-only taps avoid that entire failure mode: the OS will never block on us; the worst that can happen is we miss an event.

See `GlobalPushToTalkShortcutMonitor.swift` for the implementation, `BuddyDictationManager.swift:95` (`BuddyPushToTalkShortcut.currentShortcutOption = .controlOption`) for the hardcoded shortcut, and `docs/reference/02-system-design.md` § "Why a listen-only CGEvent tap".

## Decision

`GlobalPushToTalkShortcutMonitor` opens a `CGEventTap` at `.cgSessionEventTap` / `.headInsertEventTap` with `.listenOnly` placement. The tap matches `flagsChanged | keyDown | keyUp`. Modifier-only shortcuts are detected by inspecting `event.flags` on `.flagsChanged` (matching `[.control, .option]`); character-based variants (e.g. `controlOptionSpace`) match the keycode on `keyDown` / `keyUp`.

The tap publishes `.pressed` / `.released` on the main run loop. `CompanionManager.handleShortcutTransition` is the single consumer. If macOS disables the tap (`.tapDisabledByTimeout` or `.tapDisabledByUserInput`), the monitor re-enables it without restarting the whole app.

## Consequences

### Positive
- Modifier-only shortcuts are detected on every press regardless of which app is frontmost.
- Listen-only mode means we can never block another app's keyboard input — the worst-case failure is "Clicky misses one press".
- The tap is on the main run loop, so the press/release transition flows through Combine to the voice state machine with no thread hop.

### Negative
- Requires Accessibility permission, which is a friction point at onboarding — users must explicitly grant it in System Settings → Privacy & Security → Accessibility.
- Apps cannot be sandboxed and also open a session-level CGEvent tap. This is one of the two reasons the app sandbox is off — see [ADR 0007](./0007-sandbox-disabled.md).
- If the user revokes Accessibility permission while the app is running, the tap stops firing silently. We catch this by polling `AXIsProcessTrusted()` every 1.5 s in `CompanionManager.refreshAllPermissions` and restarting the monitor when permission returns.

### Neutral / trade-offs
- The tap intentionally lives on the main run loop, not a background one. A background-loop tap would be slightly more isolated from main-thread stalls, but routing the press/release transition back through Combine on the main actor is simpler and the latency cost is negligible (< 1 ms per event).
- The shortcut is hardcoded to `ctrl+option`. The `BuddyPushToTalkShortcut` enum has scaffolding for `shiftFunction`, `shiftControl`, and the space-based variants, but nothing exposes them in the UI. Changing the shortcut requires a code edit.

## Notes

If we ever ship a user-configurable shortcut, the parsing layer in `BuddyDictationManager.shortcutFromCGEvent` already knows how to handle character-based variants — the work is just UI in `CompanionPanelView` plus a `UserDefaults` round-trip.
