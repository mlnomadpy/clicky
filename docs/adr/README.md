# Architecture Decision Records

This folder is the immutable log of architectural decisions that shaped Clicky. Each file captures a single decision, the context that forced it, and the consequences it locks in.

ADRs 0001 through 0014 are *retroactive* — they document choices that were already in the codebase before the docs effort. ADRs from 0015 onward will be written *before* the code that depends on them lands.

## How to use this folder

- **Read top-down** if you're new — the early ADRs explain why the app is shaped the way it is.
- **Look up the latest ADR on a topic** if you're about to make a change. Cross-references between ADRs make this practical.
- **Never edit a past ADR**. If a decision changes, write a new ADR and set the old one's status to `Superseded by ADR NNNN`.

The template is in [`0000-template.md`](./0000-template.md). The roadmap (`../00-roadmap.md`) drives the order of work; this folder records the *why* behind each piece.

## ADR process

Write an ADR when:

- You're about to make a non-trivial architectural decision (a new framework, a new external dependency, a new pattern that the rest of the codebase will follow).
- You're about to *deliberately* not do something (e.g., "we are not adding persistence to conversation history"). Negative-space decisions matter as much as positive ones.
- You're undoing a previous decision. Write a new ADR; mark the old one superseded.

Don't write an ADR for:

- Bug fixes.
- Renaming a variable.
- Switching a library version.
- Anything covered by an existing ADR.

### Lifecycle

1. **Propose**: Draft the ADR with `Status: Proposed`. Cite specific files. Discuss in review.
2. **Accept**: When merged to `main`, change `Status: Accepted` (or `Accepted (retroactive)` for documentation of existing code).
3. **Supersede**: Never edit an accepted ADR's substantive content. If a decision changes, write a new ADR and update only the old one's `Status` line to `Superseded by ADR NNNN` and add a one-line note in the Notes section linking forward.

Numbering is permanent once an ADR lands. Reserve the next number, write the file, merge it.

## Index

| # | Title | Summary |
|---|-------|---------|
| [0000](./0000-template.md) | Template | Copy this when writing a new ADR. |
| [0001](./0001-menu-bar-only-app.md) | Menu-bar-only application | `LSUIElement=true`, no Dock icon, no main window — ambient by design. |
| [0002](./0002-cloudflare-worker-proxy.md) | Cloudflare Worker as API proxy | All third-party API keys live server-side; the binary ships zero rotatable secrets. |
| [0003](./0003-cgevent-tap-for-global-shortcut.md) | Listen-only CGEvent tap | Reliable modifier-only-hotkey detection while another app is foreground. |
| [0004](./0004-screencapturekit.md) | ScreenCaptureKit for screenshots | macOS 14.2+, multi-monitor parallel capture, excludes our own windows. |
| [0005](./0005-nspanel-everywhere.md) | Borderless non-activating NSPanels | Every visible surface is an `NSPanel` so the app never steals focus. |
| [0006](./0006-in-memory-conversation-history.md) | In-memory conversation history (10 turns) | No on-disk persistence; vector-search is the planned successor. |
| [0007](./0007-sandbox-disabled.md) | App sandbox disabled | Required for the CGEvent tap and Accessibility API; rules out Mac App Store. |
| [0008](./0008-ai-provider-stack.md) | Claude + AssemblyAI + ElevenLabs | Active provider stack, with Apple Speech / OpenAI as configured alternatives. |
| [0009](./0009-tls-warmup-and-shared-urlsession.md) | TLS warmup + shared URLSession | Two production-bug fixes: cold-handshake errSSL -1200 and reconnect socket errors. |
| [0010](./0010-text-based-point-protocol.md) | `[POINT:x,y:label:screenN]` tag | Pointing data rides the same SSE stream as spoken text — no extra round-trip. |
| [0011](./0011-posthog-with-full-payloads.md) | PostHog with full transcripts and responses | Privacy posture: full payloads to PostHog; no in-app opt-out today. |
| [0012](./0012-sparkle-and-login-item.md) | Sparkle auto-update + `SMAppService` login item | EdDSA-signed appcast feed; currently disabled at call site. |
| [0013](./0013-mux-hosted-onboarding-video.md) | Mux-hosted HLS onboarding video | Keeps the DMG small; the video can be edited without an app release. |
| [0014](./0014-keep-leanring-misspelling.md) | Keep "leanring" misspelled | Renaming churns TCC permissions, signing identity, Sparkle feed — not worth it. |
| [0015](./0015-plugin-system-declarative-manifests.md) | Plugin system uses declarative manifests | No scripting language; plugins compose a fixed primitive set; schema validation rejects hallucinated capabilities. |
| [0016](./0016-swoosh-illusion-then-virtualization.md) | Swoosh ships as a UX illusion, virtualization later | Agent runs on the real Mac; `SwooshHost` abstraction lets us swap in a VM / remote sandbox without redesign. |
| [0017](./0017-compile-swoosh-to-plugin.md) | Successful Swoosh runs compile into plugins | "Expensive once, free forever" — recurring tasks migrate from agent loops to deterministic replays. |
| [0018](./0018-cloud-hybrid-local-mode-picker.md) | Cloud / Hybrid / Local mode picker | A single named-mode setting governs all AI routing; Local mode means no network, no Swoosh. |
| [0019](./0019-ocr-and-foundation-models-pointing.md) | Local pointing via Vision OCR + Foundation Models | Sidesteps pixel-coordinate prediction — sub-task becomes classification over OCR boxes. |
| [0020](./0020-mlx-swift-for-vlms.md) | MLX-Swift hosts local VLMs | No Ollama dependency; SPM-integrated; we own the model lifecycle. |
| [0021](./0021-on-device-vector-search.md) | On-device vector search | `NLContextualEmbedding` + `sqlite-vec`. Zero cloud, zero ongoing cost. |
| [0022](./0022-feature-slice-design.md) | Feature Slice Design folder structure | Vertical slices per feature, strict layer-import rules, no horizontal `Models/`/`Views/` directories. |
| [0023](./0023-test-driven-development.md) | TDD policy for all post-Phase-0 work | Tests precede new contracts and bug fixes; CI gates merges; no coverage gate. |

## Where to next

- **What exists today**: `../reference/` documents the system as audited.
- **What we're going to build**: `../specs/` holds the RFCs for upcoming work.
- **Sequencing**: `../00-roadmap.md` is the single source of truth for what ships when.

When a planned feature in `specs/` ships, its design decisions land here as new ADRs (`0015+`). The roadmap lists which ADRs each upcoming feature is expected to need.
