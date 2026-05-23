# ADR 0008 — AI provider stack: Claude + AssemblyAI + ElevenLabs (Apple Speech fallback)

**Status**: Accepted (retroactive)
**Date**: 2026-05-22 (documented; original decision predates this)
**Deciders**: original-author
**Related**: [ADR 0002](./0002-cloudflare-worker-proxy.md), [ADR 0010](./0010-text-based-point-protocol.md)

## Context

The voice turn has three distinct AI workloads, each of which has a different set of provider options. The choices were made independently:

1. **Vision + text reasoning** ("look at the screen and answer / point"). Frontier multimodal LLMs only — GPT-4o, Claude, Gemini.
2. **Streaming low-latency transcription** ("convert mic audio to text as the user talks"). Real-time streaming APIs — AssemblyAI, Deepgram, Whisper (via OpenAI Realtime), Apple Speech.
3. **Voice synthesis** ("speak the response aloud"). TTS APIs — ElevenLabs, OpenAI TTS, Apple `AVSpeechSynthesizer`, Azure Neural Voices.

### Vision + text → Claude

Claude was picked over GPT-4o for one specific reason: pointing accuracy. The product requires the model to look at a screenshot and emit pixel coordinates of a UI element (see [ADR 0010](./0010-text-based-point-protocol.md) for the protocol). Anthropic's Computer Use training data and the Claude 4.x family demonstrate noticeably better pixel-coordinate accuracy on UI elements than GPT-4o in side-by-side testing. SSE streaming is mature, the API accepts multiple image content blocks per message, and the model follows the long custom system prompt without drifting.

Sonnet 4.6 is the default; Opus 4.6 is offered as a user-pickable option in the model picker (`CompanionPanelView.modelPickerRow`). Both are wired via the Worker `/chat` route.

### Transcription → AssemblyAI

AssemblyAI's `u3-rt-pro` real-time model was picked over Deepgram, Whisper-realtime, and Apple Speech for the streaming case. Three reasons:

- **Latency**: sub-300 ms turn-finalisation on `ForceEndpoint`, measured in practice on push-to-talk releases under 5 s.
- **Quality on technical jargon**: with `keyterms_prompt` (passed contextual terms like "Codex", "SwiftUI", "Vercel"), domain words transcribe correctly without needing a custom model.
- **Short-lived token model**: the Worker mints a 480-second JWT and the app connects directly to the websocket. The Worker stays stateless and doesn't have to proxy audio frames.

OpenAI's `gpt-4o-transcribe` is wired as a buffer-and-upload alternative (`OpenAIAudioTranscriptionProvider`). It's *not* on the hot path — it's available if someone configures `OpenAIAPIKey` in `Info.plist`. It's an "if AssemblyAI is down" fallback rather than a primary.

Apple Speech is the third provider (`AppleSpeechTranscriptionProvider`) — on-device, free, works offline, but lower accuracy on jargon and no streaming-turn semantics.

### TTS → ElevenLabs

ElevenLabs `eleven_flash_v2_5` was picked over OpenAI TTS and Apple `AVSpeechSynthesizer` for voice quality. The model is fast enough (typically < 1 s end-to-end for short replies) that the spinner-then-TTS gap is acceptable. The voice ID is server-side (`ELEVENLABS_VOICE_ID` in `wrangler.toml`) so it can be swapped without an app update.

When ElevenLabs returns an error (e.g. credits exhausted), the app falls back to `NSSpeechSynthesizer` with a fixed apology string — see `CompanionManager.speakCreditsErrorFallback()`.

See `ClaudeAPI.swift`, `AssemblyAIStreamingTranscriptionProvider.swift`, `ElevenLabsTTSClient.swift`, `AppleSpeechTranscriptionProvider.swift`, `OpenAIAudioTranscriptionProvider.swift`, and `docs/reference/03-features.md` §§ 3, 5, 6.

## Decision

The active production stack is:

| Workload | Provider | Model | Path |
|----------|----------|-------|------|
| Vision + text | Anthropic Claude | `claude-sonnet-4-6` (default), `claude-opus-4-6` (user toggle) | Worker `/chat` → SSE |
| Streaming transcription | AssemblyAI | `u3-rt-pro` | Worker `/transcribe-token` then direct websocket |
| TTS | ElevenLabs | `eleven_flash_v2_5` | Worker `/tts` |

OpenAI clients (`OpenAIAPI.swift`, `OpenAIAudioTranscriptionProvider.swift`) and `AppleSpeechTranscriptionProvider` are kept as configured alternatives but not used by default. The transcription provider is selected at launch from `Info.plist["VoiceTranscriptionProvider"]` (ships as `assemblyai`).

## Consequences

### Positive
- Three best-in-class providers for three distinct workloads.
- Claude's pointing accuracy is what makes the `[POINT:x,y]` flow work at all (see [ADR 0010](./0010-text-based-point-protocol.md)).
- The transcription layer is genuinely pluggable — `BuddyTranscriptionProvider` is a protocol with three implementations and a factory.

### Negative
- Three separate billing relationships and three separate sets of credits to keep funded. Each can independently fail in production.
- ElevenLabs `eleven_flash_v2_5` voices are noticeably "AI-voiced" — not as natural as their newer multilingual models. We trade some quality for speed.
- The model picker only exposes Sonnet vs Opus. There is no way for a user to opt into GPT-4o without code changes, even though the OpenAI client exists.
- Apple Speech as a "fallback" is in the code but no automatic failover wires AssemblyAI → Apple if the websocket fails. The fallback is by configuration only.

### Neutral / trade-offs
- The contextual `keyterms_prompt` array passed to AssemblyAI is hardcoded in `BuddyDictationManager.buildTranscriptionKeyterms()`. It improves jargon transcription noticeably but maintaining it is a manual job — see `docs/reference/03-features.md` § 3 for the current list.
- Apple Speech is the only provider that requires a separate `NSSpeechRecognitionUsageDescription` permission. The Info.plist declares it so the prompt has the right text if/when the Apple provider is ever activated.

## Notes

The offline-and-local-models spec (`docs/specs/11-offline-and-local-models.md`) will eventually let the user pick a Local mode that swaps Claude for Apple Foundation Models, AssemblyAI for `SpeechAnalyzer`, and ElevenLabs for `AVSpeechSynthesizer` Neural voices. This ADR remains accurate for the Cloud-mode default; a future ADR will document the mode picker and the per-mode primitive set.
