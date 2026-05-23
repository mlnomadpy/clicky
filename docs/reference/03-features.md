# Features

Each feature is described with: what it does, where it lives, and the key code paths.

## 1. Menu-bar status item & dropdown panel

- **What**: A small triangle icon in the macOS menu bar. Clicking it toggles a borderless, rounded floating panel below it.
- **Files**: `MenuBarPanelManager.swift`, `CompanionPanelView.swift`, `leanring_buddyApp.swift`.
- **Key paths**:
  - Icon drawn programmatically by `makeClickyMenuBarIcon()` — equilateral triangle rotated 35°, drawn into an `NSImage`.
  - Toggle behavior: `MenuBarPanelManager.statusItemClicked` → `showPanel` / `hidePanel`.
  - The panel is a `KeyablePanel : NSPanel` (subclass overrides `canBecomeKey = true` so the email `TextField` can focus).
  - Positioned beneath the status item via `positionPanelBelowStatusItem`, using the hosting view's `fittingSize` so the panel hugs its SwiftUI content.
  - Auto-dismisses on outside click via `NSEvent.addGlobalMonitorForEvents`, with a 300 ms delay so a system permission dialog (triggered by an in-panel Grant button) doesn't immediately dismiss the panel.
  - `NotificationCenter` channel `.clickyDismissPanel` lets any code (e.g. `CompanionManager.handleShortcutTransition(.pressed)`) close the panel.

## 2. Push-to-talk voice input

- **What**: Holding `Control + Option` records the user's voice. Releasing finalizes a transcript.
- **Files**: `GlobalPushToTalkShortcutMonitor.swift`, `BuddyDictationManager.swift`, `BuddyTranscriptionProvider.swift`, `AssemblyAIStreamingTranscriptionProvider.swift`, `OpenAIAudioTranscriptionProvider.swift`, `AppleSpeechTranscriptionProvider.swift`, `BuddyAudioConversionSupport.swift`.
- **Shortcut**: hardcoded to `.controlOption` in `BuddyPushToTalkShortcut.currentShortcutOption`. The enum supports `shiftFunction`, `controlOption`, `shiftControl`, `controlOptionSpace`, and `shiftControlSpace`, but only `.controlOption` is wired today.
- **Detection**: A `CGEventTap` at `.cgSessionEventTap` listens for `.flagsChanged` (modifier-only shortcuts) plus `.keyDown` / `.keyUp` (for space-based variants). Requires Accessibility permission. Re-enabled after `.tapDisabledByTimeout` / `.tapDisabledByUserInput`.
- **Permission debouncing**: `BuddyDictationManager.requestMicrophoneAndSpeechPermissionsWithoutDuplicatePrompts` keeps one in-flight permission task and skips re-requesting for 1 s after completion to avoid the system prompt re-popping on rapid presses.
- **Audio engine**: `AVAudioEngine.inputNode.installTap(bus: 0, bufferSize: 1024)`. Each buffer flows to the active provider and to `updateAudioPowerLevel` (RMS → smoothed `currentAudioPowerLevel` for the waveform).
- **Quick press protection**: `pendingKeyboardShortcutStartTask?.cancel()` on release prevents a quick-tap from leaving the waveform stuck if release outraces the async `startPushToTalk`.

## 3. Three transcription backends

Resolved by `BuddyTranscriptionProviderFactory.makeDefaultProvider()` based on the `VoiceTranscriptionProvider` Info.plist key. Today's `Info.plist` ships `assemblyai`.

### a) AssemblyAI (default, streaming)

- **File**: `AssemblyAIStreamingTranscriptionProvider.swift`.
- **Flow**:
  1. `POST /transcribe-token` on the Worker → returns a short-lived (480 s) JWT.
  2. Open `wss://streaming.assemblyai.com/v3/ws?sample_rate=16000&encoding=pcm_s16le&format_turns=true&speech_model=u3-rt-pro&token=…` (plus a `keyterms_prompt` array of contextual terms).
  3. Stream PCM16 16 kHz mono audio frames.
  4. On release, send `{"type":"ForceEndpoint"}`, wait up to 1.4 s grace for a formatted turn, then deliver.
  5. Always `{"type":"Terminate"}` and close.
- **Turn buffering**: stores formatted turn segments by `turn_order`, never downgrades a formatted turn to an unformatted one. Composes full transcript as `committedSegments + activeTurn`.
- **One shared `URLSession`** for all sessions (load-bearing — see [02-system-design.md](./02-system-design.md)).
- **Failure mode**: If the websocket errors *during* finalization with text already buffered, deliver the partial text rather than throwing.

### b) OpenAI (upload-based, fallback)

