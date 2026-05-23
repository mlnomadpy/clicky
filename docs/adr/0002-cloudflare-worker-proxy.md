# ADR 0002 — Cloudflare Worker as API proxy

**Status**: Accepted (retroactive)
**Date**: 2026-05-22 (documented; original decision predates this)
**Deciders**: original-author
**Related**: [ADR 0008](./0008-ai-provider-stack.md), [ADR 0011](./0011-posthog-with-full-payloads.md)

## Context

Clicky talks to three paid third-party APIs: Anthropic (Claude), AssemblyAI (streaming transcription), and ElevenLabs (TTS). Each requires a long-lived API key. Clicky is shipped as a notarised macOS DMG and the source is on GitHub under MIT. Any key shipped in the binary — or in a config file the user has to fill in — is functionally public.

Three options were on the table:

1. **Ship keys in the binary.** Trivially extractable from a `.app` bundle; would burn the project's credits within hours of release.
2. **Ask each user to bring their own key.** Kills the install funnel — most users won't have three API accounts; some are paid-only (ElevenLabs, AssemblyAI). Onboarding becomes a config screen instead of a delightful demo.
3. **Server-side proxy holding the keys.** Adds one deployable component, but keeps the keys out of the binary and lets the maintainer pay for usage centrally.

Option 3 was picked. Cloudflare Workers specifically because: (a) free tier covers small projects, (b) zero-ops — no VPS to patch, (c) global edge presence means low added latency for HTTPS requests, (d) Wrangler CLI makes secret management one command per key. The Worker is implemented in `worker/src/index.ts` — three POST routes, no framework, no inbound auth.

See `docs/reference/05-cloudflare-worker.md` for the full route table and `docs/reference/07-permissions-and-privacy.md` for where each key lives.

## Decision

Every call to a paid third-party API goes through a single Cloudflare Worker, `clicky-proxy`. The Worker holds `ANTHROPIC_API_KEY`, `ASSEMBLYAI_API_KEY`, and `ELEVENLABS_API_KEY` as Cloudflare secrets and exposes three routes:

| Route | Upstream | Notes |
|-------|----------|-------|
| `POST /chat` | `api.anthropic.com/v1/messages` | SSE streamed back to the client unchanged. |
| `POST /tts` | `api.elevenlabs.io/v1/text-to-speech/{voice}` | Voice ID is a public `wrangler.toml` var, not a secret. |
| `POST /transcribe-token` | `streaming.assemblyai.com/v3/token` | Returns a 480-second JWT; the app then connects to AssemblyAI's websocket directly with that token. |

No API key ever leaves the Worker. The app's Anthropic and ElevenLabs clients never see the upstream host directly — only `workerBaseURL`.

## Consequences

### Positive
- The Swift binary contains zero rotatable secrets — the GitHub repo can be public.
- One place to rotate keys (`wrangler secret put`); no app rebuild required.
- Cloudflare absorbs DDoS at the edge for free.
- Streaming is transparent: the Worker proxies `response.body` directly so SSE chunks reach the client unbuffered.

### Negative
- **The Worker has no inbound auth.** Anyone who discovers the URL can use it to burn the maintainer's credits. This is a known trade-off; mitigations would be a shared client secret (still extractable from the binary), per-user signed tokens (requires an account system Clicky doesn't have), or Cloudflare WAF rules.
- One more thing to deploy and maintain. Forks need their own Worker and have to edit `workerBaseURL` in two Swift files.
- Adds one extra TLS hop on every request. In practice this is well under 50 ms on Cloudflare's edge, dominated by Anthropic's TTFT, but it is non-zero.

### Neutral / trade-offs
- The AssemblyAI websocket is *not* proxied — only the token fetch is. The app connects directly to `streaming.assemblyai.com` after getting the 480-second token. This was chosen over websocket proxying to keep the Worker stateless and avoid Cloudflare Worker websocket pricing.
- The Worker is intentionally dumb — no request transformation, no logging beyond `console.error` on upstream errors, no caching. Forwarding bodies verbatim keeps it easy to debug.

## Notes

If/when the project scales beyond hobby use, the obvious next step is to add a shared-secret header (`x-clicky-shared-secret`) bundled into release builds and rotated per release, plus per-IP rate limiting at the Worker. That keeps casual scrapers out without an account system. See `docs/reference/05-cloudflare-worker.md` § "What the Worker does NOT do".
