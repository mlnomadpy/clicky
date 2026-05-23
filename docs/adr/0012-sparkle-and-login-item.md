# ADR 0012 — Sparkle auto-update (EdDSA-signed feed) and `SMAppService` login item

**Status**: Accepted (retroactive)
**Date**: 2026-05-22 (documented; original decision predates this)
**Deciders**: original-author
**Related**: [ADR 0007](./0007-sandbox-disabled.md), [ADR 0001](./0001-menu-bar-only-app.md)

## Context

Clicky ships outside the Mac App Store (see [ADR 0007](./0007-sandbox-disabled.md)). That means two normally-Apple-handled concerns become the app's problem:

1. **Update delivery.** An App Store app gets free in-place updates. A DMG distributed via GitHub Releases has none — without an updater, users would have to re-download and re-install every release.
2. **Launch at login.** App Store apps opt in via Info.plist or the Service Management framework. A DMG app has to register itself.

### Updater: Sparkle

Sparkle is the de facto standard auto-update framework for non–App Store macOS apps. It checks a static `appcast.xml` feed for newer versions, downloads the DMG, verifies a signature, and prompts the user to install. EdDSA-signed feeds were added in Sparkle 2.x and are now the recommended signing mode — feeds are public XML, so signing prevents an attacker who controls the feed host from pushing a malicious build.

The wiring is straightforward:

- `SUFeedURL` in `Info.plist` points at the hosted `appcast.xml` (currently `https://raw.githubusercontent.com/julianjear/makesomething-mac-app/main/appcast.xml` — a separate repo).
- `SUPublicEDKey` in `Info.plist` is the matching EdDSA public key (`/l3d2rw5ZZFRU3AadP/w2Zf8FHfhA6bKv16BQOV5OSk=`).
- `scripts/release.sh` runs `sign_update` against the EdDSA private key (stored in the maintainer's Keychain) and writes the signature into the regenerated `appcast.xml`.
- `CompanionAppDelegate.startSparkleUpdater()` creates an `SPUStandardUpdaterController` with auto-check enabled.

**Current status**: the call to `startSparkleUpdater()` is commented out at `leanring_buddyApp.swift:53`. The infrastructure is fully wired (feed URL, key, release script, signed feed) — re-enabling it is a one-line uncomment. The comment-out is a deliberate pause from a release where the updater was misbehaving; the plan is to flip it back on as part of Phase 0 stabilisation (see `docs/00-roadmap.md`).

### Login item: `SMAppService`

The modern API for "launch this app at login" is `SMAppService.mainApp.register()`, available macOS 13+. It registers a user-visible entry in System Settings → Login Items that the user can disable. We call it once on first launch (`CompanionAppDelegate.registerAsLoginItemIfNeeded`) and never again — once it's registered, the OS owns the state.

The older `LaunchServices`/`SMLoginItemSetEnabled` APIs are deprecated and don't surface in Login Items the way the modern API does.

See `leanring_buddyApp.swift:53` (Sparkle call site), `CompanionAppDelegate.registerAsLoginItemIfNeeded`, `Info.plist` (`SUFeedURL`, `SUPublicEDKey`), `scripts/release.sh` (appcast generation + signing), and `docs/reference/06-build-and-release.md`.

## Decision

**Updates** ship via Sparkle 2.x with an EdDSA-signed appcast feed. The feed is hosted at the `SUFeedURL` defined in `Info.plist`; the public key is in `SUPublicEDKey`. `scripts/release.sh` generates and signs `appcast.xml` on every release.

**Launch at login** is handled by `SMAppService.mainApp.register()`, called once during first launch.

The Sparkle updater controller is *wired* but currently disabled (the call to `startSparkleUpdater()` is commented out at `leanring_buddyApp.swift:53`). Re-enabling it is on the Phase 0 roadmap.

## Consequences

### Positive
- Users can ship Clicky updates without re-installing — one-click in-app update once Sparkle is enabled.
- EdDSA signatures mean a compromised feed host cannot push an arbitrary build to users.
- `SMAppService` is the modern, user-visible login-item API — users can disable autostart from a familiar place in System Settings.
- Release pipeline is one script (`scripts/release.sh`): archive → sign → DMG → notarize → staple → Sparkle-sign → appcast → GitHub Release → push appcast.

### Negative
- Sparkle is currently disabled — until it's re-enabled, every release requires users to re-download manually. This is a known gap and Phase 0 work.
- The private EdDSA key lives in the maintainer's Keychain. If it's lost, the chain has to be rotated and every previously-shipped binary loses its ability to verify future updates (users would have to manually re-install once with a new key).
- The hosted appcast lives in a separate GitHub repo (`julianjear/makesomething-mac-app`). Forkers must replace `SUFeedURL`, the EdDSA keypair, and the hosting repo before shipping their own builds.
- `SMAppService.mainApp.register()` is silent on success — there's no UI prompt the first time. Users discover the autostart entry in System Settings without explicit consent at registration time.

### Neutral / trade-offs
- The Sparkle SPM dependency adds a non-trivial binary footprint and pulls in some legacy ObjC code. Acceptable cost for the update functionality.
- We register the login item every first launch and let `SMAppService` no-op if it's already registered — there's no logic to detect "user disabled it intentionally" and re-prompt.

## Notes

Re-enabling Sparkle is a one-line change at `leanring_buddyApp.swift:53` — uncomment the call to `appDelegate.startSparkleUpdater()`. Before flipping it on, sanity-check: (a) the appcast at `SUFeedURL` is reachable, (b) the EdDSA signature in the latest entry matches the bundled `SUPublicEDKey`, (c) the DMG attached to the latest GitHub release is the same one referenced in the appcast. A failure in any of these will manifest as Sparkle silently refusing to update.