- **File**: `OpenAIAudioTranscriptionProvider.swift`.
- **Flow**: Buffer all PCM16 audio for the duration of the press. On release, wrap as WAV (`BuddyWAVFileBuilder`) and POST to `api.openai.com/v1/audio/transcriptions` as multipart with `model=gpt-4o-transcribe` (default) and a contextual `prompt`.
- **Configuration**: requires `OpenAIAPIKey` in Info.plist. Not configured by default in this repo.

### c) Apple Speech (local fallback)

- **File**: `AppleSpeechTranscriptionProvider.swift`.
- **Flow**: `SFSpeechAudioBufferRecognitionRequest` with `requiresOnDeviceRecognition = true` where supported. Streams partial results, marks `isFinal` on stop.
- **Requires** Speech Recognition permission (the only provider that does).

### Audio conversion

`BuddyPCM16AudioConverter` (in `BuddyAudioConversionSupport.swift`) lazily creates an `AVAudioConverter` per unique input format and converts to PCM16 16 kHz mono. `BuddyWAVFileBuilder.buildWAVData` synthesises a RIFF/WAVE header around the PCM16 buffer (44-byte header, little-endian).

### Contextual keyterms

`BuddyDictationManager.buildTranscriptionKeyterms()` always includes:

```
makesomething, Learning Buddy, Codex, Claude, Anthropic, OpenAI,
SwiftUI, Xcode, Vercel, Next.js, localhost
```

Plus anything `updateContextualKeyterms()` was called with (currently nothing). Deduped case-insensitively.

## 4. Multi-monitor screenshot capture

- **What**: Captures a JPEG of every connected display when the user releases push-to-talk.
- **File**: `CompanionScreenCaptureUtility.swift`.
- **API**: `ScreenCaptureKit` (`SCShareableContent`, `SCContentFilter`, `SCScreenshotManager.captureImage`). Requires macOS 14.2+.
- **Excludes our own windows** so the AI never sees the menu-bar panel or cursor overlay (`window.owningApplication?.bundleIdentifier == ownBundleIdentifier`).
- **Sort order**: cursor-containing display is always first in the returned array.
- **Sizing**: Long edge clamped to 1280 px, aspect preserved, JPEG at compression factor 0.8.
- **Labels** carried into the Claude prompt: e.g. `"screen 1 of 2 — cursor is on this screen (primary focus) (image dimensions: 1280x800 pixels)"`. The Claude system prompt teaches the model to point in *these* pixel coordinates.
- **Coordinate system fix**: maps `SCDisplay.displayID → NSScreen.frame` so `displayFrame` is in AppKit (bottom-left) coordinates, matching `NSEvent.mouseLocation` and the overlay's screen frame.

## 5. Claude chat with vision (streaming)

- **File**: `ClaudeAPI.swift`.
- **Models**: `claude-sonnet-4-6` (default) and `claude-opus-4-6`, picked in `CompanionPanelView`. Persisted in `UserDefaults["selectedClaudeModel"]` and propagated to `ClaudeAPI.model`.
- **Request**: SSE-streamed `POST` to the Worker's `/chat`. Body has `model`, `max_tokens: 1024`, `stream: true`, the system prompt, and a `messages` array of prior user/assistant turns followed by the new user message (which is a content-block array of `image` + `text(label)` for each screenshot, then a final `text(userPrompt)`).
- **MIME detection** (`detectImageMediaType`): inspects the first four bytes — `89 50 4E 47` ⇒ `image/png`, else `image/jpeg`. Pasted clipboard images would be PNG; ScreenCaptureKit output is JPEG. Anthropic rejects mismatched `media_type`.
- **SSE parse**: reads `byteStream.lines`, drops `data: ` prefix, dispatches `content_block_delta` → `text_delta` chunks to `onTextChunk`. Accumulates into `accumulatedResponseText` and returns at `[DONE]`.
- **TLS warmup**: a one-time HEAD request on the Worker host caches the TLS session ticket so the first real request with a large image payload doesn't pay a cold handshake (previously caused intermittent errSSL `-1200`).
- **Non-streaming fallback**: `analyzeImage` exists too (256-token cap) for validation use cases.

The system prompt (`CompanionManager.companionVoiceResponseSystemPrompt`) tells Claude to write for the ear, default to 1–2 sentences, never say "simply" or "just", reference what's on screen when relevant, and append `[POINT:x,y:label[:screenN]]` or `[POINT:none]` at the very end. There's a second, shorter prompt (`onboardingDemoSystemPrompt`) that asks for a 3–6 word observation about something near the centre of the cursor screen — used only during the onboarding demo at the 40-second mark.

## 6. ElevenLabs text-to-speech

