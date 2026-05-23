# ADR 0011 — PostHog telemetry with full transcript and response payloads

**Status**: Accepted (retroactive)
**Date**: 2026-05-22 (documented; original decision predates this)
**Deciders**: original-author
**Related**: [ADR 0006](./0006-in-memory-conversation-history.md), [ADR 0002](./0002-cloudflare-worker-proxy.md)

## Context

Clicky is a small open-source project. The original author wanted to know how it was actually being used — which permissions get granted, how often push-to-talk fires, what people ask, what Claude says back. That information feeds product decisions: what to improve, what's broken in the wild, whether the demo is converting.

The conservative choice would be event-level telemetry that captures *counts but not contents*: `push_to_talk_released` with no payload, no transcript text, no response text. That gives you usage shape but tells you nothing about *what people are doing with the app*.

The choice that was made: ship every event with the full content. `user_message_sent` carries the full transcript. `ai_response_received` carries the full Claude response. `element_pointed` carries the label. The user's email — submitted in onboarding — becomes the PostHog distinct ID, so events are joinable per user.

This is a real privacy posture choice, not a default. The reasoning was:

- Sample size is small enough that aggregate counts are noise. Reading actual transcripts is how you learn what's broken.
- The author owns the project end-to-end and trusts their own analytics pipeline.
- Users see the email collection during onboarding before any telemetry fires (PostHog identify happens at email submission).
- Future Local mode (`docs/specs/11-offline-and-local-models.md`) will give privacy-conscious users a no-telemetry path.

What it costs: this is the *least* private posture among reasonable choices. There is no UI to opt out. The PostHog write key is hardcoded in `ClickyAnalytics.swift` (PostHog write-only project keys are designed to be public, but extracting it would let anyone send fake events). Users in regulated environments cannot use the cloud-mode app safely.

See `ClickyAnalytics.swift`, `CompanionManager.submitEmail` for the identify call, `docs/reference/03-features.md` § 15 for the full event list, and `docs/reference/07-permissions-and-privacy.md` for the data-leaves-the-device table.

## Decision

`ClickyAnalytics` wraps `PostHogSDK.shared` and is initialised unconditionally in `applicationDidFinishLaunching`. Events include:

- Lifecycle: `app_opened`, `onboarding_started`, `onboarding_replayed`, `onboarding_video_completed`, `onboarding_demo_triggered`.
- Permissions: `permission_granted` (with name), `all_permissions_granted`.
- Voice turns: `push_to_talk_started`, `push_to_talk_released`, `user_message_sent` (**full transcript**), `ai_response_received` (**full response text**), `element_pointed` (label).
- Errors: `response_error`, `tts_error`.

The user's onboarding email is the PostHog distinct ID via `PostHogSDK.shared.identify(...)` in `CompanionManager.submitEmail`. There is no in-app toggle to disable analytics.

## Consequences

### Positive
- The maintainer has real visibility into what people ask Clicky and what Claude says back. This drives every product decision worth making at this scale.
- Failure modes show up in telemetry — `response_error` and `tts_error` events with associated user IDs make incident response possible without users having to file bug reports.
- Per-user identification (via email) lets the maintainer reply directly when something breaks ("hey, saw your transcript failed — here's a fix").

### Negative
- **This is a privacy posture, not a privacy-by-default product.** Users in regulated environments, users handling client data, and users with confidentiality requirements should not be sending screen-captioned voice transcripts to a third-party analytics provider. Today there is no in-product way to opt out short of editing source.
- Email-as-distinct-ID means the analytics dataset is directly tied to identifiable people. Any breach or accidental export is meaningful PII.
- The PostHog write key is hardcoded. Forkers who don't strip `ClickyAnalytics` ship telemetry to the original maintainer.
- We share full screen content (via transcripts that describe what's on screen, plus Claude's response that quotes UI text) with PostHog. We do *not* send screenshots to PostHog, but the prose effectively summarises them.

### Neutral / trade-offs
- The Cloudflare Worker (see [ADR 0002](./0002-cloudflare-worker-proxy.md)) does *not* log request bodies. Telemetry only flows through PostHog from the client. So removing PostHog removes essentially all observability.
- Future Local mode (`docs/specs/11-offline-and-local-models.md`) is the planned path for privacy-conscious users — when Local mode lands, telemetry can be gated off entirely for that mode.

## Notes

If you fork Clicky and don't want telemetry, the strip path is documented in `docs/reference/07-permissions-and-privacy.md` § "Removing PostHog if you fork":

1. Delete `ClickyAnalytics.swift`.
2. Remove the PostHog SPM dependency.
3. Replace every `ClickyAnalytics.track…` call with a no-op.
4. Remove the `PostHogSDK.shared.identify(...)` call from `CompanionManager.submitEmail`.

A future ADR will document the Local-mode telemetry policy (likely: no events whatsoever when mode = Local).
