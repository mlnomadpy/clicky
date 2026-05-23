# ADR 0022 — Adopt Feature Slice Design for folder structure

**Status**: Proposed
**Date**: 2026-05-22
**Deciders**: Farza, Claude Code session
**Source spec**: `docs/specs/13-folder-structure-fsd.md`

## Context

The `leanring-buddy/` source tree is 22 Swift files in one flat directory. Three files (`CompanionManager.swift`, `OverlayWindow.swift`, `BuddyDictationManager.swift`) account for 2773 LOC — over a third of the codebase. The specs in `09–12` propose ~15 more files (plugin runtime, Swoosh runtime, local-models runtime, vector memory). Flat doesn't scale.

We considered three layouts:

1. **Keep flat.** Lowest effort, but the audit already shows two god-objects forming (`CompanionManager`, `OverlayWindow`) and the spec work would make it worse.
2. **Horizontal layering** — group by type: `Models/`, `Views/`, `Services/`, `ViewModels/`. Familiar to iOS developers from MVC/MVVM templates. Cross-feature changes touch many folders.
3. **Vertical slicing (FSD)** — group by feature: `VoicePipeline/`, `CursorOverlay/`, `Plugins/`, etc. Each slice owns its UI, state, types, and tests. A feature is a folder.

FSD originated in the frontend (React/Vue) world but the *principle* — co-locate everything for a vertical slice of behavior — applies cleanly to a macOS app of Clicky's size.

## Decision

Adopt Feature Slice Design with this top-level structure:

```
leanring-buddy/
├── App/                  ← entry point, app-level wiring
├── Features/             ← one folder per vertical slice
├── Entities/             ← cross-feature domain types
├── Shared/               ← truly cross-cutting (DS, analytics, logging)
├── State/                ← coordinators that span multiple features
└── Resources/            ← non-code bundled assets
```

Layer import rules are strict and structural:

```
App ────────► everything
State ──────► Features, Entities, Shared
Features ───► Entities, Shared
Entities ───► Shared
Shared ─────► (nothing)
```

Cross-feature imports (`Features/X` → `Features/Y`) are forbidden. If two features need to coordinate, they do so through an `Entity`, a `State` coordinator, or a `NotificationCenter` post.

The migration is six PRs, each mechanical (no behavior change), detailed in `docs/specs/13-folder-structure-fsd.md`.

## Consequences

### Positive

- Files with a shared responsibility live in the same folder. Finding code is *"what feature does this belong to?"* instead of *"what type of file am I looking for?"*
- New features get a clear home. The plugin / Swoosh / local-models / vector-memory specs each map to one `Features/X/` directory.
- The import rules are mechanically enforceable. A linter or build script can fail PRs that violate them. (We'll add this in Phase 0 once the rules are real.)
- The three big files (`CompanionManager`, `OverlayWindow`, `BuddyDictationManager`) get surgical decomposition during the migration — every extracted piece has a feature folder to land in.
- New contributors orient quickly. Open `Features/`, pick the slice that matches the task, work inside it.

### Negative

- Migration is real work — six PRs of mechanical file moves with corresponding import-statement updates. No new user-visible features ship during this.
- The pattern is unfamiliar to iOS/macOS developers used to MVC / MVVM / TCA conventions. Onboarding cost for new contributors.
- Some files don't fit neatly into a single slice (e.g., `DesignSystem.swift` legitimately spans the codebase) — those go in `Shared/`, but the boundary judgment is occasionally subjective.
- The `State/` layer is a small concession to FSD purity. Classic FSD has no top-level state directory. We have one because the existing `CompanionManager` is too big to deconstruct in one step — we land coordinator types in `State/` during the migration and shrink the layer over time.
- A bad import gets caught at build time, but a *misplaced* file (in the wrong slice) won't. Code review has to catch it.

### Neutral / trade-offs

- We're not introducing Swift Package Manager modules. Each `Features/X/` is a folder, not a package. SPM modules would enforce the import rules at the compiler level but add real build complexity. Worth revisiting around ~100 source files.
- The renamed `App/ClickyApp.swift` (formerly `leanring_buddyApp.swift`) is the only file that gets a true *rename* during the migration. The `leanring-buddy` directory and target name stay misspelled per [ADR 0014](./0014-keep-leanring-misspelling.md).

## Notes

- The migration freezes feature work for the duration. Phase 0 in the roadmap reserves this slot explicitly.
- Tests (`docs/specs/14-testing-strategy.md`) mirror the same folder structure under `leanring-buddyTests/Features/`. A new test file's path is mechanically derivable from the source file's path.
- This ADR may be partially superseded if we ever adopt SPM modules — the layer rules would become compiler-enforced and the directory shape might change. Not in 2026.
