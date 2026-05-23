# ADR 0006 — In-memory conversation history, capped at 10 turns

**Status**: Accepted (retroactive)
**Date**: 2026-05-22 (documented; original decision predates this)
**Deciders**: original-author
**Related**: [ADR 0011](./0011-posthog-with-full-payloads.md)

## Context

Claude is a stateless API — every request carries the full conversation as the `messages` array. Some context is necessary or the model can't follow up on its own previous answer ("yeah, do that"; "what was that called?"). But every turn we send includes the previous transcripts, the previous responses, *and* a full-resolution JPEG of every connected display, so the token cost grows fast.

Three orthogonal questions had to be answered:

1. **How many turns to keep?** Empirically, voice-pipeline interactions are short — the user holds the hotkey, asks something, gets an answer, often follows up once or twice, then context-switches. 10 turns covers the practical maximum without bloating the request. Above 10 the user almost always wants a fresh context anyway.
2. **Should history persist across app launches?** Persistence would require either a SQLite store or a plist on disk. It would also create a real privacy obligation (encrypt at rest, expose a "clear history" button, decide what to do about screenshots in history). The voice-pipeline use case rarely benefits from cross-launch memory — the user almost always starts a new train of thought when they reopen the app.
3. **Should the `[POINT:...]` tag be saved in history?** No — keeping stale pointing coordinates in history would let the model parrot old coordinates on follow-up turns, pointing at the wrong thing.

See `CompanionManager.swift:85` (`conversationHistory` declaration), `CompanionManager.sendTranscriptToClaudeWithScreenshot` (where the trim and append happen), `docs/reference/03-features.md` § 10, and `docs/reference/07-permissions-and-privacy.md` (what stays on-device).

## Decision

`CompanionManager.conversationHistory` is a `[ConversationTurn]` array kept in memory only. After each successful turn:

1. The assistant message has `[POINT:x,y:...]` / `[POINT:none]` stripped before being appended.
2. If the array length exceeds 10 (5 user + 5 assistant exchanges), the oldest entries are trimmed from the front.
3. The full array is included verbatim in the next Claude request via the `messages` field.

Quitting the app drops the array. There is no on-disk persistence and no UI to clear history (quitting is the clear).

## Consequences

### Positive
- No on-disk persistence means no privacy obligation around the transcript text or the screenshots that produced it.
- App restart is a clean slate — this is what most users actually want for voice interactions.
- No SQLite, no plist serialisation, no migration story.
- The strip-tag-before-store rule prevents stale pointing coordinates from leaking back into Claude's context.

### Negative
- Users cannot ask Clicky to recall something from yesterday ("what did you tell me about that file earlier?"). This is by design but it's a real limitation, especially for power users.
- 10 turns is hardcoded — there's no UI to change it. If a particular workflow needs more context the user can't expand it.
- Crashes or unexpected quits silently lose all context. There is no "restore last session" affordance.

### Neutral / trade-offs
- The full image bytes from previous turns are kept in memory while their text equivalents are kept in history. This is a memory cost (roughly 100–300 KB per screenshot × number of displays × 10 turns at most) but it is bounded and falls in the noise of a typical Swift process.
- `conversationHistory` is mutated only on the main actor, so we don't need locking — it lives on `CompanionManager` which is `@MainActor`.

## Notes

The vector-search spec (`docs/specs/12-vector-search-and-memory.md`) is the planned successor to this approach. Phase V1 ships conversation-memory retrieval: keep a longer history on disk encrypted, embed each turn locally with `NLContextualEmbedding`, and inject the top-k relevant past turns at request time instead of the last-N. When that ships, this ADR will be superseded.
