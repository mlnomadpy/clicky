# Tier-3 Polish — Mini-specs

> **Status**: design doc / RFC. Companion to `15-feature-improvements.md` §Tier 3. Each section here is a one-page spec for a polish item that's small enough to land in a single PR but big enough to need agreement on the shape before coding.

The Tier-3 backlog in `15-feature-improvements.md` lists 10 items. This doc specs the four that have the best impact-per-LOC ratio. The other six stay in the backlog list until someone picks them up.

---

## 16.1 — Panic clear

**Goal**: a single button in the panel that wipes any in-flight Clicky state — for demos, screenshares, or "I don't want this on screen right now" moments.

### Behavior

One button labeled **Clear everything**. Hidden under a small ⋯ menu in the panel header (not a prominent button — only power users need this).

Clicking it, in order, with no confirmation prompt:

1. Cancel `currentResponseTask` if it's running (interrupts the Claude streaming call mid-flight).
2. Call `elevenLabsTTSClient.stopPlayback()`.
3. Clear `conversationHistory` (sets the array to `[]`).
4. Clear `lastTranscript`, `detectedElementScreenLocation`, `detectedElementDisplayFrame`, `detectedElementBubbleText`.
5. If overlay is visible, call `overlayWindowManager.fadeOutAndHideOverlay(duration: 0.2)`.
6. Reset `voiceState` to `.idle`.
7. When `VectorMemory/` (spec 12) ships: also delete every row from `conversation_turns` (and the vec table) — full forget.
8. Briefly flash a small "cleared" toast in the panel.

Persistent state stays untouched: `hasCompletedOnboarding`, `hasSubmittedEmail`, model selection, mode, login-item registration. Permissions stay granted.

### UI

In the panel header, next to the existing X button:

```
┌─────────────────────────────────────────────┐
│  ●  Clicky                 Active     ⋯  X  │
└─────────────────────────────────────────────┘
                                       ▲
                          on hover: tooltip "Options"
                          on click:  small popover with:
                                       • Clear everything
                                       • (future Tier-3 entries land here too)
```

The popover is itself an `NSPanel` (same pattern as the dropdown). Auto-dismisses on outside click.

### Privacy implications

This is the *only* button in the app that destroys conversation history. The vector-memory deletion is the irreversible part — and once `12` ships with screen memory, the same button must also offer a separate **Forget the last hour** option that wipes screen-memory rows where `timestamp > now - 1h`. Spec 12 already mentions this; this entry is what physically wires it up.

### Estimated LOC

- New file `Features/MenuBarPanel/Components/PanelOptionsMenu.swift` (~80 LOC)
- One method `clearEverything()` on `CompanionManager` or a new coordinator (~30 LOC)
- Two short tests for `clearEverything` (~50 LOC)

### Phase

After `Plugins/` Phase P0 lands — the FSD structure should exist so `Features/MenuBarPanel/Components/` is a real folder.

---

## 16.2 — "DM Farza" in-app feedback form

**Goal**: replace the external Twitter link with an in-app form that POSTs to a Worker route. Higher conversion, lower friction for users without Twitter, and the feedback ends up somewhere queryable (vs scattered DMs).

### Current state

`CompanionPanelView.swift` has a "DM Farza" row that opens `https://x.com/farzatv` in the browser. Users without Twitter give up.

### New behavior

The "DM Farza" row stays, but clicking it opens a small input sheet inside the panel:

```
┌─────────────────────────────────────────────┐
│  Tell Farza something                    X  │
│                                             │
│  ┌─────────────────────────────────────┐    │
│  │ what's working, what isn't, ideas…  │    │
│  │                                     │    │
│  │                                     │    │
│  └─────────────────────────────────────┘    │
│                                             │
│  Reply to: tahabhs14@gmail.com  (edit)      │
│                                             │
│  [  Send  ]                                 │
└─────────────────────────────────────────────┘
```

- Multi-line text field, ~140-char soft target but no hard limit.
- Pre-fills the email submitted at onboarding (`hasSubmittedEmail`-stored). User can override.
- A *Send* button POSTs to a new Worker route.
- After send: a 2s "thanks!" toast, then back to the panel.

### Worker route

Add a fourth route to `worker/src/index.ts`:

```
POST /feedback
   Forwards to: Discord webhook URL (Worker secret: FEEDBACK_WEBHOOK_URL)
   Body: { message: string, replyTo?: string, appVersion: string, mode: string }
   Forwards as: { content: "[<mode>] <message>\nreply: <replyTo>\nv<appVersion>" }
```

Discord webhook is simplest for the receiving end (Farza). Alternatives: a Linear ticket via API, a Notion DB row, a Cloudflare KV write. Webhook is least infrastructure. Worker secret named `FEEDBACK_WEBHOOK_URL`.

### Privacy

