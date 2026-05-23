# Feature Improvements — Audit-driven cleanups

> **Status**: design doc / RFC. Tier 1 lands in Phase 0 of the roadmap. Tier 2 and Tier 3 are deferred but worth keeping visible.

This document is the output of the system audit (`docs/reference/01–08`). Everything below is something the audit surfaced — usually a quality issue, a latent feature, or a polish gap that's *not* a blocker but is worth fixing.

Three tiers based on risk and value:

- **Tier 1 — Mechanical cleanups.** Low risk, immediate value. Ship in Phase 0 alongside the FSD restructure.
- **Tier 2 — Behavior improvements.** Some testing risk. Ship after FSD lands and tests exist.
- **Tier 3 — Polish & future work.** Lower priority. Track here so we don't lose them.

---

## Tier 1 — Mechanical cleanups

### 1.1 Re-enable Sparkle auto-update

**Current state**: `CompanionAppDelegate.startSparkleUpdater()` is fully implemented but commented out at the call site in `leanring_buddyApp.swift:53`. The Sparkle SPM dependency is present, the `SUFeedURL` and `SUPublicEDKey` are in `Info.plist`, and the release script signs DMGs with the matching EdDSA key.

**Why it's deferred**: unclear. Likely "the appcast wasn't ready yet."

**Fix**: uncomment the line. Verify `appcast.xml` is publicly reachable. The Sparkle controller is configured for `startingUpdater: false` — `start()` runs separately so updates aren't checked at literal startup; they're checked on a Sparkle-internal schedule.

**Risk**: low. If the appcast is broken, Sparkle logs and silently no-ops.

### 1.2 Replace ad-hoc `print(...)` with structured logging

**Current state**: ~80 `print("🎙️ ...")` / `print("⚠️ ...")` calls scattered across the Swift sources. They go to stdout, never persisted, never queryable.

**Fix**: introduce `Shared/Logging/ClickyLogger.swift` (an `os.Logger` wrapper) with categories matching feature slices (`voice-pipeline`, `claude-chat`, `overlay`, etc.). Replace `print` calls during the FSD migration step that touches each file.

**Benefits**: logs are queryable via Console.app, persist across launches, can be filtered by category and level, included in sysdiagnose, redacted automatically for privacy where flagged.

**Risk**: low. The existing prints are debug aids; nothing depends on their format.

### 1.3 De-duplicate the screenshot-coordinate math

**Current state**: the screenshot→display→AppKit coordinate conversion is duplicated in `CompanionManager.swift` — once in `sendTranscriptToClaudeWithScreenshot` (around line 663) and again in `performOnboardingDemoInteraction` (around line 1005). About 15 lines of near-identical math.

**Fix**: extract to `Features/ClaudeChat/PointCoordinateMath.swift`. Pure function signature:

```swift
enum PointCoordinateMath {
    static func globalLocation(
        forScreenshotPixel point: CGPoint,
        screenshotSize: CGSize,
        displaySize: CGSize,
        displayFrame: CGRect
    ) -> CGPoint
}
```

This is also the most-tested function we have (every `[POINT:x,y]` flows through it) — extracting it is the prerequisite for `PointCoordinateMathTests.swift` in `specs/14-testing-strategy.md`.

**Risk**: low. Pure refactor, unit-tested.

### 1.4 Remove or document `OpenAIAPI.swift`

**Current state**: `OpenAIAPI.swift` (142 LOC) is a full GPT vision client, but it's not called anywhere in the active code paths. It looks like a fallback that was never wired in. The model string defaults to `"gpt-5.2-2025-12-11"` which is suspiciously future-dated.

**Options**:
- **A**: delete. Reduces dead code; if someone wants it back, git has it.
- **B**: keep, but add a comment at the top stating *"unused on the hot path; kept for ad-hoc testing"*.

**Recommendation**: A. The `OpenAIAudioTranscriptionProvider` already proves we can wire OpenAI services through `Info.plist` if the need arises — we don't need to keep an unused vision client around for symmetry.

**Risk**: low.

*Status: planned for Wave-2 PR — see `DELETION_PLAN.md`.*

### 1.5 Remove or document the legacy `WindowPositionManager` helpers

**Current state**: `WindowPositionManager.swift` has two methods that are no longer called from the active code: `pinMainWindowToRight(onDisplayID:)` and `shrinkOverlappingFocusedWindow(targetDisplayID:)`. They were used when Clicky had a docked main window; now it doesn't.

