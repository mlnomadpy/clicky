# Clicky — Master Roadmap

> Living document. Tracks everything we've decided, everything we're building, and the order we ship it in. When you finish a phase, update the status here.

## How to use this document

- **Reference docs** (`docs/reference/`) describe Clicky *as it is today*. Re-read after every major refactor.
- **Specs** (`docs/specs/`) are RFCs for things we're going to build. Each spec ends with a Phased Rollout section that this roadmap aggregates.
- **ADRs** (`docs/adr/`) capture the *why* behind each decision, in chronological order. Never edit a past ADR — supersede it with a new one.
- **This file** is the single place where the *order of work* lives. If a phase moves, change it here, not in the specs.

## Doc folder map

```
docs/
├── 00-roadmap.md                    ← you are here
├── README.md                        ← index
├── reference/                       ← what exists today (audit)
│   ├── 01-overview.md
│   ├── 02-system-design.md
│   ├── 03-features.md
│   ├── 04-file-reference.md
│   ├── 05-cloudflare-worker.md
│   ├── 06-build-and-release.md
│   ├── 07-permissions-and-privacy.md
│   └── 08-data-and-config.md
├── specs/                           ← what we're going to build (RFCs)
│   ├── 09-plugin-system-design.md
│   ├── 10-swoosh-mode-design.md
│   ├── 11-offline-and-local-models.md
│   ├── 12-vector-search-and-memory.md
│   ├── 13-folder-structure-fsd.md
│   ├── 14-testing-strategy.md
│   ├── 15-feature-improvements.md
│   ├── 16-tier-3-polish.md
│   └── wave2-pbxproj-surgery.md    ← investigation, kept for archaeology
└── adr/                             ← decisions, immutable once accepted
    ├── 0000-template.md
    ├── 0001-menu-bar-only-app.md
    ├── 0002-cloudflare-worker-proxy.md
    └── …                            (0003–0023; see adr/README.md for the index)
```

## Status legend

- ⏺ **Done** — shipped, in the codebase
- ◐ **In progress** — actively being worked on
- ○ **Planned** — spec written, not started
- ◌ **Sketched** — discussed, not specced
- × **Rejected / superseded** — kept for history

## The work, in shipping order

The order below is the recommended sequence. Items in the same phase can be parallelized; phases should not be reordered without a roadmap update.

### Phase 0 — Stabilize the foundation

We refactor the codebase before adding new features. Without this, every new feature accretes onto an already-too-large `CompanionManager`.

| Item | Owner | Status | Spec |
|------|-------|--------|------|
| Adopt Feature Slice Design folder structure | — | ○ | `specs/13-folder-structure-fsd.md` |
| Establish testing strategy + starter tests | — | ◐ | `specs/14-testing-strategy.md` (swift-testing adopted; 18 starter tests landed for `PointTagParser` + `PointCoordinateMath`; CI workflow on disk but gated by fork-Actions consent) |
| Apply audit-driven feature improvements (low-risk cleanups) | — | ◐ | `specs/15-feature-improvements.md` (Tier 1: §1.1, §1.3, §1.4, §1.5, §1.6, §1.9 shipped; §1.2, §1.7, §1.8, §1.10 pending) |
| Remove dead code (OpenAIAPI.swift, ElementLocationDetector.swift, legacy WPM helpers) | — | ⏺ | `specs/15-feature-improvements.md` §1.4–§1.6 |
| Re-enable Sparkle auto-update | — | ⏺ | `specs/15-feature-improvements.md` §1.1 (commit `be8bd80`) |
| Extract Claude system prompts to a focused file | — | ⏺ | `specs/15-feature-improvements.md` §1.9 (commit `a4fe403`) |
| Extract `PointTagParser` + `PointCoordinateMath` from `CompanionManager` | — | ⏺ | `specs/15-feature-improvements.md` §1.3 (commit `eeea49c`) |
| CI workflow + local test runner | — | ◐ | `specs/14-testing-strategy.md` (workflow files on disk, fork Actions consent pending) |
| Worker vitest suite (17 tests) | — | ⏺ | `specs/14-testing-strategy.md` open question #5 (commit `2c752d5`) |
| Tier-3 polish mini-specs (panic clear, feedback form, latency metric, login-item opt-in) | — | ⏺ | `specs/16-tier-3-polish.md` |
| Write ADRs for the existing system (0001–0014) | — | ⏺ | `adr/` |
| Write ADRs for planned decisions (0015–0023) | — | ⏺ | `adr/` |