- The form's body is plain text from the user. We do NOT include screenshots, transcripts, conversation history, or the user's IP (Cloudflare can't avoid logging the IP at the edge, but the Worker never reads it).
- `appVersion` and `mode` (Cloud / Hybrid / Local) are included for triage.
- Submit logs an `in_app_feedback_sent` PostHog event with `{ has_email, message_length }` — never the message text itself.

### Estimated LOC

- One new SwiftUI view `Features/MenuBarPanel/Components/FeedbackForm.swift` (~120 LOC)
- One method on a feedback client (`Shared/Feedback/FeedbackClient.swift`) (~40 LOC)
- One new Worker route + tests (~50 LOC TS + tests)
- Wire-up in the panel: replace `URL("https://x.com/farzatv")` with the sheet open call

### Phase

Anytime after Phase 1 (Local-mode foundations) lands. Independent of plugins and Swoosh.

---

## 16.3 — Live latency metric in the panel

**Goal**: a tiny "last 10 turns: avg 2.4 s" readout in the panel footer that helps users see whether their mode (Cloud / Hybrid / Local) is actually faster for them. Drives mode-picker adoption.

### What gets measured

Each completed voice turn measures **time from `voiceState = .processing` to `voiceState = .responding`**. That is: from "user released hotkey" to "TTS audio starts playing." It includes:

- Final transcript fetch
- Screen capture
- Claude (or local LLM) round-trip
- TTS generation + first audio byte

It excludes the user's speaking time itself (since that's user-driven).

### Storage

A ring buffer of the last 10 turn-latencies (Doubles, seconds) on `CompanionManager`. In-memory only — restarts reset the average. Per-mode tracking would be nice but doubles complexity; keep it flat.

### UI

A new row in the panel footer, only visible when `hasCompletedOnboarding && allPermissionsGranted`:

```
                       ⏱ avg 2.4s · last 10 turns
```

Small font (size 10), `DS.Colors.textTertiary`. Tooltip on hover: *"Average time from when you stopped speaking to when Clicky started replying. Local mode is typically faster after warmup."*

Updates after every turn.

### When the buffer is empty

Show nothing — don't render the row until at least one turn completes. No "n/a" placeholders.

### Estimated LOC

- ~30 LOC on `CompanionManager` (the ring buffer + the time-stamping in `bindVoiceStateObservation`)
- ~20 LOC in `Features/MenuBarPanel/Components/FooterSection.swift` (the row)
- One unit test for the ring buffer eviction (~40 LOC)

### Phase

Independent. Could ship in Phase 0 polish, but Phase 1 is a better home (mode picker is when users care about latency).

---

## 16.4 — Login-item opt-in at first launch

**Goal**: stop auto-registering Clicky as a login item on every launch. Ask once, respect the answer, never ask again. This is one of the few items in the audit that's an outright user-respect issue, not just polish.

### Current behavior

`CompanionAppDelegate.registerAsLoginItemIfNeeded()` calls `SMAppService.mainApp.register()` on every launch where the service isn't already enabled. Users who manually disabled the login item in System Settings get re-registered on the next launch.

### New behavior

Add `UserDefaults["loginItemPromptShown"]` (Bool, default `false`).

On launch:

```swift
if !UserDefaults.standard.bool(forKey: "loginItemPromptShown") {
    // First time we ever asked — show the panel with an extra "Start at login?" row.
    // No system-level registration yet.
} else if UserDefaults.standard.bool(forKey: "loginItemEnabled") {
    SMAppService.mainApp.register()   // user opted in; ensure registered
} else {
    SMAppService.mainApp.unregister() // user opted out; ensure unregistered
}
```

The first-time prompt lives in the onboarding panel as a new row:

```
☑ Start Clicky automatically when you log in
   (you can change this in System Settings)
```

Default checked. The user can uncheck before clicking the *Start* button. Whatever the state is when they click *Start*, that's stored in `UserDefaults["loginItemEnabled"]` and `loginItemPromptShown` flips to `true`.

After that, we never re-register without consent. If the user manually toggles the login item in System Settings, we don't override.

### Estimated LOC

- ~25 LOC in `CompanionAppDelegate` and `CompanionManager` (logic + UserDefaults)
- ~15 LOC of new UI in `Features/Onboarding/OnboardingFlow.swift`
- One unit test of the launch-time decision tree (~40 LOC)

### Phase

Phase 0 polish — small, low-risk, ships independently.

---

## 16.5 — Backlog (specs deferred)

Other items from `15-feature-improvements.md` §Tier 3 that don't yet have specs:

| Item | Why deferred |
|------|--------------|
| Bundle the onboarding video locally | DMG-size trade-off needs a Farza decision before specing |
| Apple Personal Voice TTS opt-in | Apple's API for Personal Voice in `AVSpeechSynthesizer` is fiddly enough that the spec needs prototyping first |
| Better failure-mode for credits exhausted | One-line fix once we switch from `NSSpeechSynthesizer` to `AVSpeechSynthesizer` — defer until Local mode's TTS path lands |
| First-class multi-display flight starting point | Edge case; revisit after telemetry shows how often Claude points across screens |
| Surface AssemblyAI keyterms editing | Niche; wait for users to ask |
| Onboarding "no email needed" path | Has product implications (FormSpark capture rate) — needs Farza |

These can be promoted into their own mini-specs as priority shifts.

---

## TL;DR

Four small specs land four polish items: panic clear, in-app feedback form, latency readout, login-item opt-in. None of them is big enough to need its own multi-doc treatment. None of them blocks any other spec. Pick the lowest-LOC one (16.4) for the first Tier-3 PR after Phase 0 ships.
