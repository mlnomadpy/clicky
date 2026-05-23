# Overview

## What Clicky is

Clicky is a macOS menu-bar companion app. It lives entirely in the status bar (no Dock icon, no main window — `LSUIElement=true` in `Info.plist`). The user holds a push-to-talk shortcut, talks to the app, and Clicky:

1. Streams their voice to a transcription provider.
2. Captures a screenshot of every connected display.
3. Sends the transcript + screenshots to Claude (vision + streaming).
4. Speaks Claude's reply via ElevenLabs TTS.
5. Optionally flies a blue triangle cursor across the screen(s) to point at a specific UI element Claude referenced.

No API key ships in the binary — everything routes through a Cloudflare Worker proxy.

## User-visible surface

There are exactly two windows in the app:

1. **The menu-bar panel** (`MenuBarPanelManager.swift` + `CompanionPanelView.swift`). Borderless `NSPanel` that drops down beneath the status item. Shows onboarding state, permissions UI, model picker (Sonnet/Opus), "Watch Onboarding Again", and quit.
2. **The cursor overlay** (`OverlayWindow.swift`). One full-screen transparent `NSPanel` per connected display. Hosts the blue triangle cursor, waveform/spinner replacement during voice interaction, and the "speech bubble" when pointing at an element. Click-through (`ignoresMouseEvents = true`).

There is no main window, no preferences window, no app menu.

## What the user does

| Action | What happens |
|--------|--------------|
| Launch the app | Status item appears in the menu bar. Panel auto-opens if onboarding incomplete or permissions missing (`leanring_buddyApp.swift:49`). |
| Click the status item | Panel toggles open/closed (`MenuBarPanelManager.statusItemClicked`). |
| First launch — submit email + click Start | Email goes to FormSpark + identifies user in PostHog (`CompanionManager.submitEmail`). Onboarding video plays full-screen on the overlay, with a demo "point at something" interaction at the 40s mark. |
| Hold `Control` + `Option` | Cursor turns into a waveform. Audio streams to AssemblyAI. |
| Release `Control` + `Option` | Final transcript is fetched, screenshot taken, sent to Claude. Cursor turns into a spinner. When TTS audio begins, the response is spoken. If Claude returned a `[POINT:x,y:label]` tag, the cursor flies along a bezier arc to the target and shows a one-phrase speech bubble. |
| Press the hotkey again mid-response | Previous response and TTS are cancelled (`currentResponseTask?.cancel()`, `elevenLabsTTSClient.stopPlayback()`), new turn begins immediately. |
| Toggle "Show Clicky" off | Overlay hides. Push-to-talk still works — when pressed, the overlay fades in transiently for that one interaction, then fades back out 1s after the reply ends (`scheduleTransientHideIfNeeded`). |

## Conversation model

Up to the last 10 user/assistant exchanges are kept in memory in `CompanionManager.conversationHistory` and sent with each turn so Claude has context. History is in-memory only — it does not persist across app launches. The `[POINT:...]` tag is stripped before storing.

## Models

The user picks between two Claude models from the panel (`CompanionPanelView.modelPickerRow`); the choice persists to `UserDefaults["selectedClaudeModel"]`:

- `claude-sonnet-4-6` (default)
- `claude-opus-4-6`

There's an `OpenAIAPI.swift` and `OpenAIAudioTranscriptionProvider.swift` in the repo too, but the active production path is Claude + AssemblyAI as configured in `Info.plist` (`VoiceTranscriptionProvider = assemblyai`).

## What's intentionally *not* in the app

- No Dock icon, no main window, no preferences window.
- No persistent chat history.
- No setting for the push-to-talk shortcut — it's hardcoded to `ctrl+option` (`BuddyPushToTalkShortcut.currentShortcutOption = .controlOption`, `BuddyDictationManager.swift:95`).
- No way to disable analytics from the UI — PostHog is wired in unconditionally (`ClickyAnalytics.configure`).
- The "leanring" misspelling in the project/scheme name is intentional legacy — do not rename it.

## Audience

This is a personal/open-source project by Farza. The codebase optimises for:

- **Clarity over cleverness.** Long variable names, explicit `// why` comments around AppKit bridging. See the conventions in `AGENTS.md`.
- **Reliability of one specific flow** (hold hotkey → screen-aware voice answer) over breadth of features.