- **File**: `ElevenLabsTTSClient.swift`.
- **Request**: `POST` to the Worker's `/tts` with `model_id: eleven_flash_v2_5`, `voice_settings: {stability: 0.5, similarity_boost: 0.75}`. Voice ID is configured server-side via the `ELEVENLABS_VOICE_ID` Worker var (currently `kPzsL2i3teMYv0FxEYQ6` in `worker/wrangler.toml`).
- **Playback**: full MP3 loaded into an `AVAudioPlayer`. Despite the file's top-of-file comment claiming streaming, `session.data(for:)` is used — playback begins as soon as the full response arrives, not while it streams.
- **`isPlaying`** is exposed so `CompanionManager.scheduleTransientHideIfNeeded` can wait for audio to finish before fading the cursor out.
- **Cancellation**: `stopPlayback()` is called whenever the user starts a new turn or cancels the current task.
- **Credits-exhausted fallback**: `CompanionManager.speakCreditsErrorFallback()` uses `NSSpeechSynthesizer` to say "I'm all out of credits. Please DM Farza and tell him to bring me back to life." when ElevenLabs fails.

## 7. Cursor overlay & blue triangle

- **What**: A blue triangle "cursor buddy" that follows the OS cursor and morphs into a waveform, spinner, or response-aware shape during voice interaction.
- **Files**: `OverlayWindow.swift`, `CompanionResponseOverlay.swift`, `DesignSystem.swift`.
- **Window**: one `OverlayWindow : NSWindow` per `NSScreen`. `.borderless`, transparent, `level = .screenSaver`, `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]`, `ignoresMouseEvents = true`, never key or main.
- **Per-screen view**: `BlueCursorView`. Each instance:
  - Reads `NSEvent.mouseLocation` on a 60 Hz `Timer`, decides whether the cursor is on *this* screen, and only renders the triangle if so.
  - During voice interaction the triangle is replaced by `BlueCursorWaveformView` (5 audio-reactive bars driven by `companionManager.currentAudioPowerLevel`), `BlueCursorSpinnerView` (spinning trimmed circle), or a streaming response text bubble (currently disabled — the spinner stays until TTS plays).
  - Animates a bezier-arc flight to `detectedElementScreenLocation` with `buddyFlightScale` swooping to ~1.3× at the midpoint, rotates to face the direction of travel, then pops a 1–3-word `navigationBubbleText` speech bubble that cancels if the user moves the cursor enough on the return flight.
- **First-appearance** gates the welcome bubble (`hey! i'm clicky`), the onboarding video, the onboarding demo at 40s, and the prompt stream after the video ends. Controlled by `OverlayWindowManager.hasShownOverlayBefore`.
- **Fade out**: `OverlayWindowManager.fadeOutAndHideOverlay(duration: 0.4)` uses `NSAnimationContext` to ease the windows' alpha to 0 and removes them.

## 8. Element pointing protocol

- **Protocol**: Claude appends `[POINT:x,y:label]` or `[POINT:x,y:label:screenN]` or `[POINT:none]` at the very end of its response. Coordinates are in screenshot pixels (top-left origin), in the dimensions the image was sent at.
- **Parser**: `CompanionManager.parsePointingCoordinates`. Regex: `\[POINT:(?:none|(\d+)\s*,\s*(\d+)(?::([^\]:\s][^\]:]*?))?(?::screen(\d+))?)\]\s*$`. Returns spoken text (tag stripped), optional `CGPoint`, optional label, optional screen number.
- **Targeting**: If `screenN` is set, that screen's capture is used; otherwise the cursor screen. Coordinate is clamped, scaled to display points, flipped to AppKit Y, translated by display origin → published as `detectedElementScreenLocation` + `detectedElementDisplayFrame`. (See [02-system-design.md#coordinate-math](./02-system-design.md#coordinate-math).)
- **Animation**: `BlueCursorView` watches the published location, switches `BuddyNavigationMode` to `.navigatingToTarget`, runs a bezier flight, pops the speech bubble at landing, then returns to `.followingCursor` after a delay (or instantly if the user moves the cursor).

## 9. Transient cursor mode

When the user toggles "Show Clicky" off (`isClickyCursorEnabled = false`, persisted to `UserDefaults`):

- The overlay is hidden by default.
- On hotkey press, the overlay is shown (`overlayWindowManager.showOverlay`) and any pending transient-hide is cancelled.
- After the turn completes (response done, TTS finished, pointing landed) and 1s of inactivity, the overlay fades out (`scheduleTransientHideIfNeeded`).
- A second hotkey press during the transient period cancels the hide.

(The UI to toggle this is currently commented out in `CompanionPanelView` — the toggle path is wired but hidden.)

## 10. Conversation memory

