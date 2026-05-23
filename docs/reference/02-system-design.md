# System Design

## High-level shape

```
┌──────────────── macOS process ─────────────────┐
│                                                │
│  leanring_buddyApp        @main entry point    │
│         │                                      │
│         ▼                                      │
│  CompanionAppDelegate                          │
│    ├─ MenuBarPanelManager   (NSStatusItem +    │
│    │     │                   borderless NSPanel)│
│    │     └─ CompanionPanelView (SwiftUI)       │
│    │                                            │
│    └─ CompanionManager     (central state)     │
│         ├─ BuddyDictationManager               │
│         │     └─ BuddyTranscriptionProvider    │
│         │         ├─ AssemblyAIStreaming…      │
│         │         ├─ OpenAIAudio…              │
│         │         └─ AppleSpeech…              │
│         ├─ GlobalPushToTalkShortcutMonitor     │
│         │     (CGEvent tap, listen-only)       │
│         ├─ ClaudeAPI       (SSE streaming)     │
│         ├─ ElevenLabsTTSClient                 │
│         ├─ CompanionScreenCaptureUtility       │
│         │     (ScreenCaptureKit, multi-monitor)│
│         └─ OverlayWindowManager                │
│               └─ OverlayWindow × N screens     │
│                   └─ BlueCursorView (SwiftUI)  │
│                                                │
└──────────────────┬──────────────────┬──────────┘
                   │ HTTPS            │ WebSocket
                   ▼                  ▼
       ┌──────────────────────────────────────┐
       │  Cloudflare Worker (clicky-proxy)    │
       │   /chat              → Anthropic     │
       │   /tts               → ElevenLabs    │
       │   /transcribe-token  → AssemblyAI    │
       └──────────────────────────────────────┘
```

## State ownership

| Owner | State |
|-------|-------|
| `CompanionManager` (the single `@StateObject`) | Voice state machine, conversation history, model selection, all overlay/cursor flags, permission flags, onboarding flags, transient-hide scheduling, detected element location. |
| `BuddyDictationManager` | Audio engine session, active transcription session, latest recognized text, audio-power waveform history, microphone/speech permission state. |
| `GlobalPushToTalkShortcutMonitor` | The `CGEventTap` machine port + `isShortcutCurrentlyPressed`. Published so the overlay reacts immediately on release. |
| `OverlayWindowManager` | The list of `OverlayWindow`s and a `hasShownOverlayBefore` flag that gates the first-time welcome bubble. |
| `MenuBarPanelManager` | The `NSStatusItem` and the borderless `NSPanel` with its outside-click monitor. |

There is exactly one `CompanionManager` for the process. It's created on the `CompanionAppDelegate` (`leanring_buddyApp.swift:33`) and passed into the panel manager.

## The voice-state machine

`CompanionVoiceState` is one of `idle`, `listening`, `processing`, `responding`. The transitions are driven by Combine subscriptions on `BuddyDictationManager`'s `@Published` flags, set up in `CompanionManager.bindVoiceStateObservation()`:

```
                  press hotkey
        idle ─────────────────► listening
         ▲                          │ release hotkey
         │                          ▼
         │                       processing  (spinner shown; screenshot + Claude in flight)
         │                          │ TTS audio actually begins playing
         │                          ▼
         │                       responding
         │  TTS finishes,           │
         └──────────────────────────┘
```

The `.responding` state is *not* set from the dictation flags — it's set inside `sendTranscriptToClaudeWithScreenshot()` only after `elevenLabsTTSClient.speakText` returns (which it does once `player.play()` has been called). This is intentional: the spinner stays visible until audio actually starts, so there's no awkward silent gap.

If Claude returned point coordinates, the state briefly switches to `.idle` *before* the location is set, so the triangle becomes visible and can be animated to the target (`CompanionManager.swift:634`).

## End-to-end voice turn (the hot path)

`CompanionManager.handleShortcutTransition` is the entry point. The full sequence:

