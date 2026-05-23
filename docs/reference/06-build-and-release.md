# Build & Release

## Local dev build

1. `open leanring-buddy.xcodeproj` (yes, the typo stays).
2. Select the **leanring-buddy** scheme.
3. Set your Team under *Signing & Capabilities*.
4. `Cmd+R`.

**Do NOT use `xcodebuild` from the terminal.** It invalidates TCC permissions, which means the next launch re-prompts for Screen Recording / Accessibility / Microphone. Always build in the Xcode UI for day-to-day development.

### Required dependencies

The project uses Swift Package Manager (SPM) for:

- **Sparkle** — auto-update framework. Imported in `leanring_buddyApp.swift`.
- **PostHog** — analytics. Imported in `ClickyAnalytics.swift` and `CompanionManager.swift`.

Both resolve on first build via the bundled `xcshareddata` in `leanring-buddy.xcodeproj/`.

### Known non-blocking warnings

- Swift 6 concurrency warnings throughout (the codebase predates strict-concurrency mode).
- A deprecated `onChange` API in `OverlayWindow.swift`.

Both are intentional. `AGENTS.md` explicitly says **do not fix them.**

## Release pipeline

The single command:

```bash
./scripts/release.sh                 # auto-bump from latest GH release
./scripts/release.sh 2.0             # set marketing version, auto-bump build
./scripts/release.sh 2.0 10          # set both
```

What it does, in order:

1. Reads the latest release from GitHub via `gh` to determine version + build.
2. Confirmation prompt (Y/N).
3. `xcodebuild archive` into a temporary archive.
4. Exports a signed `.app` with the configured Developer ID.
5. `create-dmg` builds a DMG with `dmg-background.png` as the drag-to-Applications background.
6. `xcrun notarytool submit ... --wait` notarizes the DMG (waits for Apple).
7. `xcrun stapler staple` staples the notarization ticket to the DMG.
8. Sparkle's `sign_update` signs the DMG with the EdDSA key.
9. Generates/updates `appcast.xml`.
10. `gh release create` creates a GitHub Release with the DMG attached.
11. Pushes the updated `appcast.xml` to the appcast-hosting repo.

### One-time setup

```bash
brew install create-dmg gh

gh auth login

xcrun notarytool store-credentials "AC_PASSWORD" \
    --apple-id YOUR_APPLE_ID \
    --team-id YOUR_TEAM_ID
# Use an app-specific password from appleid.apple.com.

# Sparkle EdDSA key — already in Keychain from initial Sparkle setup.
```

### Sparkle auto-update wiring

| Piece | Where |
|-------|-------|
| Feed URL | `Info.plist` → `SUFeedURL` (currently `https://raw.githubusercontent.com/julianjear/makesomething-mac-app/main/appcast.xml`) |
| Public EdDSA key | `Info.plist` → `SUPublicEDKey` |
| Updater controller | `CompanionAppDelegate.startSparkleUpdater()` (currently commented out at the call site — uncomment line 53 of `leanring_buddyApp.swift` to re-enable in-app update checks) |
| Appcast generation | `scripts/release.sh` (regenerates and pushes `appcast.xml`) |

If you fork Clicky, swap `SUFeedURL` and the EdDSA keypair before shipping.

## Entitlements and code signing

`leanring-buddy.entitlements`:

| Key | Value | Why |
|-----|-------|-----|
| `com.apple.security.app-sandbox` | `false` | App needs system-wide CGEvent tap + Accessibility API access; not compatible with the sandbox. |
| `com.apple.security.network.client` | `true` | Worker, Anthropic, ElevenLabs, AssemblyAI, FormSpark, PostHog, Mux HLS. |
| `com.apple.security.device.camera` | `true` | Camera entitlement is requested but not used; `AVCaptureDevice.authorizationStatus(.audio)` is the actual mic check. Camera is here for future use. |
| `com.apple.security.device.audio-input` | `true` | Microphone. |
| `com.apple.security.temporary-exception.mach-lookup.global-name` → `com.apple.screencapturekit.picker` | array | Required to use the ScreenCaptureKit picker dialog. |

The app is not sandboxed. This is required for the global `CGEventTap` and the Accessibility API.

## Worker deploy

See [`05-cloudflare-worker.md`](./05-cloudflare-worker.md). Summary:

```bash
cd worker
npm install
npx wrangler secret put ANTHROPIC_API_KEY
npx wrangler secret put ASSEMBLYAI_API_KEY
npx wrangler secret put ELEVENLABS_API_KEY
# edit wrangler.toml: ELEVENLABS_VOICE_ID
npx wrangler deploy
```

## Versioning

- `CFBundleShortVersionString` and `CFBundleVersion` are bumped by `scripts/release.sh`.
- The README's "Update: April 27, 2026" line is hand-maintained.
- `appcast.xml` is regenerated each release.

## Project hygiene rules (from `AGENTS.md`)

These are non-negotiable when working on the codebase:

- **Do not rename** the project directory or scheme. The "leanring" misspelling is intentional/legacy.
- **Do not run `xcodebuild`** for daily dev — it invalidates TCC.
- **Do not fix** Swift 6 concurrency warnings or the deprecated `onChange` warning.
- **Do not add docstrings / comments / type annotations** to code you didn't change.
- **Do not force-push to `main`.**
