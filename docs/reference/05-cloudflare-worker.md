# Cloudflare Worker — `clicky-proxy`

## Why a proxy exists

API keys (Anthropic, AssemblyAI, ElevenLabs) must not ship in a shareable macOS binary. The Worker holds them as Cloudflare secrets and the app talks only to the Worker.

## Routes

All routes are `POST`. The Worker rejects anything else with HTTP 405.

### `POST /chat` → `https://api.anthropic.com/v1/messages`

| | |
|---|---|
| Headers added | `x-api-key: $ANTHROPIC_API_KEY`, `anthropic-version: 2023-06-01`, `content-type: application/json` |
| Body | Forwarded verbatim. The app sends `{model, max_tokens, stream, system, messages}` with image content blocks. |
| Response | Streamed back as `text/event-stream` (SSE). The Worker proxies `response.body` directly so chunks reach the client as Anthropic emits them. |
| Errors | Forwarded with original status + body. |

### `POST /tts` → `https://api.elevenlabs.io/v1/text-to-speech/{ELEVENLABS_VOICE_ID}`

| | |
|---|---|
| Headers added | `xi-api-key: $ELEVENLABS_API_KEY`, `content-type: application/json`, `accept: audio/mpeg` |
| Body | Forwarded verbatim. The app sends `{text, model_id: "eleven_flash_v2_5", voice_settings: {stability: 0.5, similarity_boost: 0.75}}`. |
| Response | `audio/mpeg` MP3 forwarded as-is. |
| Errors | Forwarded with original status + body. |

### `POST /transcribe-token` → `https://streaming.assemblyai.com/v3/token?expires_in_seconds=480`

| | |
|---|---|
| Headers added | `authorization: $ASSEMBLYAI_API_KEY` (upstream call is `GET`) |
| Body | Empty — the upstream is a `GET`, the route is still defined as `POST` to keep the app→Worker shape uniform. |
| Response | `{ "token": "..." }` (JSON) with 480-second validity. |

## Secrets and vars

Secrets (set with `npx wrangler secret put`):

- `ANTHROPIC_API_KEY`
- `ASSEMBLYAI_API_KEY`
- `ELEVENLABS_API_KEY`

Public vars (in `wrangler.toml`):

- `ELEVENLABS_VOICE_ID = "kPzsL2i3teMYv0FxEYQ6"` — current voice. Replace with your own.

## Local development

```bash
cd worker
npm install
cp /dev/null .dev.vars   # then add your keys, one per line:
                         # ANTHROPIC_API_KEY=sk-ant-...
                         # ASSEMBLYAI_API_KEY=...
                         # ELEVENLABS_API_KEY=...
                         # ELEVENLABS_VOICE_ID=...
npx wrangler dev
```

This serves at `http://localhost:8787`. To point the app at it, edit the two hardcoded URLs:

1. `CompanionManager.workerBaseURL` (file `CompanionManager.swift`, top of class).
2. `AssemblyAIStreamingTranscriptionProvider.tokenProxyURL` (file `AssemblyAIStreamingTranscriptionProvider.swift`, top of class).

`grep -r "clicky-proxy" leanring-buddy/` finds both.

## Deployment

```bash
cd worker
npx wrangler deploy
```

Output gives a `*.workers.dev` URL. Either reuse the same hostname when you self-host, or set up a custom domain in the Cloudflare dashboard.

## Error semantics

Every route logs the upstream status + body to `console.error` and forwards the *upstream*'s status code and body to the client. The Worker never mints its own error JSON beyond a generic `{"error": "..."}` at HTTP 500 for unhandled exceptions.

## What the Worker does NOT do

- No rate limiting.
- No auth on the inbound side — anyone who knows the URL can hit it.
- No request logging or analytics beyond `console.error` on upstream failures.
- No caching (`cache-control: no-cache` set on `/chat`).
- No request transformation — bodies are forwarded verbatim.
