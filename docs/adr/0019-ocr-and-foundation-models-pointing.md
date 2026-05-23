# ADR 0019 — Local pointing uses Vision OCR + Foundation Models, not pixel-coordinate prediction

**Status**: Proposed
**Date**: 2026-05-22
**Deciders**: Farza, Claude Code session
**Related**: [ADR 0010](./0010-text-based-point-protocol.md), [ADR 0018](./0018-cloud-hybrid-local-mode-picker.md), [ADR 0020](./0020-mlx-swift-for-vlms.md)
**Source spec**: `docs/specs/11-offline-and-local-models.md`

## Context

In Cloud mode, Claude predicts the pixel coordinate of a target element directly via the `[POINT:x,y]` tag (see [ADR 0010](./0010-text-based-point-protocol.md)). This works because Anthropic specifically trains Claude for Computer Use — pixel accuracy is genuinely good.

For Local mode (no network), we need a pointing mechanism that doesn't require Claude. The obvious candidates are open-weight vision-language models (Qwen2.5-VL, Phi-3.5-vision, Llava). All three understand the screen content reasonably well, but their **pixel-coordinate output** is meaningfully worse than Claude's — they point at the right region but often not the right button. Asking a 7B local VLM to nail an exact pixel for a small UI element is asking too much of the architecture.

We considered:

1. **Use a local VLM for pixel coordinates** and accept the accuracy hit. Honest but disappointing UX.
2. **Skip pointing entirely in Local mode.** Reduces the product significantly.
3. **Use a *different* pipeline for local pointing** — one that doesn't require pixel coordinate prediction at all.

## Decision

In Local mode, pointing uses a three-stage pipeline that sidesteps pixel inference entirely:

1. **OCR the screen** with `Vision.RecognizeTextRequest` (`VNRecognizeTextRequest` or the modern iOS 18 async equivalent). Returns text strings with their pixel-precise `boundingBox` rectangles. Free, fast (~50 ms), on-device since macOS 13.
2. **Ask Apple Foundation Models** (or a local VLM if installed) to pick which OCR'd element matches the user's request — by *label*, not by coordinates. Output is a single integer index into the OCR results array.
3. **Use that bounding box as the point coordinate.** The pixels are real measurements from the OCR step; the LLM was never asked to predict them.

For elements that don't OCR — icons, image regions, custom-rendered UI — Local mode falls back to:

- Asking the local VLM (if installed) for an approximate region.
- Or refusing to point and telling the user *"I can see this is on the screen but I can't precisely point at it without text labels."*

## Consequences

### Positive

- Pointing accuracy in Local mode is exact for any text element. Save buttons, menu items, links, form labels — all work as well as Cloud mode.
- Zero hallucinated coordinates. The boxes come from OCR ground truth, not a generative model's guess.
- The whole pipeline is free, offline, and ~150 ms total. Comparable to Cloud-mode latency after warmup.
- Works on any Mac that runs macOS 14+. No GPU required for the OCR; Foundation Models needs macOS 26 + Apple Silicon but is also Apple-bundled and free.
- The structured-output guarantee of Foundation Models (`@Generable` with `@Guide`) makes the "pick an OCR index" step reliable. We're asking the LLM to do classification, not generation.

### Negative

- Icon-only targets (gear icon, hamburger menu, app dock icons) don't OCR. Without a VLM installed, Local mode can't point at them precisely.
- Custom-rendered UI (Canvas-based apps, some Electron apps) often has poor OCR fidelity — text exists but isn't recognized.
- The pipeline is two LLM calls (or one OCR + one LLM call) instead of one. Latency floor is slightly higher than a single VLM call.
- Adding an MLX-Swift VLM is a separate dependency stack ([ADR 0020](./0020-mlx-swift-for-vlms.md)) and only valuable for the OCR-fallback case.

### Neutral / trade-offs

- We're making Local mode product-feasible by changing the *task* the LLM does — from "predict pixels" (hard for small local models) to "classify among labeled options" (easy for any LLM). This is a recurring pattern worth remembering.
- The fallback hierarchy (OCR → VLM if installed → refuse) gives the user a clear mental model: "Local mode is great at text targets, OK at icons if I install the VLM, honest when it can't."

## Notes

- This decision *only* applies to Local mode. Cloud and Hybrid still use Claude's `[POINT:x,y]` directly (see [ADR 0010](./0010-text-based-point-protocol.md)).
- The OCR pipeline can also help Cloud mode as an *optimization* — Phase L2 in `specs/11` proposes sending OCR text alongside the screenshot to Claude, which may improve pointing on small targets even with cloud Claude. Worth measuring.
- The `@Generable` reliability claim depends on Apple Foundation Models behaving correctly with strict structured output for short integer responses. If it doesn't, the fallback is a free-form parse with retry. Validate in Phase L3.
