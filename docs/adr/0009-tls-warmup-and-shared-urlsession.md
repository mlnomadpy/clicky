# ADR 0009 — TLS warmup HEAD request and one long-lived URLSession per host

**Status**: Accepted (retroactive)
**Date**: 2026-05-22 (documented; original decision predates this)
**Deciders**: original-author
**Related**: [ADR 0002](./0002-cloudflare-worker-proxy.md), [ADR 0008](./0008-ai-provider-stack.md)

## Context

Two distinct production bugs were the forcing function for two distinct fixes that share a common theme — `URLSession` lifecycle matters.

### Bug 1: errSSL -1200 on the first Claude request

`ClaudeAPI.analyzeImageStreaming` sends a large body — base64-encoded JPEG screenshots of every connected display plus the system prompt plus history. On the very first call after app launch, this request intermittently failed with `errSSLBadRecordMac` (`-1200`). Repeating the call worked. The pattern was reproducible enough to chase.

The root cause was a cold TLS handshake racing with a large initial write. The first record on a fresh TLS session was occasionally being rejected by `URLSession`. The fix — confirmed by testing — is to do a tiny preflight request that completes the TLS handshake and caches a session ticket. By the time the real request goes out, the handshake is warm and the large payload sails through.

### Bug 2: "Socket is not connected" on AssemblyAI reconnects

`AssemblyAIStreamingTranscriptionProvider` originally created a new `URLSession` per push-to-talk press, used the websocket, and invalidated the session on release. After about four to six rapid press cycles (releasing and re-pressing the hotkey within seconds), new websocket connections started failing with "Socket is not connected" until the user waited 30+ seconds or restarted the app.

The pattern was: per-session `URLSession.invalidateAndCancel()` returns the underlying NSURLSessionTask network channel to the pool, but rapid create/invalidate cycles corrupt connection-pool state. Sharing a single long-lived `URLSession` across every press eliminates the problem — the OS reuses the channel internally.

See `ClaudeAPI.swift`, `OpenAIAPI.swift`, `AssemblyAIStreamingTranscriptionProvider.swift`, and `docs/reference/02-system-design.md` § "URLSession lifetimes".

## Decision

Two independent rules, both load-bearing:

1. **TLS warmup on `ClaudeAPI` and `OpenAIAPI` init.** Each client creates a `URLSessionConfiguration.default`-backed session and, on `init`, fires a fire-and-forget HEAD request to the host (`workerBaseURL` for Claude, `api.openai.com` for OpenAI). This caches a TLS session ticket so the first real request — which carries a base64 JPEG payload — doesn't pay a cold handshake.
2. **One shared `URLSession` for AssemblyAI streaming.** `AssemblyAIStreamingTranscriptionProvider` owns a single long-lived `URLSession` at the provider level. Every streaming session (every push-to-talk press) reuses it. No per-session `URLSession` is created. The session is never invalidated until the provider itself is torn down (i.e. process exit).

## Consequences

### Positive
- The first Claude request after app launch is reliable — no more `errSSL -1200` flakes on cold start.
- AssemblyAI reconnects survive rapid press cycles indefinitely. The "Socket is not connected" failure mode is gone.
- Both fixes are local, undocumented-feature-free, and have no behavioural surface beyond reliability.

### Negative
- The TLS warmup is a request the user never asked for. It's small (HEAD, no body) but it does hit the network on app launch.
- A shared `URLSession` for AssemblyAI means we can't cleanly cancel everything by tearing down the session — cancellation has to be per-task (each websocket task is `.cancel()`'d on release).
- Two important rules in two different files. If a future maintainer "tidies up" by either (a) removing the warmup as "dead code" or (b) switching AssemblyAI to per-session `URLSession`s as "cleaner", the bugs come back. The comments in each file flag this.

### Neutral / trade-offs
- Both `ClaudeAPI` and `OpenAIAPI` set `urlCache = nil` and `httpCookieStorage = nil` on their configurations. This is unrelated to the warmup but worth noting: response bodies (which may contain transcript text or model output) are never persisted to disk.
- The warmup is best-effort — if the network is offline at launch it fails silently. The real request still works once the network is back because the URLSession will perform a fresh handshake then.

## Notes

This is the kind of decision that only makes sense when read alongside the bug reports it fixed. If a maintainer with no context looks at either pattern and thinks "why is this here?", the answer is in the file comments and in this ADR. Do not remove either without a controlled experiment first.
