# ADR 0020 — MLX-Swift hosts local vision-language models (not Ollama)

**Status**: Proposed
**Date**: 2026-05-22
**Deciders**: Farza, Claude Code session
**Related**: [ADR 0018](./0018-cloud-hybrid-local-mode-picker.md), [ADR 0019](./0019-ocr-and-foundation-models-pointing.md)
**Source spec**: `docs/specs/11-offline-and-local-models.md`

## Context

Local mode needs a vision-language model for the icon-pointing fallback case (when OCR can't see the target — see [ADR 0019](./0019-ocr-and-foundation-models-pointing.md)). Apple Foundation Models is text-only at launch — we need a separate VLM runtime.

The realistic options for running open-weight VLMs on Apple Silicon:

1. **Ollama** — separate macOS app + HTTP server. Familiar to many developers. Easy to install models via `ollama pull`.
2. **MLX-Swift** — Apple's open-source array framework. SPM dependency. Models loaded directly via Swift API.
3. **llama.cpp / mlc-llm** — C++ binaries embedded. Lower-level, more work to wire.
4. **Bundle a Core ML model** — Apple's native ML runtime. Limited VLM availability; conversion pipeline is its own project.

## Decision

Use **MLX-Swift** as the local VLM runtime. Bundle a small VLM (initial recommendation: **Qwen3-VL-8B-Instruct quantized to 4-bit**, from `mlx-community/Qwen3-VL-8B-Instruct-4bit`) and let advanced users opt into larger or smaller variants via a model-management sheet. A 4B variant (`mlx-community/Qwen3-VL-4B-Instruct-4bit`, ~3 GB) is offered as the fallback for 8 GB-RAM Macs.

Model files are downloaded from Hugging Face on first use, verified against a SHA-256 manifest shipped with the app. Files live in `~/Library/Application Support/Clicky/Models/`.

We do not require Ollama. If a user already has Ollama installed and would prefer to use it, a future ADR may add an Ollama-backed primitive — but that's a power-user escape hatch, not the default.

## Consequences

### Positive

- Zero external dependencies. The user doesn't have to install Ollama or any other runtime — they just download models inside Clicky.
- MLX-Swift integrates natively. Swift APIs, async/await, no IPC overhead between processes.
- We control the model lifecycle (load, unload after idle, swap quantizations) without coordinating with a separate process.
- Quality is competitive with Ollama-hosted equivalents — both run on the same Apple Silicon ANE/GPU/Neural Engine paths.
- Apple invests in MLX. Future versions will likely add features (faster quantization, KV cache improvements) we benefit from without changing our integration.

### Negative

- Building the model-download UX is real work. Progress bars, sha256 verification, resumability, "free up disk space" prompts — all on us.
- A bundled VLM is 2–5 GB on disk. App download size doesn't grow (downloads are post-install), but storage usage does.
- MLX-Swift is younger than llama.cpp / Ollama. API churn is a real risk for the next year or two — we may need to update the integration when MLX changes.
- We're responsible for picking which models to ship. Future-you may be embarrassed by Qwen2.5-VL when better options arrive.
- No GUI for users to browse models like Ollama's `ollama list` — they pick from the curated set in our sheet.

### Neutral / trade-offs

- Apple Silicon-only. Intel Macs see Local mode disabled in the mode picker — already a constraint from Foundation Models.
- Model storage is per-user, not per-app — but since only Clicky uses these specific quantized variants, there's no community-wide caching benefit. Acceptable.
- The "no third-party install required" property is a real selling point for less-technical users. Most macOS users will not install Ollama.

## Notes

- The initial recommended model (**Qwen3-VL-8B-Instruct 4-bit**, ~5–6 GB on disk, ~7–8 GB resident) was chosen for: Apache-2.0 license across the whole family (Qwen2.5-VL's 3B / 72B variants are under the restrictive Qwen license — avoid those), SOTA open VLM for screen / UI-grounding tasks as of October 2025, explicitly designed for computer-use agents, supports `response_format: json_object` for structured output.
- The 4B variant (`mlx-community/Qwen3-VL-4B-Instruct-4bit`, ~3 GB on disk) is the fallback for 8 GB RAM Macs (M1 / M2 base). Same architecture and tokenizer as the 8B so prompts and parsing code are identical.
- Larger models (Qwen3-VL-30B-A3B, Qwen3-VL-72B) are listed as opt-in in the management sheet for users with 64 GB+ RAM.
- **Do not** ship `Thinking` variants — they don't support `json_object` response format (per QwenLM/Qwen3-VL issue #1652). Stick to `-Instruct`.
- **MLX-VLM version floor**: Qwen3-VL needs `mlx-vlm ≥ 0.3.4`. Verify the Swift port has the Qwen3-VL processor before locking the SPM revision.
- **Image preprocessing gotcha**: clamp `max_pixels` to roughly 1024×1024 before sending. Retina screenshots otherwise blow past the 16384-visual-token default and tank latency.
- MoonDream2 was considered as a smaller alternative but rejected — strong ScreenSpot benchmark but weaker instruction-following.
- A future ADR may revisit if MLX-Swift becomes unmaintained or if Apple ships a competing on-device VLM in Foundation Models. The architectural inversion would be a backend swap behind the `LocalVLMRuntime` protocol — same pattern as `SwooshHost` (see [ADR 0016](./0016-swoosh-illusion-then-virtualization.md)).
- The Hugging Face download is the *only* network call Local mode makes during normal operation, and it happens on first use only. This is documented in the user-visible Local-mode copy.