**Fix**: delete both methods. The permission utilities (`hasAccessibilityPermission`, `requestAccessibilityPermission`, etc.) stay — they're the file's actual purpose. Rename the file to `PermissionsHelper.swift` and move it under `Features/Permissions/`.

**Risk**: low.

*Status: planned for Wave-2 PR — see `DELETION_PLAN.md`.*

### 1.6 Remove or wire `ElementLocationDetector`

**Current state**: `ElementLocationDetector.swift` (335 LOC) uses Anthropic's Computer Use API for pointing. The current hot path doesn't use it — it parses Claude's `[POINT:x,y]` tag directly from regular chat responses.

**Options**:
- **A**: delete entirely. Computer Use can be re-introduced later if needed.
- **B**: keep as a fallback for cases where the `[POINT:none]` tag is returned but a pointing answer is still expected.
- **C**: repurpose as the *Local mode* OCR-pointing implementation (see `specs/11-offline-and-local-models.md` §OCR-pointing trick).

**Recommendation**: A for now. Local mode pointing is being designed from scratch with Vision OCR + Foundation Models; reusing this file would mostly be a name collision. We can resurrect it from git if the design calls for it.

**Risk**: low.

*Status: planned for Wave-2 PR — see `DELETION_PLAN.md`.*

### 1.7 Hide the unused "Show Clicky" UI section behind a feature flag

**Current state**: in `CompanionPanelView.swift` lines 52–59 there's a commented-out `showClickyCursorToggleRow` block. The runtime path for `isClickyCursorEnabled` is fully wired in `CompanionManager` — it's just the UI that's hidden.

**Options**:
- **A**: ship it. The toggle is useful; the runtime works.
- **B**: delete the runtime path too. If we don't ship the UI, the underlying support is dead code.

**Recommendation**: A. Add the row back. The transient cursor mode behavior is one of the more compelling product features and deserves to be discoverable.

**Risk**: low.

### 1.8 Make the push-to-talk shortcut user-configurable

**Current state**: `BuddyPushToTalkShortcut.currentShortcutOption = .controlOption`. The enum already supports 5 options (`shiftFunction`, `controlOption`, `shiftControl`, `controlOptionSpace`, `shiftControlSpace`) — the wiring exists but isn't exposed.

**Fix**: add a "Push-to-talk shortcut" row to the panel. Persist the choice to `UserDefaults["pushToTalkShortcut"]`. Restart the `GlobalPushToTalkShortcutMonitor` on change.

**Risk**: low. The hard work is already done.

### 1.9 Move the system prompts out of `CompanionManager`

**Current state**: `companionVoiceResponseSystemPrompt` (~30 lines) and `onboardingDemoSystemPrompt` (~10 lines) are static String constants on the giant `CompanionManager` class.

**Fix**: move to `Features/ClaudeChat/ClaudeSystemPrompts.swift`. Same constants, just in a focused file. This is a natural step during the FSD migration.

**Risk**: zero.

### 1.10 Consolidate the bundled audio assets

**Current state**: `enter.mp3`, `eshop.mp3`, `ff.mp3`, `steve.jpg`, `codex-add-project.png` all live at the top of `leanring-buddy/`. `ff.mp3` is 8 MB.

**Fix**: move all to `Resources/`. Use them via `Bundle.main.url(forResource:withExtension:)` (already the pattern). Audit which ones are actually referenced — `enter.mp3` and `eshop.mp3` don't appear to be played anywhere in `CompanionManager` (only `ff.mp3` for onboarding music) and might be deletable.

**Risk**: low.

---

## Tier 2 — Behavior improvements

These need tests to land safely. Tier 2 starts after Phase 0's testing infrastructure is in place.

### 2.1 Token-budget-based conversation history (not turn count)

**Current state**: `CompanionManager.conversationHistory` is capped at 10 turns regardless of length. Long turns can blow up the prompt; short turns waste the budget.

**Fix**: cap by estimated token count instead. Use `tiktoken`-equivalent or a 3.5-char-per-token rule of thumb. Default budget: 6000 tokens; drop oldest turn(s) until under budget. Expose as a hidden setting.

**Risk**: medium. Changes the prompt shape Claude sees — could shift Claude's responses subtly. Test with both single- and multi-turn fixtures before shipping.

### 2.2 Switch transcription provider at runtime

