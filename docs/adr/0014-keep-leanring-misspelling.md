# ADR 0014 — Keep the "leanring" misspelling in the project directory and scheme

**Status**: Accepted (retroactive)
**Date**: 2026-05-22 (documented; original decision predates this)
**Deciders**: original-author
**Related**: [ADR 0007](./0007-sandbox-disabled.md)

## Context

The Xcode project on disk is `leanring-buddy.xcodeproj`. The folder containing all Swift sources is `leanring-buddy/`. The scheme is `leanring-buddy`. The entitlements file is `leanring-buddy.entitlements`. The `@main` `App` is named `leanring_buddyApp` (Swift identifier — hyphen to underscore). This is a typo of "learning" — `leanring` instead of `learning`. The product name displayed to users is "Clicky", which has been correctly spelled from the start.

The misspelling exists because the original project was bootstrapped with that typo and the typo propagated everywhere Xcode generates filenames and identifiers from the scheme name. Every contributor has thought about renaming it. Every contributor has decided not to.

The reasons not to rename it:

1. **TCC permissions are keyed by bundle identifier and code-signing identity.** Renaming the scheme or bundle changes how macOS records permission grants. Users would lose every Accessibility / Screen Recording / Microphone / Screen Content grant and have to re-grant on next launch. That breaks the "ambient, just works" promise of the app.
2. **Signing identity churn.** The Developer ID certificate ties to a specific bundle identifier. A rename either requires a new identity (with its own provisioning chain) or careful renaming with Apple support.
3. **Sparkle feed continuity.** The appcast feed and EdDSA keypair (see [ADR 0012](./0012-sparkle-and-login-item.md)) are tied to the current bundle identifier. A rename means existing installs would not see new releases until they manually downloaded a one-time bridge build.
4. **Merge churn across every file path.** Every PR in flight would conflict on file paths. The release script, the entitlements, the Worker URL references, every test file path — all would need updates.
5. **Zero user-visible benefit.** Users see "Clicky" in the menu bar, "Clicky" in the DMG, "Clicky" in System Settings. The "leanring" string is invisible outside the source tree and Xcode.

The cost of the rename is real and the benefit is purely aesthetic. So the rule is hardcoded in `AGENTS.md`:

> Do not rename the project directory or scheme (the "leanring" typo is intentional/legacy)

This ADR exists so contributors who haven't read `AGENTS.md` carefully (or who think they've spotted a quick win) find a single document explaining why nobody has fixed this yet.

See `AGENTS.md` § "Do NOT", `docs/reference/06-build-and-release.md` § "Project hygiene rules", `docs/reference/04-file-reference.md` (file path list with the misspelling preserved throughout).

## Decision

The project directory (`leanring-buddy/`), the scheme name (`leanring-buddy`), the project file (`leanring-buddy.xcodeproj`), the entitlements file (`leanring-buddy.entitlements`), and the `@main` identifier (`leanring_buddyApp`) all keep the "leanring" misspelling. Nothing is renamed.

The user-facing product name remains "Clicky" everywhere it appears: app name, status item, DMG, menu bar, documentation, marketing.

## Consequences

### Positive
- Existing users keep all TCC permission grants across every release.
- Signing identity, Sparkle feed, EdDSA keypair, and bundle identifier all stay stable.
- Zero file-path churn.

### Negative
- Every new contributor notices the typo on day one and has to be told not to fix it. This ADR exists partly to short-circuit that conversation.
- A code-search for "learning" misses every file with the misspelling — including the entire Swift source tree. Searches must use "leanring" or be path-aware.
- `Bundle.main.bundleIdentifier` and the Swift `@main` symbol look unprofessional to anyone reading sources for the first time.

### Neutral / trade-offs
- The "Clicky" / "leanring-buddy" split is now baked in. If a future rename is genuinely needed (e.g., to support Mac App Store distribution), the migration would need a careful TCC-permission-preserving path — likely a one-time release that registers the new identifier and copies/transfers permissions, which is non-trivial.
- AI coding agents (Claude Code, Cursor, etc.) are instructed in `AGENTS.md` to never propose a rename. This ADR reinforces that for human reviewers.

## Notes

If a future maintainer ever needs to rename for a substantive reason — App Store submission, brand change, multi-app suite — the steps would be:

1. Coordinate a release that ships both old and new bundle identifiers (the old as a "redirect stub" that launches the new).
2. Have the stub migrate `UserDefaults` and `hasScreenContentPermission` to the new identifier on first launch.
3. Inform users that TCC permissions will need to be re-granted once (no way around this — Apple keys grants to bundle ID).
4. Update `SUFeedURL`, regenerate Sparkle keypair if desired, and migrate the appcast.

Until that day comes, the typo stays.