- **File**: `CompanionManager.swift`, `conversationHistory` array.
- **Behavior**: Up to the last 10 user/assistant exchanges are kept in memory and sent verbatim with every new turn. The `[POINT:...]` tag is stripped from the saved assistant message so future Claude calls don't see stale coordinates.
- **Persistence**: in-memory only. Restarting the app clears history.

## 11. Onboarding sequence

- **State**: `hasCompletedOnboarding` and `hasSubmittedEmail` in `UserDefaults`.
- **Flow**: See [02-system-design.md#onboarding-flow](./02-system-design.md#onboarding-flow).
- **Pieces**:
  - Email submitted to FormSpark (`https://submit-form.com/RWbGJxmIs`) and identifies the user in PostHog (`CompanionManager.submitEmail`).
  - 90-second background music: `ff.mp3` (bundled, ~8 MB) played at 30% volume, fades out over 3 s starting at the 90 s mark.
  - HLS video on Mux (`https://stream.mux.com/e5jB8UuSrtFABVnTHCR7k3sIsmcUHCyhtLu1tzqLlfs.m3u8`) rendered via `OnboardingVideoPlayerView` (an `AVPlayerLayer` wrapped in `NSViewRepresentable`).
  - 40s boundary observer → `performOnboardingDemoInteraction()` (separate prompt; only the cursor screen is sent so Claude can't pick a target on a different monitor).
  - Post-video character-by-character prompt stream (`startOnboardingPromptStream`) → `"press control + option and introduce yourself"`.
- **Replay**: panel footer link calls `replayOnboarding()`.

## 12. Model picker

- `CompanionPanelView.modelPickerRow` renders two pill buttons: Sonnet (default) and Opus.
- Switches via `companionManager.setSelectedModel(_:)`, which writes to `UserDefaults["selectedClaudeModel"]` and updates `claudeAPI.model` for the next turn.

## 13. Permissions gating

- **File**: `WindowPositionManager.swift` (the static utilities), `CompanionManager.swift` (the live state).
- **Four permissions tracked**: Accessibility (`AXIsProcessTrusted`), Screen Recording (`CGPreflightScreenCaptureAccess`), Microphone (`AVCaptureDevice.audio`), Screen Content (latched in `UserDefaults["hasScreenContentPermission"]` once the user accepts the ScreenCaptureKit picker — see `requestScreenContentPermission()`).
- **Re-prompt strategy**: `WindowPositionManager.permissionRequestPresentationDestination` returns `.systemPrompt` once per app launch, then `.systemSettings` so the OS prompt and Settings pane never appear together.
- Polled every 1.5 s by `accessibilityCheckTimer`.

## 14. Sparkle auto-update (wired but disabled)

- **Configuration**:
  - `SUFeedURL = https://raw.githubusercontent.com/julianjear/makesomething-mac-app/main/appcast.xml`
  - `SUPublicEDKey = /l3d2rw5ZZFRU3AadP/w2Zf8FHfhA6bKv16BQOV5OSk=`
  - Sparkle SPM dependency imported in `leanring_buddyApp.swift`.
- **Status**: `startSparkleUpdater()` exists but is commented out in `applicationDidFinishLaunching` (`leanring_buddyApp.swift:53`). Uncommenting it re-enables update checks.
- **Appcast generation** is automated by `scripts/release.sh`.

## 15. Analytics

- **File**: `ClickyAnalytics.swift`. Wraps `PostHogSDK.shared` (api key hardcoded; `us.i.posthog.com`).
- **Events**: `app_opened`, `onboarding_started`, `onboarding_replayed`, `onboarding_video_completed`, `onboarding_demo_triggered`, `permission_granted` (with name), `all_permissions_granted`, `push_to_talk_started`, `push_to_talk_released`, `user_message_sent` (full transcript), `ai_response_received` (full response text), `element_pointed` (label), `response_error`, `tts_error`.
- **PII**: the email submitted at onboarding becomes the PostHog distinct ID via `PostHogSDK.identify(...)`.

## 16. Login item

- `SMAppService.mainApp.register()` is called once on first launch (`CompanionAppDelegate.registerAsLoginItemIfNeeded`). After that the system shows Clicky in System Settings > Login Items where the user can disable it.

## 17. Window helpers (`WindowPositionManager`)

Today this file is mostly used for its static permission utilities. It also contains:

- `pinMainWindowToRight(onDisplayID:)` — pins the (currently non-existent) main window to the right edge.
- `shrinkOverlappingFocusedWindow(targetDisplayID:)` — uses Accessibility API to resize the frontmost non-Clicky window so it doesn't overlap our main window.

These are legacy helpers from when the app had a docked main window. They aren't called from the active code paths today but are kept available.