1. **Press detected** by `GlobalPushToTalkShortcutMonitor` (its `CGEventTap` runs on the main run loop; modifier changes match `[.control, .option]`).
2. **Pre-flight cleanup** in `handleShortcutTransition(.pressed)`: cancel any pending transient-hide, ensure the overlay is on-screen (transient mode brings it back), dismiss the menu-bar panel (`NotificationCenter clickyDismissPanel`), cancel the previous in-flight Claude task and TTS playback, clear the previous pointing target, dismiss the onboarding prompt if showing.
3. **Permission check + audio engine start** via `BuddyDictationManager.startPushToTalkFromKeyboardShortcut`. It debounces duplicate requests, then opens a `BuddyTranscriptionProvider` session and installs a tap on the audio engine input node.
4. **Audio streaming.** Each PCM buffer is converted to PCM16 16 kHz mono by `BuddyPCM16AudioConverter` and pushed into the provider. RMS audio levels also feed `currentAudioPowerLevel` so the waveform animates.
5. **Release detected.** The monitor publishes `.released`; `handleShortcutTransition(.released)` calls `buddyDictationManager.stopPushToTalkFromKeyboardShortcut()`. The provider gets a `ForceEndpoint` (AssemblyAI) or `endAudio` (Apple Speech) or an upload (OpenAI). A fallback timer triggers transcript delivery if the provider doesn't deliver one within `finalTranscriptFallbackDelaySeconds` (2.8s for AssemblyAI, 1.8s for Apple, 8s for OpenAI).
6. **Final transcript** arrives via the `submitDraftText` callback, which routes to `CompanionManager.sendTranscriptToClaudeWithScreenshot`.
7. **Screenshot all displays** via `CompanionScreenCaptureUtility.captureAllScreensAsJPEG()` (excludes this app's own windows). Each capture carries its pixel dimensions, the display point dimensions, and its display frame.
8. **Claude request.** `ClaudeAPI.analyzeImageStreaming` POSTs to `/chat` on the Worker. The Worker proxies to `api.anthropic.com/v1/messages` with `stream: true`. The body includes the system prompt (the long "you're clicky" one in `CompanionManager.companionVoiceResponseSystemPrompt`), the last ≤10 turns, all labeled images, and the new prompt. SSE chunks are accumulated.
9. **Parse `[POINT:x,y:label:screenN]`.** `parsePointingCoordinates` strips the tag from the spoken text and returns an optional `CGPoint` + element label + screen number. The tag pattern is `[POINT:(none|x,y[:label][:screenN])]\s*$` (must be at the end).
10. **Coordinate conversion.** If a point exists, the screenshot-pixel coordinate is scaled to the display's point space and converted from top-left origin (image) to bottom-left origin (AppKit), then offset by the display's global origin. The result is published to `detectedElementScreenLocation` + `detectedElementDisplayFrame`. `BlueCursorView` watches these and runs the bezier-arc flight animation.
11. **TTS.** `ElevenLabsTTSClient.speakText` POSTs to `/tts`. The Worker proxies to `api.elevenlabs.io/v1/text-to-speech/{voiceId}` with `eleven_flash_v2_5`. The full MP3 is loaded into an `AVAudioPlayer` and played. (Despite the file comment claiming "streaming," the client awaits the full data buffer — see file note.)
12. **Save exchange.** The exchange (without the tag) is appended to `conversationHistory`. Old entries past 10 are trimmed.
13. **Cleanup.** State returns to `.idle`. If the cursor is in transient mode, `scheduleTransientHideIfNeeded` waits for TTS and the pointing animation to finish, then fades out the overlay after 1s.

## Coordinate math

Three coordinate systems are in play:

| System | Origin | Used by |
|--------|--------|---------|
| Screenshot pixels | Top-left | The `[POINT:x,y]` tag from Claude; image dimensions are passed in the image label. |
| Display points (AppKit) | Bottom-left | `NSScreen.frame`, `NSEvent.mouseLocation`, `OverlayWindow` frames. |
| Core Graphics display | Top-left | `SCDisplay.frame`. Diverges from AppKit on multi-monitor setups. |

The conversion lives in two near-identical blocks: the production path in `CompanionManager.sendTranscriptToClaudeWithScreenshot` (around line 663) and the onboarding-demo path in `performOnboardingDemoInteraction` (around line 1005):

```swift
let clampedX = max(0, min(pointX, screenshotW))
let clampedY = max(0, min(pointY, screenshotH))
let displayLocalX = clampedX * (displayW / screenshotW)
let displayLocalY = clampedY * (displayH / screenshotH)
let appKitY      = displayH - displayLocalY                     // flip origin
let globalX      = displayLocalX + displayFrame.origin.x
let globalY      = appKitY      + displayFrame.origin.y
```

`CompanionScreenCaptureUtility` is careful to map `SCDisplay.displayID → NSScreen` so it always reports `displayFrame` in AppKit coordinates. Without this, the cursor would point at the wrong pixel on secondary monitors.

## Why three windows live in `NSPanel`s, not `NSWindow`s

Both the menu-bar dropdown and the per-screen cursor overlay use `NSPanel` with `.nonactivatingPanel`. That keeps them from stealing focus from the user's current app. The overlay further uses `level = .screenSaver`, `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]`, and `ignoresMouseEvents = true` so it floats above everything and is fully click-through.

The menu-bar panel subclasses `NSPanel` (`KeyablePanel`) to override `canBecomeKey = true` — without that, text fields inside (email input during onboarding) can't receive focus.

## Why a listen-only CGEvent tap, not `NSEvent.addGlobalMonitorForEvents`

`GlobalPushToTalkShortcutMonitor` uses a `CGEventTap` at `.cgSessionEventTap` / `.headInsertEventTap` / `.listenOnly`. Modifier-only shortcuts (`ctrl + option`) are detected via `flagsChanged`. Global `NSEvent` monitors miss flag-change events while the app is in the background, which would make the hotkey unreliable — the whole point of the app is responding while another app is foreground.

The tap requires Accessibility permission. If it's revoked, `CompanionManager.refreshAllPermissions` stops the monitor; the permission poll (every 1.5s) restarts it when the user grants permission again.

## URLSession lifetimes

- `ClaudeAPI` and `OpenAIAPI` each create their own `URLSessionConfiguration.default`-backed session and **fire a HEAD request to the host on init** to warm the TLS handshake. This pre-caches a session ticket so the first real request (carrying a base64'd JPEG) doesn't pay a cold handshake — without warmup, large image payloads were intermittently failing with errSSL `-1200`.
- `AssemblyAIStreamingTranscriptionProvider` keeps a single long-lived `URLSession` shared across every streaming session. Per-session `URLSession`s were observed to corrupt the OS connection pool after a few rapid reconnections, producing "Socket is not connected" failures.
- `ElevenLabsTTSClient` uses its own session with 30/60s timeouts.

## Permissions polling

`CompanionManager.startPermissionPolling()` runs a 1.5s `Timer.scheduledTimer` that calls `refreshAllPermissions()`. This polls Accessibility (`AXIsProcessTrusted`), Screen Recording (`CGPreflightScreenCaptureAccess`), and Microphone (`AVCaptureDevice.authorizationStatus(.audio)`). Screen Content (ScreenCaptureKit's `SCShareableContent` picker grant) is tracked separately in `UserDefaults` because once granted it stays granted and isn't worth polling.

Granting state changes trigger PostHog events (`permission_granted`, `all_permissions_granted`).

## Onboarding flow

State variables: `hasCompletedOnboarding`, `hasSubmittedEmail`, both in `UserDefaults`.

1. Panel opens on launch if either onboarding or permissions are incomplete (`leanring_buddyApp.swift:49`).
2. User grants four permissions (mic, accessibility, screen recording, screen content) — the panel renders each as a Grant button until satisfied.
3. User types an email → `submitEmail()` identifies them in PostHog and POSTs to FormSpark (`https://submit-form.com/RWbGJxmIs`).
4. User clicks **Start** → `triggerOnboarding()`:
   - Dismisses the panel.
   - Sets `hasCompletedOnboarding = true`.
   - Plays `ff.mp3` (Final Fantasy "Besaid" theme) at 30% volume; fades out after 90s.
   - Shows the cursor overlay with the welcome bubble (`hey! i'm clicky`).
5. `BlueCursorView` on the cursor screen calls `companionManager.setupOnboardingVideo()`, which loads a Mux HLS stream (`https://stream.mux.com/...`) into an `AVPlayer` and renders it inside the overlay.
6. At the 40s mark, a boundary time observer triggers `performOnboardingDemoInteraction()` — Clicky takes a screenshot, asks Claude (with a different, "find something interesting in the center" prompt) for one thing to point at, and runs the same coordinate→flight animation as a regular pointing turn.
7. When the video ends, `startOnboardingPromptStream()` types out "press control + option and introduce yourself" character-by-character on the cursor for 10 seconds.

The "Watch Onboarding Again" footer button calls `replayOnboarding()`, which re-runs the same sequence with `hasShownOverlayBefore = false` so the welcome animation fires again.

## Auto-update (Sparkle)

Sparkle is imported and `SPUStandardUpdaterController` is created in `CompanionAppDelegate.startSparkleUpdater()`. **Note**: this function is currently commented out at the call site (`leanring_buddyApp.swift:53`). The `SUFeedURL` (`appcast.xml` on a separate repo) and `SUPublicEDKey` are wired in `Info.plist` and the release script signs the DMG with the corresponding EdDSA key, so re-enabling the updater is a one-line change.

## Login item

`SMAppService.mainApp.register()` registers Clicky as a login item on first launch (`CompanionAppDelegate.registerAsLoginItemIfNeeded`). User can opt out in System Settings > Login Items.
