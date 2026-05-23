# ADR 0015 — Plugin system uses declarative manifests, not embedded code

**Status**: Proposed
**Date**: 2026-05-22
**Deciders**: Farza, Claude Code session
**Related**: [ADR 0017](./0017-compile-swoosh-to-plugin.md), [ADR 0019](./0019-ocr-and-foundation-models-pointing.md), [ADR 0023](./0023-test-driven-development.md)
**Source spec**: `docs/specs/09-plugin-system-design.md`

## Context

Clicky needs to be user-extensible. The product target is *"users add new behaviors by describing them in language, no code from us."* The naive shape of that — let an LLM write Swift / JavaScript / Python and execute it — is a security disaster (RCE on the user's machine by design) and an operational nightmare (sandboxing arbitrary code on macOS is its own multi-quarter project).

The alternative shape — let plugins be data, not code — is well-trodden in other ecosystems (Shortcuts, Raycast extensions in restricted JS, Hammerspoon's Lua subset). We pick a strict version of that pattern.

We considered three alternatives:

1. **Sandboxed scripting language** (Lua, restricted JS, Wasm). Powerful, well-understood, but real isolation on macOS is hard, and the security review for *any* user-authored script becomes substantial. Also a maintenance burden — every host upgrade risks breaking user scripts.
2. **Compiled SwiftPM packages** signed by Clicky's CI. Maximum power, zero usability — users would have to write Swift.
3. **Declarative JSON manifests over a fixed primitive catalogue.** Plugins describe what they do; the host runtime decides how. Constrained but composable.

## Decision

Plugins are JSON manifests conforming to a schema bundled with the app. Each manifest declares a trigger, optional conditions, and an ordered list of actions. Actions reference *primitives* — named capabilities implemented in Swift by us (capture_screen, prompt_claude, file_write, etc.). The primitive set is closed at compile time; plugins cannot extend it.

The plugin generator (Claude with a specific system prompt) takes the user's natural-language description and emits a manifest. The schema goes into the system prompt so the model sees the exact shape it must produce. Hallucinated primitive names are rejected at install time; the validation error is fed back to the model with one retry.

Scopes (file paths the plugin can write, domains it can hit, opt-in to AppleScript/shell) are mandatory and approved by the user at install. The runtime enforces them at every primitive call, not just at install.

## Consequences

### Positive

- The blast radius of a malicious or buggy plugin is bounded by the primitive set. We can't add a "send email" capability the runtime didn't ship with.
- We can audit the entire surface area of "what plugins can do" by reading one file — `PrimitiveRegistry.swift`.
- Plugins are inspectable as JSON. A user (or a security-conscious admin) can read a manifest before installing without compiling anything.
- The primitive set is shared with Swoosh ([ADR 0017](./0017-compile-swoosh-to-plugin.md)), which keeps the two runtimes compatible.
- Schema validation lets us reject hallucinated capabilities without writing custom guardrails for each.

### Negative

- Expressiveness ceiling. Anything that needs control flow beyond "if condition then run this sequence" requires the LLM to do the work inside a `prompt_*` action. Users with programming instincts may chafe.
- Adding a new primitive requires a Clicky release. Users can't ship their own.
- We become responsible for the safety boundary of every primitive. If `file_write` is buggy and writes outside its declared scope, every plugin inherits the bug.
- The schema is now a versioned product surface. We promise to be backward-compatible forever (per `09`'s versioning section); breaking the schema breaks every installed plugin.

### Neutral / trade-offs

- We're explicitly choosing security and reviewability over expressiveness. A user who needs more should reach for Shortcuts / Hammerspoon — and we say so in the docs.
- The plugin generator's quality (how well Claude emits valid manifests) is now a load-bearing piece of the product. Phase 0 of the spec validates this works before user-authored plugins ship.

## Notes

- The primitive catalogue is documented in `docs/specs/09-plugin-system-design.md` and extended by `docs/specs/11-offline-and-local-models.md` (local-models primitives) and `docs/specs/12-vector-search-and-memory.md` (vector primitives).
- Future ADRs may revisit if we ever allow sandboxed scripting. We don't reject the idea forever — we just say "not in v1."
- The `applescript` and `shell` primitives exist in the schema but are opt-in per-install and never offered by the generator. This is a deliberate "escape hatches that adults can use" design.
