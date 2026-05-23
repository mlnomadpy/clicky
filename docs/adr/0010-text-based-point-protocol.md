# ADR 0010 — Text-tag `[POINT:x,y:label:screenN]` protocol for pointing

**Status**: Accepted (retroactive)
**Date**: 2026-05-22 (documented; original decision predates this)
**Deciders**: original-author
**Related**: [ADR 0004](./0004-screencapturekit.md), [ADR 0008](./0008-ai-provider-stack.md)

## Context

Claude has to do two things in one response:

1. Speak a natural reply (which the user hears via ElevenLabs TTS).
2. Optionally tell the app "by the way, point at *that* button at pixel (832, 410) on screen 2".

The second part is structured data — coordinates plus an optional label plus an optional screen number. Anthropic offers a first-class mechanism for structured outputs (tool use / function calling), which would have been the textbook answer. But Clicky uses SSE streaming so the text reply starts speaking almost immediately, and we wanted exactly *one* round-trip — text and pointing data in the same stream.

Three alternatives were considered:

1. **Anthropic tool use** with a `point_at_element` tool. Clean schema, validated arguments. Downsides: two round-trips (the model emits a `tool_use` block, the app emits a `tool_result`, the model emits the final text), which adds latency. Also requires custom SSE handling for `tool_use` content blocks alongside `text_delta`, more code than a regex.
2. **JSON-in-response**, e.g. ask Claude to wrap output as `{"speech": "...", "point": {"x":..., "y":..., "label":"..."}}`. Easy to parse but breaks streaming — we'd have to buffer the entire response before parsing, which defeats the SSE setup.
3. **A trailing text tag** like `[POINT:832,410:OK button:screen2]` appended at the very end of the natural-language response. Streams cleanly (the tag arrives in the last few SSE chunks); strip the tag from spoken text with a regex; the rest is plain prose that goes straight to TTS.

Option 3 was picked. The system prompt teaches Claude the protocol (see `companionVoiceResponseSystemPrompt` in `CompanionManager.swift`), and `parsePointingCoordinates` parses it on the way out:

```
\[POINT:(?:none|(\d+)\s*,\s*(\d+)(?::([^\]:\s][^\]:]*?))?(?::screen(\d+))?)\]\s*$
```

Coordinates are in screenshot pixels (top-left origin, in the dimensions the image was sent at — see [ADR 0004](./0004-screencapturekit.md) for the image labelling that teaches the model what coordinate space to use).

See `CompanionManager.parsePointingCoordinates`, `CompanionManager.companionVoiceResponseSystemPrompt`, `docs/reference/03-features.md` § 8, and `docs/reference/02-system-design.md` § "Coordinate math".

## Decision

Pointing is communicated via a trailing text tag at the end of Claude's response:

- `[POINT:x,y:label]` — point at `(x, y)` on the cursor screen, with a 1–3-word `label` spoken in the bubble.
- `[POINT:x,y:label:screenN]` — same but explicitly on screen N (1-indexed, matching the image labels).
- `[POINT:none]` — no element to point at this turn.

The parser strips the tag from the spoken text (so ElevenLabs never reads it aloud), extracts the coordinate, looks up the right display's screenshot, and converts pixel → AppKit-point coordinates to drive the bezier-arc animation.

## Consequences

### Positive
- Single round-trip — text and pointing data arrive in the same SSE stream.
- Plays well with streaming: by the time the tag arrives, TTS is already buffered for the prose that came before it. There's no pause.
- Trivially testable: feed a string to `parsePointingCoordinates`, assert the output. No mock model required.
- Provider-agnostic: the same tag protocol works if we ever swap Claude for GPT-4o — only the system prompt has to change.

### Negative
- The protocol is "vibes" — the model can occasionally emit malformed tags (`[POINT: 832,410]` with a leading space, or two tags in one response, or coordinates outside the image dimensions). The parser is defensive (clamps coordinates, anchors to end-of-string) but malformed tags are silently dropped, which can look like "Claude forgot to point".
- The system prompt has to teach the model the format every turn. That's tokens we pay for on every request.
- The model can also choose to *not* emit any tag at all, which the parser treats as "no point" — there's no way to distinguish "model forgot" from "model decided no". Empirically Claude is reliable about always emitting either `[POINT:x,y:...]` or `[POINT:none]` thanks to the system prompt instruction.

### Neutral / trade-offs
- Coordinates are in screenshot pixels, not display points. Conversion to AppKit points happens client-side and depends on the display's actual frame; the math is in `CompanionManager.sendTranscriptToClaudeWithScreenshot` (around line 663) and is mirrored in `performOnboardingDemoInteraction` (around line 1005).
- The `screenN` parameter is optional and defaults to the cursor screen. When the user has multiple displays and Claude wants to point at the non-cursor screen, the model must emit `:screenN`. The system prompt instructs it to.

## Notes

If we ever migrate to Anthropic's structured-output API (tool use with `disable_parallel_tool_use` for atomicity, or a future "JSON mode" with streaming), revisit this ADR. The tag protocol was the right call when SSE-only streaming was the constraint; structured outputs would be more robust at the cost of one round-trip.
