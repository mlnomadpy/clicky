# ADR 0017 — Successful Swoosh runs compile into deterministic plugins

**Status**: Proposed
**Date**: 2026-05-22
**Deciders**: Farza, Claude Code session
**Related**: [ADR 0015](./0015-plugin-system-declarative-manifests.md), [ADR 0016](./0016-swoosh-illusion-then-virtualization.md), [ADR 0018](./0018-cloud-hybrid-local-mode-picker.md)
**Source spec**: `docs/specs/10-swoosh-mode-design.md`
**Related memory**: `memory/swoosh_saves_as_plugin.md`

## Context

Swoosh's agent loop uses Claude with Computer Use. Realistic per-task cost is $1–5; pathological runs can hit $20+. The naive product — *"every task is a fresh agent run"* — is unaffordable for daily use and ruinous for power users.

The user identified this concern early: tasks that succeed tend to *recur*. The same person who Swooshed "summarize today's GitHub activity into my notes" yesterday will Swoosh approximately the same thing tomorrow. Paying for a fresh agent loop every time is wasteful when the previous trace already encodes a working solution.

We considered three approaches:

1. **Cache the agent's output** by task description. Cheap but useless — the output is task-specific and stale within hours.
2. **Cache the agent's trajectory** (which tools it called, in what order). Replayable but rigid — fails when the UI changes.
3. **Compile the trace into a deterministic plugin** using the same primitive catalogue as user-authored plugins. Replays via the cheap plugin runtime, with optional per-step agent-fallback if a deterministic step fails.

## Decision

After a successful Swoosh run, the user is offered *Save as plugin*. If they accept, the Swoosh recorder's trace (every observation, decision, tool call, and result) is passed through a one-shot Claude call that:

1. Strips exploration (dead-end branches).
2. Maps each agent tool call to its corresponding plugin primitive (the plugin and Swoosh catalogues are designed to share primitives — see [ADR 0015](./0015-plugin-system-declarative-manifests.md)).
3. Parameterizes literal values that should become inputs next time (filenames, URLs).
4. Emits a plugin manifest conforming to the Phase-2 schema.

The user reviews and installs the manifest through the standard plugin install UX. Future invocations of the same task hit the deterministic plugin runtime — no agent loop, no Claude turn, ~0 cost.

A per-step `swoosh_fallback: true` flag (default `false`) lets a compiled plugin re-enter agent mode for just the failed step. Useful for steps that depend on web pages or UIs that drift.

## Consequences

### Positive

- The "expensive once, free forever" cost curve is the answer to *"how does Swoosh stay affordable at scale."* The more users save their successful runs, the less the agent loop runs.
- Compiled plugins are inspectable JSON, just like user-authored ones. The user can edit, share, version them.
- Local-mode users (per [ADR 0018](./0018-cloud-hybrid-local-mode-picker.md)) can run Cloud-mode-authored Swoosh-compiled plugins for free forever, as long as the plugin's primitives have local equivalents (most of the perception ones do; the planning ones don't).
- The primitive-catalogue contract from [ADR 0015](./0015-plugin-system-declarative-manifests.md) is doing more work than we expected — it's the *interlingua* between agent traces and replayable plugins.

### Negative

- Compilation is itself a Claude call (one-shot, but real cost). At ~$0.10–0.30 per compile, it's small relative to the agent run, but not free.
- A compiled plugin is brittle to UI changes — if the *Save* button moves, the deterministic click coordinates miss. `swoosh_fallback: true` mitigates but doesn't eliminate this.
- The compiler can confidently rewrite obvious patterns but may be too aggressive at parameterization, producing plugins that need fiddly arguments. The user-review step before install is the safety valve.
- Plugins compiled from Swoosh need the same scope review as user-authored ones, which adds friction to the "save this!" moment. Worth it for safety.

### Neutral / trade-offs

- The compiled plugin and the original Swoosh task are decoupled — editing the plugin doesn't propagate back to the Swoosh history. Versioning question for later (probably never worth solving).
- This is a feature designed for *recurring* tasks. One-off tasks won't benefit from save-as-plugin and the UI shouldn't push it on them.

## Notes

- Memory note `memory/swoosh_saves_as_plugin.md` records this decision in the agent's persistent memory.
- The compiler runs on Sonnet, not Opus, even when the original Swoosh used Opus — translation is less demanding than planning.
- A potential future enhancement: *re-compile* a plugin from its execution log if it has been used many times and the agent could improve it. Out of scope for v1.
