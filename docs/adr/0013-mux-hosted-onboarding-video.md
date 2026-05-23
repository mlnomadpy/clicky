# ADR 0013 — Mux-hosted HLS onboarding video instead of bundling MP4

**Status**: Accepted (retroactive)
**Date**: 2026-05-22 (documented; original decision predates this)
**Deciders**: original-author
**Related**: [ADR 0001](./0001-menu-bar-only-app.md)

## Context

The onboarding flow plays a video on the cursor overlay after the user submits their email and clicks Start (see `docs/reference/02-system-design.md` § "Onboarding flow"). The video is the centrepiece of the demo — it explains what Clicky is, and at the 40-second mark Clicky takes a screenshot and points at something on the user's screen in real time.

Two options for shipping the video:

1. **Bundle an MP4 in the app.** Pros: no network dependency, plays instantly, works offline. Cons: a reasonable-quality 90-second screencast is ~50 MB. The release DMG would balloon to ~70 MB, which is heavy for a small utility — most "menu bar apps" download in under 20 MB. Also, every video edit requires a new release.
2. **Stream from a hosted source.** Pros: small binary, video can be tweaked without an app update, adaptive bitrate (HLS) plays well on slow connections. Cons: requires a network at first launch.

Mux specifically because (a) HLS adaptive bitrate is built in, no per-resolution encode required, (b) the playback URL is a single `.m3u8` that `AVPlayer` handles natively with zero added code, (c) cost at our scale is essentially free on the Mux developer plan, (d) we already require a network at first launch for the Worker calls anyway.

The onboarding flow as a whole has a network dependency only at the video stage. Email submission needs FormSpark. The "ask Claude what to point at" demo at the 40s mark needs the Worker. So adding the video to Mux didn't introduce a new offline-failure mode that didn't already exist — first-launch always needs internet.

See `CompanionManager.setupOnboardingVideo`, the hardcoded URL `https://stream.mux.com/e5jB8UuSrtFABVnTHCR7k3sIsmcUHCyhtLu1tzqLlfs.m3u8`, `OverlayWindow.swift` (`OnboardingVideoPlayerView` wrapping `AVPlayerLayer`), and `docs/reference/03-features.md` § 11.

## Decision

The onboarding video is hosted on Mux and streamed via HLS. The playback URL is a hardcoded Mux `.m3u8` in `CompanionManager.swift`. The app uses `AVPlayer` with the URL directly — no third-party SDK, just the native HLS support in `AVFoundation`.

The video is rendered inside the cursor overlay's `OverlayWindow` via `OnboardingVideoPlayerView`, an `NSViewRepresentable` wrapping `AVPlayerLayer`. A boundary time observer at 40 s triggers `performOnboardingDemoInteraction()`.

The Final Fantasy "Besaid" theme (`ff.mp3`, ~8 MB) is still bundled because it's small and starts the moment the user clicks Start — there's no time to download it. Only the video itself streams.

## Consequences

### Positive
- App DMG stays small (notarised binary is well under 20 MB).
- Video can be re-edited / re-uploaded / replaced without a new app release. The current Mux asset can be swapped for an improved cut whenever.
- Mux's HLS handles bad networks gracefully — viewers on a 3 Mbps connection get a lower bitrate variant automatically.
- `AVPlayer` HLS support is native; no SDK to integrate, no licensing.

### Negative
- **First-launch onboarding has a hard network dependency.** If the user's first launch is offline, the onboarding video doesn't play. There's no bundled fallback.
- The Mux URL is hardcoded. If the asset is deleted, every existing install with `hasCompletedOnboarding=false` plus every future "Watch Onboarding Again" replay breaks. Mux asset URLs are stable but not immutable across plan changes.
- Mux is an additional vendor dependency outside the Cloudflare Worker. One more thing to keep funded.
- The 40-second demo trigger is a `boundaryTimeObserver` — if HLS playback stalls and resumes, the observer can fire at a different wall-clock time than the user expects. In practice this hasn't been a problem.

### Neutral / trade-offs
- The video plays inside the cursor overlay (the same transparent `NSPanel` used by the blue triangle), via an `AVPlayerLayer` hosted in an `NSViewRepresentable`. The window stays non-activating and click-through; the video doesn't capture clicks.
- A "Watch Onboarding Again" footer button in `CompanionPanelView` re-runs the same sequence — the video URL doesn't change, the video just re-streams from Mux.

## Notes

If the video ever needs to work offline (e.g., a kiosk install or a privacy-mode "no network ever" use case), the right fix is to bundle a downsized fallback (~5 MB at 480p) and only attempt the Mux stream when reachable. Today this isn't worth the binary cost.
