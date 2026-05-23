# Clicky — Documentation

Three kinds of documents live here, in three folders:

| Folder | What it contains | When to read it |
|--------|------------------|-----------------|
| [`reference/`](./reference/) | Audit of the system **as it is today**. | Onboarding, before you touch a feature, after every major refactor. |
| [`specs/`](./specs/) | RFCs for things we're **going to build**. | Before starting work on a new feature; cite-by-number in commits and PRs. |
| [`adr/`](./adr/) | **Why** each architectural decision was made — immutable log. | When you're about to change something foundational and need the original reasoning. |

The single sequencing document is [`00-roadmap.md`](./00-roadmap.md) at this folder's root — it pulls the phased rollouts from every spec into one ordered list and tracks status.

## Quick map

```
docs/
├── 00-roadmap.md                    ← what ships in which phase
├── README.md                        ← you are here
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
│   └── 16-tier-3-polish.md
└── adr/                             ← decisions, immutable once accepted
    ├── README.md                    ← ADR index + process
    ├── 0000-template.md
    ├── 0001-menu-bar-only-app.md
    ├── … (0001–0014: retroactive, document existing system)
    ├── 0015-plugin-system-declarative-manifests.md
    └── … (0015–0023: planned decisions for upcoming features)
```

## Reading order, by goal

### "I'm new — bring me up to speed"

1. [`00-roadmap.md`](./00-roadmap.md) — get the big picture and the sequencing.
2. [`reference/01-overview.md`](./reference/01-overview.md) — what the product is.
3. [`reference/02-system-design.md`](./reference/02-system-design.md) — how it works under the hood.
4. [`adr/`](./adr/) ADRs 0001–0014 — *why* the existing pieces are the way they are.

### "I'm about to add a feature"

1. [`00-roadmap.md`](./00-roadmap.md) — confirm what phase you're in.
2. The relevant spec(s) under [`specs/`](./specs/) — read end-to-end before writing code.
3. The relevant retroactive ADRs that the feature touches.
4. [`specs/14-testing-strategy.md`](./specs/14-testing-strategy.md) — write tests first.
5. After landing, write a new ADR if a non-trivial decision was made.

### "I'm refactoring something"

1. [`specs/13-folder-structure-fsd.md`](./specs/13-folder-structure-fsd.md) — make sure the destination shape is right.
2. [`reference/04-file-reference.md`](./reference/04-file-reference.md) — know what's actually in the file you're moving.
3. [`specs/14-testing-strategy.md`](./specs/14-testing-strategy.md) — green before green.

### "I'm reviewing this work"

[`00-roadmap.md`](./00-roadmap.md) for context, then jump to the spec or ADR being touched.

## What lives in each spec

| # | Spec | One-liner |
|---|------|-----------|
| 09 | [Plugin system](./specs/09-plugin-system-design.md) | Users describe behaviors in language → Claude emits a JSON manifest → runtime executes against a fixed primitive set. |
| 10 | [Swoosh Mode](./specs/10-swoosh-mode-design.md) | Long-running agentic tasks with a "send Clicky to another desktop" UX illusion; successful runs compile into deterministic plugins. |
| 11 | [Offline & local models](./specs/11-offline-and-local-models.md) | Cloud / Hybrid / Local modes. OCR + Foundation Models pointing. MLX-Swift for VLMs. |
| 12 | [Vector search & memory](./specs/12-vector-search-and-memory.md) | On-device embeddings for conversation memory, intent routing, and opt-in screen memory. |
| 13 | [FSD folder structure](./specs/13-folder-structure-fsd.md) | Vertical-slice layout with strict layer-import rules. Six-PR migration plan. |
| 14 | [Testing strategy](./specs/14-testing-strategy.md) | XCTest, the test pyramid, TDD policy, CI workflow, ~70 starter tests. |
| 15 | [Feature improvements](./specs/15-feature-improvements.md) | 10 mechanical cleanups + 9 behavior improvements + 10 polish items surfaced by the audit. |
| 16 | [Tier-3 polish](./specs/16-tier-3-polish.md) | Mini-specs for four Tier-3 polish items: panic clear, in-app feedback form, latency readout, login-item opt-in. |

## What lives in each ADR

The ADR index lives in [`adr/README.md`](./adr/README.md). Twenty-three ADRs total:

- **0001–0014** — *Retroactive.* Document decisions already in the codebase (menu-bar app, Worker proxy, CGEvent tap, ScreenCaptureKit, NSPanels, in-memory history, sandbox off, AI provider stack, TLS warmup, POINT protocol, PostHog, Sparkle, Mux video, leanring misspelling).
- **0015–0023** — *Planned.* Decisions for upcoming work (declarative plugin manifests, Swoosh illusion, Swoosh-to-plugin compile, mode picker, OCR-pointing, MLX-Swift VLMs, on-device vector search, FSD, TDD).

## How this doc was built

The reference docs came from a direct read of every Swift source, the Worker, scripts, and project metadata in May 2026. The specs were written in design discussions and validated against the reference docs. The ADRs were extracted from the same audit (0001–0014) and from the spec discussions (0015–0023). Everything has a verifiable source — if a fact here doesn't match the code, the code is right and the doc needs an update.

When you change the codebase, update the relevant reference doc, the relevant spec (or its `Status` if it's now shipped), and the corresponding `00-roadmap.md` line. Keep the three layers in sync.