**Current state**: `BuddyTranscriptionProviderFactory.resolveProvider()` runs once at `BuddyDictationManager.init`. Provider can't change without an app restart.

**Fix**: allow `BuddyDictationManager.swap(provider:)` so the panel can switch between AssemblyAI / OpenAI / Apple Speech. Useful for the Local-mode picker (`specs/11`).

**Risk**: medium. The provider lifecycle (active session, audio engine) needs careful teardown.

### 2.3 Adaptive screenshot resolution

**Current state**: `CompanionScreenCaptureUtility` clamps the long edge to 1280 px regardless of display size. A 6K display gets aggressively downsampled; a 1080p display sees no benefit.

**Fix**: scale to ~85% of the actual display pixel dimensions, but cap at 1600 px on the long edge. Re-test with Claude's pointing accuracy on a 4K display — the existing 1280 cap was chosen to keep payloads small (and cheap), not because it's the right precision target.

**Risk**: medium. Bigger payloads cost more tokens.

### 2.4 PostHog privacy mode (opt-out + transcript redaction)

**Current state**: `ClickyAnalytics.trackUserMessageSent(transcript:)` and `trackAIResponseReceived(response:)` ship the full text of every voice turn. Distinct ID is the user's email.

**Fix**:
- Add a "Send anonymous analytics" toggle in the panel. Default: on (preserves today's behavior).
- When off, all `PostHogSDK.shared.capture` calls are no-ops.
- When on but the mode is Hybrid or Local: drop the `transcript` / `response` property and ship only the lengths. The Local-mode case already disables PostHog entirely per `specs/11`.
- Document the user's choice in onboarding copy.

**Risk**: medium. Reduces our debugging surface for failures but is the right product call.

### 2.5 Replace 1.5s permission polling with system notifications

**Current state**: `CompanionManager.startPermissionPolling` runs a `Timer.scheduledTimer(withTimeInterval: 1.5, ...)` forever. Wakes the CPU every 1.5 s just to call `AXIsProcessTrusted()`.

**Fix**: use `NSWorkspace.shared.notificationCenter` for what's available (accessibility changes via `NSAccessibility` notifications aren't first-class, but app-foreground changes are). For Accessibility specifically, there's no clean OS notification — keep a slower polling timer (10 s) as a fallback, or only poll while the panel is open. Microphone permission has callbacks via `AVCaptureDevice.requestAccess`.

**Risk**: low energy impact, mostly a code-cleanliness win.

### 2.6 Decompose `CompanionManager`

**Current state**: 1026 LOC, ~25 published properties, owns the voice pipeline, the response pipeline, the overlay, onboarding, music, permissions, and analytics dispatch.

**Fix**: this is Step 4 of the FSD migration in `specs/13`. Listed here for completeness.

**Risk**: this is the highest-risk piece of the Phase 0 restructure, which is why the testing strategy in `specs/14` is the prerequisite.

### 2.7 Stream ElevenLabs TTS for lower latency

**Current state**: `ElevenLabsTTSClient.speakText` claims to stream in its file comment but actually awaits the full MP3 via `session.data(for:)` before calling `AVAudioPlayer.play()`. Latency is "wait for full audio + play."

**Fix**: switch to `URLSession.bytes(for:)` and pipe into `AVAudioPlayerNode` or `AVAudioConverter` so playback can start while audio is still arriving. ElevenLabs' streaming endpoint already supports this.

**Risk**: medium. AVAudioPlayer doesn't natively stream; AVAudioPlayerNode requires more wiring. But the latency win on the first phoneme is meaningful (~500 ms in practice).

### 2.8 Make `requestScreenContentPermission` cheaper

**Current state**: triggers the macOS picker by capturing a real 320×240 screenshot. The capture is throwaway but the picker UX is what we want.

**Fix**: use `SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)` alone — it's the call that actually triggers the picker; the screenshot capture afterwards is unnecessary. Validate that this still triggers the prompt on a fresh install.

**Risk**: low. If the prompt doesn't trigger from `SCShareableContent` alone, the old screenshot path stays as a fallback.

### 2.9 Cancel in-flight transcript when push-to-talk fires again

