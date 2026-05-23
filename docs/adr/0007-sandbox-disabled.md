# ADR 0007 — App sandbox disabled

**Status**: Accepted (retroactive)
**Date**: 2026-05-22 (documented; original decision predates this)
**Deciders**: original-author
**Related**: [ADR 0003](./0003-cgevent-tap-for-global-shortcut.md), [ADR 0012](./0012-sparkle-and-login-item.md)

## Context

`com.apple.security.app-sandbox` in `leanring-buddy.entitlements` is `false`. This is intentional. Two specific capabilities the app depends on are incompatible with the macOS App Sandbox:

1. **Session-level `CGEventTap`.** The push-to-talk hotkey monitor (see [ADR 0003](./0003-cgevent-tap-for-global-shortcut.md)) opens a `CGEventTap` at `cgSessionEventTap`. The sandbox blocks this — sandboxed apps may only tap their own events. Without a session-level tap we'd lose the entire ambient-hotkey product premise.
2. **Accessibility API access.** `AXIsProcessTrusted()` and the related `AXUIElement` APIs (used by `WindowPositionManager.shrinkOverlappingFocusedWindow` and reachable from the Accessibility-permission flow) are not available to sandboxed apps. The CGEvent tap *also* requires Accessibility permission, which itself requires being un-sandboxed.

Other implications of the choice fell out naturally:

- **Mac App Store is off the table.** App Store distribution requires the sandbox. Clicky ships through GitHub Releases as a notarised DMG, with Sparkle handling updates from a hosted appcast.
- **Notarisation is mandatory.** With Gatekeeper-only signing (no App Store review), Apple requires notarisation for the DMG to run on a fresh Mac without the user right-clicking to override. `scripts/release.sh` handles `xcrun notarytool submit --wait` and `xcrun stapler staple` as steps 6–7 of the release pipeline.

See `leanring-buddy.entitlements` for the entitlements file itself, `docs/reference/06-build-and-release.md` § "Entitlements and code signing" for the full table, and `scripts/release.sh` for the notarisation flow.

## Decision

The app is un-sandboxed. `leanring-buddy.entitlements` sets `com.apple.security.app-sandbox` to `false` and instead declares the minimal set of capability entitlements actually used:

| Entitlement | Value | Reason |
|------------|-------|--------|
| `com.apple.security.network.client` | `true` | Worker, Anthropic, ElevenLabs, AssemblyAI, FormSpark, PostHog, Mux HLS. |
| `com.apple.security.device.audio-input` | `true` | Microphone access for push-to-talk. |
| `com.apple.security.device.camera` | `true` | Declared but currently unused (camera is reserved for future use). |
| `com.apple.security.temporary-exception.mach-lookup.global-name` → `com.apple.screencapturekit.picker` | array | Required by ScreenCaptureKit's picker dialog. |

Distribution is GitHub Releases → DMG → Sparkle auto-update. Notarisation is part of every release via `scripts/release.sh`.

## Consequences

### Positive
- The CGEvent tap and Accessibility API both work, which is what the product needs.
- We are not constrained by App Store review timelines — we ship when the release script finishes.
- Sparkle auto-update (see [ADR 0012](./0012-sparkle-and-login-item.md)) gives users a one-click update path independent of the App Store.

### Negative
- **No Mac App Store distribution.** Reach is smaller; users who only install from the Store will never see Clicky.
- Notarisation has to happen on every release and depends on Apple's notary service being up. `scripts/release.sh` waits for the result; an Apple outage stalls releases.
- Gatekeeper still occasionally surprises users on first launch ("can't be opened because the developer cannot be verified") even when notarised — this happens when the staple step is missed or stripped from the DMG.
- The unused `com.apple.security.device.camera` entitlement is harmless but slightly noisy; it shows up in Apple's signed-entitlements display.

### Neutral / trade-offs
- All TCC permissions (Accessibility, Screen Recording, Microphone, Screen Content) still apply just as they would to a sandboxed app — un-sandboxing does not bypass TCC. The user still grants each individually.
- A non-sandboxed app has access to the whole filesystem in principle. We do not exercise that — the app only reads from its bundle and writes only to `UserDefaults`. If we ever add real file I/O, this is something to be deliberate about.

## Notes

If the project ever wants App Store distribution, the CGEvent tap would need to be replaced with `NSEvent.addGlobalMonitorForEvents`, which is sandbox-compatible but unreliable for modifier-only shortcuts (see [ADR 0003](./0003-cgevent-tap-for-global-shortcut.md)). That would mean either changing the default hotkey to one with a character key, or accepting a worse press-detection rate. Neither is appealing — the choice to ship outside the Store is the right one given the product.
