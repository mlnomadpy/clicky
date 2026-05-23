# ADR 0016 — Swoosh ships as a UX illusion in v1, with real virtualization as the eventual destination

**Status**: Proposed
**Date**: 2026-05-22
**Deciders**: Farza, Claude Code session
**Related**: [ADR 0015](./0015-plugin-system-declarative-manifests.md), [ADR 0017](./0017-compile-swoosh-to-plugin.md)
**Source spec**: `docs/specs/10-swoosh-mode-design.md`
**Related memory**: `memory/swoosh_isolation_strategy.md`

## Context

Swoosh is a long-running agentic mode — give Clicky a task, it goes "somewhere" to do the work, and reports back. The user-facing pitch is *"Clicky goes to another desktop and gets it done."*

The literal interpretation — actually create a separate macOS Space — runs into a wall: macOS exposes no public API for creating or switching Spaces. Three real options:

1. **Private CGS APIs** (`CGSCreateSpace`, `_CGSDefaultConnection`) — work, but apps using them face notarization rejection risk and break with major macOS releases. Hammerspoon and similar tools that lean on these APIs have a long history of breaking on every OS update.
2. **AppleScript driving Mission Control** — flaky, visible to the user, can't reliably target a specific Space.
3. **Fast User Switching** — too much UX friction for a per-task feature.
4. **Per-app virtual displays / VMs** — heavy dependency (`Virtualization.framework` or external sandbox); months of work; only macOS 13+ supports macOS guests; user has to download a guest image.
5. **No real separation — just a UX illusion.** A full-screen overlay window dims the screen, the agent works on the user's real Mac inside a hidden capture context, the swoosh animation creates the mental model.

## Decision

V1 of Swoosh ships as option 5 — the UX illusion. The agent runs on the user's real Mac. The "another desktop" is a full-screen translucent overlay window that dims the user's screen while the agent works. The swoosh-out / swoosh-back animations are the entire isolation theater.

We design the runtime so that the host environment is abstracted behind a `SwooshHost` protocol. Every tool the agent can call (`click`, `type`, `capture_screen`, `open_app`, `read_file`, …) goes through this protocol. The v1 implementation targets the real Mac. A future v2 swaps it for a `Virtualization.framework`-backed macOS guest, or a remote sandboxed compute target.

The safety model (destructive-action confirmations, scope allowlists, audit log) is written **as if isolation already existed**. Anything that would be catastrophic without a sandbox stays out of scope for v1.

## Consequences

### Positive

- We ship Swoosh in a reasonable timeframe instead of spending a quarter building a VM dependency before any user sees the feature.
- No private API usage; notarization-safe.
- The `SwooshHost` abstraction is doing real work even in v1 — it's how we test the runtime against scripted hosts.
- When real isolation lands, it's a backend swap, not a redesign. The safety model already assumes isolation.

### Negative

- A v1 Swoosh run can in principle damage the user's system (delete files, send messages, post tweets) — the supervisor's destructive-confirm gating is the only defense. If we get the supervisor wrong, the user pays.
- The illusion is leaky. If the user clicks during the agent's action, the agent visibly competes with them. The dim overlay sells the illusion only when the user cooperates.
- We're shipping with a known asymmetry — the marketing pitch says "another desktop" but it's not. We have to be honest in onboarding copy.
- Adding real virtualization later is real work and *not* on the v1 critical path — we may end up living with the illusion much longer than planned.

### Neutral / trade-offs

- Many tasks users want Swoosh for *don't* need real isolation (research, summarization, file-organization). The illusion is functionally adequate for those.
- The destructive-action confirmation flow is annoying but necessary — and tunable per task (the "trust me for this task" checkbox in `specs/10`).
- This is fundamentally a security trade-off masked as a UX choice. Be honest about that in user-facing docs.

## Notes

- Memory note `memory/swoosh_isolation_strategy.md` records this decision in the agent's persistent memory so future Claude Code sessions don't relitigate it without going back to Farza.
- "When does real virtualization land?" is intentionally not committed. Phase S4 in `specs/10` is a placeholder.
- This ADR may be superseded by a future ADR titled *"Swoosh moves to Virtualization.framework"* when the work actually happens.