**Current state**: `handleShortcutTransition(.pressed)` cancels `currentResponseTask` and stops TTS, but if the previous transcript is *still being finalized* by the provider (e.g., AssemblyAI's `requestFinalTranscript` flow with the 1.4s grace period), the result can still arrive after the new turn started.

**Fix**: cancel the dictation session's pending transcript explicitly on press; check `pendingStartRequestIdentifier` before delivering the finalized text.

**Risk**: low, but the bug is hard to reproduce — needs a test rather than manual repro.

---

## Tier 3 — Polish & future work

Lower priority. Listed so we don't lose them.

### 3.1 Bundle the onboarding video locally (skip Mux)

The onboarding video is the only first-launch network dependency. Bundling a ~30 MB MP4 makes Clicky truly offline-capable from first launch. Trade-off: app download size grows.

### 3.2 Apple Personal Voice integration

`AVSpeechSynthesizer` supports the user's trained Personal Voice (macOS 14+). Surface this in the panel as "Use my voice" — for Local mode users who want their cloned voice instead of the canned Neural voice.

### 3.3 Better failure mode for credits-exhausted

`speakCreditsErrorFallback` uses `NSSpeechSynthesizer` (the old, robotic Apple voice — not `AVSpeechSynthesizer`). The line "I'm all out of credits. Please DM Farza..." is shipped as a hardcoded string. Replace `NSSpeechSynthesizer` with `AVSpeechSynthesizer` for a much nicer voice, and surface a panel notification too — the audio alone is easy to miss.

### 3.4 First-class multi-display picker

When pointing across multiple monitors, the `[POINT:...:screenN]` math handles correctness, but the *cursor position* before flight is whatever screen `NSEvent.mouseLocation` returns. If the user is on screen 1 and Claude points to screen 2, the flight should start from a sensible location on screen 2's edge, not from screen 1's cursor. Refine the animator.

### 3.5 In-app "DM Farza" feedback panel

Today the "DM Farza" button opens Twitter. A direct in-app feedback form (writing to a Cloudflare Worker route or to GitHub Issues via a PAT) would convert more feedback. Trade-off: more infrastructure.

### 3.6 Live latency metric in the panel

Track and display "Avg response time over the last 10 turns." Useful for power users tuning mode (Cloud vs Hybrid) — they can see immediately whether their choice was faster.

### 3.7 A "panic clear" button

Single button in the panel that: clears conversation history (RAM + vector store), clears screen memory, clears the current overlay, cancels any in-flight task. For demos / privacy-sensitive moments. Trivial to implement once `VectorMemory/` exists.

### 3.8 Onboarding "no email needed" path

Email collection happens before Start can be clicked. Some users will (reasonably) want to try the app without sharing an email. Add a "Skip" link that lets them through but tracks the skip event. Drives onboarding completion up.

### 3.9 Surface AssemblyAI keyterms editing

`BuddyDictationManager.buildTranscriptionKeyterms()` has a baked-in list plus a `contextualKeyterms` setter that's never called. Expose a "Domain words" multi-line text field in the panel so users with non-standard vocabulary (medical, legal, niche product names) can boost transcription accuracy.

### 3.10 Login Item opt-out at first launch

`registerAsLoginItemIfNeeded` registers Clicky as a login item on every launch where it isn't already registered. Some users find this presumptuous. Ask once during onboarding ("Start Clicky automatically when you log in?") and respect the answer.

---

## Sequencing summary

```
Phase 0 ── Tier 1 cleanups + FSD restructure + Testing infrastructure
            └─ items 1.1 through 1.10

Phase 1 ── Local-mode foundations + Tier 2.4 (PostHog privacy) + Tier 2.7 (TTS streaming)
            └─ items 2.4, 2.7 land alongside the new TTS / transcription primitives

Phase 2 ── Plugin kernel + Tier 2.6 (CompanionManager decomposition)
            └─ item 2.6 is the same as FSD step 4

Phase 3 ── User-authored plugins + Tier 2.1, 2.2 (history & provider runtime swap)
            └─ items 2.1, 2.2 unblock the mode-picker UX

Phase 4 ── Swoosh + heavy local models — no specific Tier 2 dependencies

Phase 5+ ── Tier 3 polish, opportunistically as relevant phases ship
```

## TL;DR

The audit surfaced 10 small cleanups, 9 behavior improvements, and 10 polish items. The cleanups (Tier 1) ship in Phase 0 alongside the FSD restructure and testing infrastructure — they're load-bearing for the rest of the roadmap. Tier 2 ships with tests. Tier 3 stays on the list so we don't forget about it. Nothing here is a feature you'd put on the homepage, but together they remove the rough edges visible in the audit.
