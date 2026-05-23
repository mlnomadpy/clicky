# Contributing to Clicky

Welcome. This file is the short version. The deeper rules live in
[`AGENTS.md`](./AGENTS.md) — read that first, then come back here.

## Where to start

- **The roadmap**: [`docs/00-roadmap.md`](./docs/00-roadmap.md) — what's being
  built, in what order, and why. If you're picking up a task, start here.
- **The testing strategy**: [`docs/specs/14-testing-strategy.md`](./docs/specs/14-testing-strategy.md) —
  the authoritative spec for how we test. Folder layout, framework choices,
  the test pyramid, fixtures, and CI all live in that doc.
- **The architecture decisions**: [`docs/adr/`](./docs/adr/) — every
  non-obvious choice has an ADR. If you disagree with one, open an ADR
  that supersedes it rather than just changing the code.

## Running tests locally

There's a one-command runner that mirrors what CI does:

```bash
./scripts/test.sh
```

If you need the local Cloudflare Worker running too (for integration tests
that talk to `localhost:8787`), pass `--worker`:

```bash
./scripts/test.sh --worker
```

This spawns `wrangler dev` in the background on port 8787, waits for it to
come up, runs `xcodebuild test`, then tears the Worker down on exit. The
Worker needs `worker/.dev.vars` populated with API keys — see
[`worker/README.md`](./worker/README.md) and the project's CLAUDE.md /
AGENTS.md for setup.

CI runs the same flow on every push to `main` and every pull request via
[`.github/workflows/tests.yml`](./.github/workflows/tests.yml). UI tests
are gated to `release/*` branches because they're slow.

## Test-driven development policy

Per [ADR 0023](./docs/adr/0023-test-driven-development.md), all work after
Phase 0 is test-driven. New primitives, coordinators, and parsers get their
tests written *before* the implementation, with at minimum a happy path and
each declared failure mode covered. Bug fixes ship in the same commit as a
failing test that reproduces the bug. Refactors must keep the existing suite
green, and any behavior they expose without a test gets a test before the
code changes. UI views that are pure layout are exempt. We do not gate on
coverage percentage — see the "Open questions" in the testing strategy spec
for why.

## Branch and commit conventions

- Branch names: `feature/short-description` for new features, `fix/short-description`
  for bug fixes, `chore/...` and `docs/...` for the obvious cases, and
  `release/x.y.z` for release candidates (UI tests run on these).
- Commit messages use the imperative mood: "add plugin manifest validator",
  not "added" or "adds". Keep the subject under ~70 characters.
- Explain the *why* in the body when the change isn't self-evident from the
  diff. Reference the relevant spec or ADR when you can.
- Never force-push to `main`.

## Anything not covered here

It's in [`AGENTS.md`](./AGENTS.md) — code style, Swift conventions, the
"don't run `xcodebuild` locally" rule, what not to refactor, and the rest.
