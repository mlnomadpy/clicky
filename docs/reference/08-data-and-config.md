# Data & Configuration

## `UserDefaults` keys

| Key | Type | Set by | Read by |
|-----|------|--------|---------|
| `hasCompletedOnboarding` | `Bool` | `CompanionManager.triggerOnboarding` | `CompanionManager` (gates panel UI + auto-show), `leanring_buddyApp` (panel auto-open on launch). |
| `hasSubmittedEmail` | `Bool` | `CompanionManager.submitEmail` | `CompanionPanelView` (hides email input once submitted). |
| `hasScreenContentPermission` | `Bool` | `CompanionManager.requestScreenContentPermission` | `CompanionManager.refreshAllPermissions`, panel UI. |
| `selectedClaudeModel` | `String` | `CompanionManager.setSelectedModel` | `CompanionManager` init (default `claude-sonnet-4-6`), `ClaudeAPI.model`. |
| `isClickyCursorEnabled` | `Bool` (defaults to `true` if absent) | `CompanionManager.setClickyCursorEnabled` | Overlay show/hide + transient-cursor mode. |
| `com.learningbuddy.hasPreviouslyConfirmedScreenRecordingPermission` | `Bool` | `WindowPositionManager.hasScreenRecordingPermission` (latches on first true) | `shouldTreatScreenRecordingPermissionAsGrantedForSessionLaunch` (false-negative fallback). |
| `NSInitialToolTipDelay` | `Int` (registered to `0`) | `applicationDidFinishLaunching` | macOS tooltip display delay. |

## `Info.plist` keys

| Key | Value | Purpose |
|-----|-------|---------|
| `LSUIElement` | `true` | Menu-bar-only app, no Dock icon. |
| `SUFeedURL` | `https://raw.githubusercontent.com/julianjear/makesomething-mac-app/main/appcast.xml` | Sparkle appcast feed. |
| `SUPublicEDKey` | `/l3d2rw5ZZFRU3AadP/w2Zf8FHfhA6bKv16BQOV5OSk=` | Sparkle EdDSA public key for signed update verification. |
| `VoiceTranscriptionProvider` | `assemblyai` | Picks transcription provider in `BuddyTranscriptionProviderFactory`. Values: `assemblyai`, `openai`, `apple`. |
| `NSMicrophoneUsageDescription` | "Clicky uses your microphone so you can talk to it" | Mic permission rationale. |
| `NSScreenCaptureUsageDescription` | "Clicky needs screen recording access to see your screen and help you." | Screen recording rationale. |
| `NSSpeechRecognitionUsageDescription` | "Clicky uses speech recognition to transcribe your voice when you talk to it" | Apple Speech rationale (only used when the Apple provider is active). |

Additional optional keys read at runtime via `AppBundleConfiguration.stringValue(forKey:)`:

- `OpenAIAPIKey` — enables `OpenAIAudioTranscriptionProvider.isConfigured`.
- `OpenAITranscriptionModel` — overrides default `gpt-4o-transcribe`.

## Entitlements (`leanring-buddy.entitlements`)

See [`06-build-and-release.md#entitlements-and-code-signing`](./06-build-and-release.md#entitlements-and-code-signing) for the full table. Summary: sandbox off, network client, mic, camera (declared but unused), ScreenCaptureKit picker exception.

## Bundled assets

| Asset | Size | Used where |
|-------|------|------------|
| `ff.mp3` | ~8 MB | Onboarding background music (`CompanionManager.startOnboardingMusic`). |
| `enter.mp3` | ~6 KB | UI sound (referenced from bundle by name; played as needed). |
| `eshop.mp3` | ~67 KB | UI sound. |
| `steve.jpg` | ~120 KB | Bundled image (referenced from panel UI). |
| `codex-add-project.png` | ~46 KB | Bundled image. |
| `Assets.xcassets/AppIcon.appiconset/` | various | App icon. |
| `Assets.xcassets/AccentColor.colorset/` | n/a | Accent color. |

## Worker config (`worker/wrangler.toml`)

```toml
name = "clicky-proxy"
main = "src/index.ts"
compatibility_date = "2024-01-01"

[vars]
ELEVENLABS_VOICE_ID = "kPzsL2i3teMYv0FxEYQ6"
```

Secrets are set via `wrangler secret put` (not in source).

## Hardcoded URLs

A short list of every URL hardcoded into the Swift sources — useful when forking.

| URL | File | Purpose |
|-----|------|---------|
| `https://your-worker-name.your-subdomain.workers.dev` (placeholder) | `CompanionManager.swift` (`workerBaseURL`), `AssemblyAIStreamingTranscriptionProvider.swift` (`tokenProxyURL`) | Worker base. Replace before shipping. |
| `https://submit-form.com/RWbGJxmIs` | `CompanionManager.swift` | FormSpark email collection. |
| `https://stream.mux.com/e5jB8UuSrtFABVnTHCR7k3sIsmcUHCyhtLu1tzqLlfs.m3u8` | `CompanionManager.swift` | Onboarding video. |
| `https://us.i.posthog.com` | `ClickyAnalytics.swift` | PostHog host. |
| `wss://streaming.assemblyai.com/v3/ws` | `AssemblyAIStreamingTranscriptionProvider.swift` | AssemblyAI websocket. |
| `https://api.openai.com/v1/audio/transcriptions` | `OpenAIAudioTranscriptionProvider.swift` | OpenAI transcription. |
| `https://api.openai.com/v1/chat/completions` | `OpenAIAPI.swift` | OpenAI vision (legacy, off the hot path). |
| `x-apple.systempreferences:com.apple.preference.security?Privacy_*` | `WindowPositionManager.swift`, `BuddyDictationManager.swift` | Deep links to System Settings panes. |

## System prompts

Two large constants live in `CompanionManager.swift`:

- `companionVoiceResponseSystemPrompt` — the main "you're clicky" prompt with the `[POINT:x,y:label:screenN]` protocol. Reproduced in [`03-features.md`](./03-features.md#5-claude-chat-with-vision-streaming).
- `onboardingDemoSystemPrompt` — the 40s onboarding-demo prompt. Constrains the model to pick something in the central 60% of the cursor screen and respond with ≤6 words.

If you change these, expect the AI's spoken cadence and pointing behavior to change noticeably. The "20%–80% bounds" rule in the onboarding prompt exists because models otherwise default to pointing at menu-bar items or dock icons, which look unimpressive in the demo.
