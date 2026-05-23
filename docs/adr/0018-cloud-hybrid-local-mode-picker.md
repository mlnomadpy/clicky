# ADR 0018 — A single Cloud / Hybrid / Local mode setting governs all AI calls

**Status**: Proposed
**Date**: 2026-05-22
**Deciders**: Farza, Claude Code session
**Related**: [ADR 0019](./0019-ocr-and-foundation-models-pointing.md), [ADR 0020](./0020-mlx-swift-for-vlms.md), [ADR 0017](./0017-compile-swoosh-to-plugin.md)
**Source spec**: `docs/specs/11-offline-and-local-models.md`

## Context

Today every AI call in Clicky goes to a cloud provider (Claude via the Worker, AssemblyAI for transcription, ElevenLabs for TTS). Three forces push us toward more flexibility:

1. **Cost** — Farza pays for every turn. The cost projection in `specs/11` shows ~$36/month for a heavy user.
2. **Privacy** — some users want voice + screen-aware AI that never touches a network.
3. **Latency floor** — cloud requests have an unavoidable round-trip. After a local model is warmed up, it can be faster for short replies.

The naive design — three independent toggles ("use local transcription", "use local LLM", "use local TTS") — generates 8 combinations to test and 8 mental models for the user to manage. Most of those combinations don't make sense.

The slightly-less-naive design — one toggle "use local everything" — couples the choices unnecessarily. Sometimes you want Claude's planning quality with free TTS.

The right granularity is *modes*: named bundles of choices that map to user-meaningful intents.

## Decision

Three modes, mutually exclusive, set via a single picker in the panel:

- **Cloud** — today's behavior. Everything goes to the Worker. Default for new installs.
- **Hybrid** — Claude for the parts that need its planning + vision quality; Apple Foundation Models for pre-perception, summarization, and any sub-task that fits FM's 4K context; `SpeechAnalyzer` for transcription; `AVSpeechSynthesizer` for TTS. Roughly half the cost of Cloud.
- **Local** — no network at all. Foundation Models + Vision OCR + (optional) MLX-Swift VLM. Swoosh is unavailable in this mode (see [ADR 0017](./0017-compile-swoosh-to-plugin.md)).

The mode is a string in `UserDefaults["aiMode"]`. The plugin generator's system prompt is mode-aware — in Local mode it can only emit local primitives; in Hybrid mode it biases toward local. The Swoosh runtime reads the mode and disables itself in Local with a clear message and a link to the saved-plugins list.

Per-turn cloud fallback ("try cloud Claude?") is offered in Local mode when the local response has low confidence — one tap returns to Local for the next turn.

## Consequences

### Positive

- One setting, three intents the user can name. Easy to explain in onboarding, easy to support.
- The architecture (primitives, generator prompt, runtime dispatch) is shared between modes. The mode is a routing parameter, not a fork.
- Reduces test matrix from 8 combinations to 3.
- Local mode is a meaningful product position — *"AI that never leaves your Mac."*

### Negative

- The user can't say "I want Claude for chat but Apple TTS." Hybrid does this automatically; if a user wants a different mix they can't have it.
- Mode-switching has consequences (Foundation Models has a one-time asset download; MLX VLMs are several GB). The UX for moving between modes needs to handle these gracefully.
- The mode is invisible to the user when things are working — they might not realize why a feature worked yesterday and doesn't today (Swoosh disabled in Local). UX needs to surface mode-dependent disabled states clearly.

### Neutral / trade-offs

- Power-user override (per-plugin "always use Cloud" toggle) is documented as Phase L4+ work. Initially the modes are global.
- The line "default to Cloud" preserves today's behavior. A future ADR could revisit if usage data shows most users prefer Hybrid.
- Cloud mode is the only one where analytics fire. Hybrid logs but doesn't reduce telemetry; Local turns telemetry off entirely. This is a privacy-posture choice baked into the modes (see [ADR 0011](./0011-posthog-with-full-payloads.md)).

## Notes

- The mode picker UI is part of Phase L4 in `specs/11`.
- Foundation Models requires macOS 26 + Apple Silicon. Hybrid and Local are gated on these — Intel Macs see only "Cloud" in the picker.
- This ADR may be superseded later if open-weight model quality reaches a point where Local Swoosh is feasible. At that point the mode definitions may shift.