Exit criteria: no file over 600 LOC in the renamed slices; tests pass on CI (blocked by fork-Actions consent at https://github.com/mlnomadpy/clicky/actions); ADRs 1–14 merged.

### Phase 1 — Local-mode foundations (cheap wins, no new product surface)

These ship existing features more cheaply without introducing user-facing complexity.

| Item | Status | Spec |
|------|--------|------|
| Phase L0: `tts_local` primitive (`AVSpeechSynthesizer` Neural voices) | ○ | `specs/11-offline-and-local-models.md` §Phased rollout |
| Phase L1: `SpeechAnalyzer` as a transcription provider option | ○ | same |
| Phase L2: OCR-pointing trick wired in Hybrid mode | ○ | same |

Exit criteria: an internal toggle lets the team flip to Hybrid mode; observable cost drop in the next telemetry window.

### Phase 2 — Plugin system kernel

| Item | Status | Spec |
|------|--------|------|
| Phase P0: `PluginRuntime` + `PluginManifest` + `PluginStore` types, default flow expressed as a bundled manifest | ○ | `specs/09-plugin-system-design.md` |
| Phase P1: 3–5 first-party plugins shipped in the bundle | ○ | same |
| Vector search Phase V1: conversation-memory retrieval (the cheap, high-value piece) | ○ | `specs/12-vector-search-and-memory.md` |

Exit criteria: the existing voice flow runs through the runtime; first-party plugins enable/disable from the panel; conversation memory retrieves older relevant turns.

### Phase 3 — User-authored plugins + mode picker

| Item | Status | Spec |
|------|--------|------|
| Phase P2: in-app chat-based plugin authoring UI | ○ | `specs/09-plugin-system-design.md` |
| Phase L3: Foundation Models (`prompt_apple_local`) primitive | ○ | `specs/11-offline-and-local-models.md` |
| Phase L4: Cloud / Hybrid / Local mode picker in panel | ○ | same |
| Vector search Phase V2: `voice_intent` plugin trigger via semantic similarity | ○ | `specs/12-vector-search-and-memory.md` |

Exit criteria: a user can describe a plugin in language, approve scopes, install, run; mode setting is visible and effective.

### Phase 4 — Swoosh + heavy local models

| Item | Status | Spec |
|------|--------|------|
| Phase S0–S2: Swoosh runtime, internal UX, public preview with budget caps | ○ | `specs/10-swoosh-mode-design.md` |
| Phase L5: MLX-Swift VLM + model-management sheet | ○ | `specs/11-offline-and-local-models.md` |
| Phase L6: Network-allowlist enforcement + audit panel | ○ | same |
| Vector search Phase V3: screen memory (opt-in, behind feature flag) | ○ | `specs/12-vector-search-and-memory.md` |

Exit criteria: a user can run a Swoosh task end-to-end with budget caps; Local mode actually means no network; screen memory works with the feature flag on.

### Phase 5 — Compile-on-save + community

| Item | Status | Spec |
|------|--------|------|
| Phase S3: Swoosh trace → plugin manifest compilation | ○ | `specs/10-swoosh-mode-design.md` |
| Phase P3: shareable plugin URLs with install-time security review | ○ | `specs/09-plugin-system-design.md` |
| Phase P4 (post-MVP): signed third-party primitive bundles | ◌ | `specs/09-plugin-system-design.md` |
| Phase S4 (post-MVP): real virtualization for Swoosh (`Virtualization.framework` or remote sandbox) | ◌ | `specs/10-swoosh-mode-design.md` + `memory/swoosh_isolation_strategy.md` |

Exit criteria: a successful Swoosh becomes a deterministic plugin; community plugins install through a security-review screen.

## Cross-cutting policies adopted during Phase 0

These are not features — they are process changes that compound over time.

- **Feature Slice Design** (`specs/13-folder-structure-fsd.md`) — every new file goes into a feature slice, never into a flat top-level dir.
- **Unit-test-driven** (`specs/14-testing-strategy.md`) — every new bug fix lands with a failing test first; every new primitive in the plugin/Swoosh catalogue lands with at least one happy-path and one failure-path test.
- **ADR-first decisions** — non-trivial architectural decisions land as an ADR before the code that depends on them. The ADR template is in `adr/0000-template.md`.
- **Spec-first features** — anything beyond a small bug fix or rename starts with an RFC in `specs/`.

## ADR backlog

A non-exhaustive list of ADRs to write before Phase 0 closes. The numbering becomes immutable once each file lands. See `adr/0000-template.md` for the format.

### Documenting existing decisions (from the audit)

- `0001-menu-bar-only-app.md` — `LSUIElement=true`, no Dock icon
- `0002-cloudflare-worker-proxy.md` — all third-party API keys live server-side
- `0003-cgevent-tap-for-global-shortcut.md` — listen-only `CGEventTap` vs `NSEvent.addGlobalMonitorForEvents`
- `0004-screencapturekit.md` — choose `SCScreenshotManager` over `CGWindowList`
- `0005-nspanel-everywhere.md` — borderless non-activating panels for both the menu-bar dropdown and the cursor overlays
- `0006-in-memory-conversation-history.md` — last-10-turns, no persistence
- `0007-sandbox-disabled.md` — required for the CGEvent tap + Accessibility API
- `0008-ai-provider-stack.md` — Claude (primary) + AssemblyAI (transcription) + ElevenLabs (TTS) + Apple Speech (fallback)
- `0009-tls-warmup-and-shared-urlsession.md` — HEAD-request warmup and one-session-per-host
- `0010-text-based-point-protocol.md` — `[POINT:x,y:label:screenN]` tag vs structured tool use
- `0011-posthog-with-full-payloads.md` — analytics ships the full transcript + response text
- `0012-sparkle-and-login-item.md` — Sparkle EdDSA-signed auto-update, `SMAppService` login item
- `0013-mux-hosted-onboarding-video.md` — streamed HLS instead of bundled MP4
- `0014-keep-leanring-misspelling.md` — directory and scheme name stay misspelled for legacy reasons

### Documenting planned decisions (from the specs)

- `0015-plugin-system-declarative-manifests.md` — no scripting language; fixed primitive set
- `0016-swoosh-illusion-then-virtualization.md` — UX illusion in v1, real isolation later
- `0017-compile-swoosh-to-plugin.md` — successful agent traces become deterministic plugins
- `0018-cloud-hybrid-local-mode-picker.md` — three-mode user setting
- `0019-ocr-and-foundation-models-pointing.md` — sidestep pixel inference with OCR bounding boxes
- `0020-mlx-swift-for-vlms.md` — chosen over Ollama for installation simplicity
- `0021-on-device-vector-search.md` — Apple `NLContextualEmbedding` + `sqlite-vec`
- `0022-feature-slice-design.md` — folder layout adoption
- `0023-test-driven-development.md` — unit-test-first policy

ADR numbers are reserved when this roadmap lands; the file content arrives during Phase 0.

## Definition of "done" for each spec

For a spec to leave `specs/` and enter `reference/`:

1. All phases in the spec are at status ⏺ Done.
2. Every primitive / behavior in the spec is covered by tests (`specs/14-testing-strategy.md`).
3. The corresponding ADRs are accepted (not proposed).
4. The reference doc(s) — `03-features.md`, `02-system-design.md`, `04-file-reference.md`, `08-data-and-config.md` — are updated to describe the new surface.
5. A line on this roadmap is moved from "Planned" to "Done."

A spec is not deleted after shipping — it stays in `specs/` for archaeological context. Add a `Status: shipped` banner at the top.

## Glossary of terms used across docs

- **Primitive** — a built-in capability the plugin/Swoosh runtimes can call (e.g., `capture_screen`, `prompt_claude`). The set is fixed at compile time. Plugins and Swoosh agents compose primitives; they don't define new ones.
- **Mode** — Cloud / Hybrid / Local. A user-visible setting that gates which primitives are available and where LLM calls go.
- **Manifest** — the declarative JSON description of a plugin.
- **Trace** — the recorded sequence of (observation, decision, tool_call, result) tuples a Swoosh agent produces during a run.
- **Compile-on-save** — the act of turning a successful Swoosh trace into a plugin manifest.
- **Illusion** — the v1 Swoosh approach where the agent runs on the user's real Mac but the UX makes it look like a separate desktop. Slated for replacement by real virtualization in a later phase.
- **Slice** — a feature folder under the FSD layout. Owns its UI, state, types, and tests.
