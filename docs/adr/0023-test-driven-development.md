# ADR 0023 — Adopt test-driven development for all work after Phase 0

**Status**: Proposed
**Date**: 2026-05-22
**Deciders**: Farza, Claude Code session
**Related**: [ADR 0022](./0022-feature-slice-design.md)
**Source spec**: `docs/specs/14-testing-strategy.md`

## Context

Clicky's test suite today is two Xcode-generated stub files and a launch test. The release script does not run tests. Verification has been "Cmd+R and try it" — workable while the codebase was one developer and one flow.

The roadmap (`docs/00-roadmap.md`) commits to a substantial refactor (FSD restructure per [ADR 0022](./0022-feature-slice-design.md)) followed by four new subsystems (plugins, Swoosh, local models, vector memory). Each subsystem ships a handful of primitives that other parts of the app *compose*. A single broken primitive will break many plugins. A regression in the FSD migration will be invisible without tests.

We considered three policies:

1. **No tests / status quo.** Cheap now, expensive forever. Every refactor becomes high-stakes.
2. **Tests-after** — write code, then add tests. Common but produces tests that confirm what the code does, not what it should do. Tests become an afterthought and rot.
3. **Test-driven** — for new contracts (primitives, parsers, coordinators), tests come *first*. For bug fixes, a failing test reproduces the bug *before* the fix lands.

## Decision

Adopt test-driven development for all work after Phase 0, with the following rules:

- **Bug fixes**: a failing test that exhibits the bug lands in the same commit as the fix.
- **New primitives** (plugin/Swoosh catalogue): tests written first. At minimum a happy path + each declared failure mode.
- **New coordinators** (`State/<Flow>Coordinator.swift`): state-transition tests before the coordinator.
- **Refactors**: existing tests stay green. If a refactor exposes untested behavior, the test lands first.
- **CI**: tests run on every push to `main` and every PR. The suite must be green to merge.

We do not gate on coverage percentage — that's a perverse incentive (see `docs/specs/14-testing-strategy.md` "Open questions"). We gate on *behavior* coverage: every spec'd behavior has at least one test, every primitive has its declared failure modes covered.

Exemptions:
- SwiftUI views without logic (pure layout). Tested implicitly by UI smoke tests.
- Constants, design-system tokens.
- Third-party-library 1-line passthroughs.
- Exploratory prototypes (spikes) — but the moment code is meant to ship, it gets tests.

Framework: **XCTest** for both unit and UI tests. No mocking library — protocol injection + `URLProtocol` stubs are sufficient and don't add dependencies.

## Consequences

### Positive

- Refactors become safe. The FSD migration's six PRs (per [ADR 0022](./0022-feature-slice-design.md)) can land confidently because tests catch regressions.
- The primitive catalogue's contract becomes executable — each primitive's tests *are* the documentation of what it promises.
- New contributors (or future Claude Code sessions) learn the system by reading tests, not by spelunking 1000-LOC files.
- Bug regressions become impossible to ship — every reported bug ends up with a permanent test guarding against re-introduction.
- Forces better API design. Code that's easy to test is usually code with clear boundaries.

### Negative

- TDD slows the first few PRs that adopt it. Estimated 1.3–1.5× the time of "just ship it" for new features, especially while we're building out `TestSupport/` fakes.
- The discipline only works if it's actually enforced. A single skipped test for a "trivial change" sets a precedent. PR review has to catch this.
- Some Apple APIs are genuinely hard to test (the `CGEventTap`, `AVAudioEngine` taps, `AVPlayer` time observers). Tests for those tend to be integration tests with real audio, which are slow and flaky. We accept partial coverage for those areas with explicit notes in `specs/14`.
- Onboarding cost for new contributors who aren't TDD-fluent.

### Neutral / trade-offs

- "Test-driven" is a discipline, not a religion. The rule bends for spikes and prototypes; it bends for view code that's pure layout. The *spirit* is "no code ships without a test for the contract it commits to," not "every line has a test."
- XCTest is the conservative choice. Apple's new `swift-testing` framework (WWDC 2024) is more ergonomic but tooling maturity is uneven in 2026. Revisit in 2027 (per `specs/14` open questions).
- We deliberately exclude UI view code from strict TDD. Snapshot testing would help but it's deferred — the cost/benefit isn't obvious yet.

## Notes

- Phase 0 lands the *infrastructure* (CI workflow, `TestSupport/`, local Worker for integration tests) and ~30 starter tests for pure-logic types. The full discipline kicks in from Phase 1 onwards.
- `specs/14-testing-strategy.md` documents the test pyramid, directory layout, naming conventions, and quality bar in detail.
- A linter / pre-commit hook to *enforce* "every new public API gets a test" is out of scope — we trust code review.
- This ADR may be amended (not superseded) if/when we adopt `swift-testing` or property-based testing. Both are additive, not contradictory.
