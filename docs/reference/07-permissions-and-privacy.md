# Permissions & Privacy

## macOS permissions

Clicky needs four permissions. The panel UI surfaces a Grant button for each until it's satisfied.

| Permission | API used to check | Why needed | Recoverable without app restart? |
|------------|-------------------|------------|----------------------------------|
| **Microphone** | `AVCaptureDevice.authorizationStatus(.audio)` | Capture voice for push-to-talk. | Yes — polled every 1.5 s in `CompanionManager.refreshAllPermissions`. |
| **Accessibility** | `AXIsProcessTrusted()` | The `CGEventTap` listens for the global `ctrl+option` shortcut. | Yes — `GlobalPushToTalkShortcutMonitor.start()` is re-invoked once permission is granted. |
| **Screen Recording** | `CGPreflightScreenCaptureAccess()` | ScreenCaptureKit screenshots. | macOS typically requires app restart after first grant. The app has a "previously confirmed" fallback (`UserDefaults`) to avoid re-prompting on false negatives. |
| **Screen Content** (ScreenCaptureKit picker grant) | A test `SCScreenshotManager.captureImage` call; the result image's `width > 0` and `height > 0` confirms approval. | Required by ScreenCaptureKit's picker dialog before any capture. | Once granted, the result is latched in `UserDefaults["hasScreenContentPermission"]` and never asked again. |

The strategy in `WindowPositionManager.permissionRequestPresentationDestination` is: first attempt presents the system prompt; subsequent attempts open System Settings, so the user never sees both at once.

Each successful grant fires a `permission_granted` PostHog event; the first time all four are granted, `all_permissions_granted` fires.

## Where API keys live

| Key | Storage |
|-----|---------|
| Anthropic API key | Cloudflare Worker secret (`ANTHROPIC_API_KEY`). Never in the app. |
| AssemblyAI API key | Cloudflare Worker secret (`ASSEMBLYAI_API_KEY`). The app receives a 480-second token instead. |
| ElevenLabs API key | Cloudflare Worker secret (`ELEVENLABS_API_KEY`). |
| ElevenLabs voice ID | Public `wrangler.toml` var (`ELEVENLABS_VOICE_ID`). Not sensitive. |
| PostHog API key | Hardcoded in `ClickyAnalytics.swift` (`phc_xcQPygm…`). PostHog write-only project keys are designed to be public. |
| OpenAI API key (optional) | Read from `Info.plist["OpenAIAPIKey"]`. Not configured by default in this repo. |

The app's `URLSessionConfiguration` for both Claude and OpenAI clients explicitly disables `urlCache` and `httpCookieStorage` so no response payloads or credentials are persisted to disk.

## What data leaves the device

| Sink | Data sent |
|------|-----------|
| Cloudflare Worker → Anthropic | Voice transcript text + JPEG screenshots of every connected display + up to 10 prior turns. |
| Cloudflare Worker → AssemblyAI | Live PCM16 16 kHz audio frames over websocket; the temp token fetch. |
| Cloudflare Worker → ElevenLabs | The plain-text response body from Claude (post-tag-strip). |
| FormSpark (`submit-form.com/RWbGJxmIs`) | The user's email at onboarding. |
| PostHog (`us.i.posthog.com`) | App lifecycle, onboarding, permission, push-to-talk, **full user transcript text**, **full AI response text**, element-label, errors. Distinct ID = the email submitted at onboarding. |
| Mux | HLS playback of the onboarding video (read-only). |

The app never directly contacts Anthropic / AssemblyAI / ElevenLabs — only the Worker does.

## What data stays on the device

| Where | What |
|-------|------|
| `UserDefaults` | `hasCompletedOnboarding`, `hasSubmittedEmail`, `hasScreenContentPermission`, `selectedClaudeModel`, `isClickyCursorEnabled`, `com.learningbuddy.hasPreviouslyConfirmedScreenRecordingPermission`. |
| In-memory only | `conversationHistory` (max 10 turns). Cleared on app quit. |
| Bundle resources | The Final Fantasy "Besaid" theme (`ff.mp3`), `enter.mp3`, `eshop.mp3`, `steve.jpg`, `codex-add-project.png`. |

## What's explicitly excluded from screenshots

`CompanionScreenCaptureUtility` builds the `SCContentFilter` with `excludingWindows = ownAppWindows`, where `ownAppWindows` is every window whose `owningApplication?.bundleIdentifier` matches Clicky's. So neither the menu-bar panel nor the cursor overlay ever appears in a screenshot sent to Claude.

## Microphone access lifecycle

- The first push-to-talk press triggers `AVCaptureDevice.requestAccess(.audio)` if status is `.notDetermined`.
- `BuddyDictationManager.requestMicrophoneAndSpeechPermissionsWithoutDuplicatePrompts` keeps a single in-flight permission task and skips re-requesting for 1 s after completion, so rapid press repeats don't pop the prompt twice.
- Once granted, the app does not hold the microphone open between turns — `AVAudioEngine.start/stop` brackets each press.

## Speech Recognition permission

Only the `AppleSpeechTranscriptionProvider` requires Speech Recognition permission (it's a third macOS prompt distinct from Microphone). The default AssemblyAI path does not need it. The `Info.plist` declares `NSSpeechRecognitionUsageDescription` so the prompt has the right text if/when it ever fires.

## What the Worker logs

The Worker has no logging beyond `console.error` for non-2xx upstream responses. There is no inbound auth — anyone who knows the URL can use the Worker. If you self-host, consider adding a shared-secret header or IP-based filtering before exposing it publicly.

## Removing PostHog if you fork

`ClickyAnalytics.configure()` is called unconditionally in `applicationDidFinishLaunching` (`leanring_buddyApp.swift:42`). To strip analytics:

1. Delete `ClickyAnalytics.swift`.
2. Remove the PostHog SPM dependency.
3. Replace every `ClickyAnalytics.track…` call with a no-op (or delete them).
4. Remove the `PostHogSDK.shared.identify(...)` call from `CompanionManager.submitEmail`.
