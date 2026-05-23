# Designing Offline & Local-Models Support

> **Status**: design doc / RFC. Companion to `09-plugin-system-design.md` (Plugins) and `10-swoosh-mode-design.md` (Swoosh). Goal: let Clicky run cheaply or fully offline by routing each turn to local Apple frameworks and open-weight models when possible, while keeping cloud Claude available for the cases where local quality isn't enough.

## Why this exists

Three motivations, in order:

1. **Cost.** Every cloud turn is real money against the Worker. Heavy users today pay nothing because the bill goes to Farza; that doesn't scale.
2. **Privacy / offline.** Some users want voice + screen-aware AI that *never* touches a network — for sensitive work, demo environments, airplane mode.
3. **Latency floor.** Local inference on Apple Silicon has 1–3 s of cold-start latency but no round-trip; after warmup, local replies feel snappier than cloud for short utterances.

## The three modes

The user picks a mode from the panel; it's stored in `UserDefaults["aiMode"]`. The plugin generator and the Swoosh supervisor both read this setting and route primitives accordingly.

| | **Cloud** *(default, today's behavior)* | **Hybrid** | **Local** *(fully offline)* |
|---|---|---|---|
| Transcription | AssemblyAI (websocket) | Apple `SpeechAnalyzer` (macOS 26+) or `SFSpeechRecognizer` fallback | Apple `SpeechAnalyzer` / `SFSpeechRecognizer` |
| Vision LLM (normal voice turn) | Claude Sonnet 4.6 with full image | Claude with image + OCR — Claude sees both | Apple Foundation Models text + Vision OCR ("perception-first" pipeline) **or** MLX-Swift VLM if installed |
| Pointing accuracy | Claude `[POINT:x,y]` | Same (Claude still does it) | OCR-bounding-box driven (free, no pixel inference) — degrades for icon-only targets |
| TTS | ElevenLabs `eleven_flash_v2_5` | `AVSpeechSynthesizer` Neural voices | `AVSpeechSynthesizer` Neural voices |
| Plugin runtime | Plugins call cloud primitives by default | Plugin generator biases toward local primitives | Plugins must use only local primitives — cloud primitives error |
| Swoosh runtime | Available | Available | **Disabled — uses cloud Claude for planning.** Saved Swoosh-plugins still run. |
| Network required? | Yes | Yes (Claude + Apple Foundation Models is on-device so most calls don't need it, but Claude calls do) | **No** |
| Analytics (PostHog) | On | On | Off |
| Update checks (Sparkle) | On | On | Off |

The default for new installs is **Cloud** (existing behavior). The mode picker lives in the panel under a *Privacy & Cost* section.

## What lives on-device vs in the cloud

```
                     ┌────────────────── Cloud route ─────────────────┐
                     │                                                │
   user voice ───────┼──► Worker /chat ──► Claude (vision + planning) │
                     │                                                │
                     │   Worker /tts  ──► ElevenLabs                  │
                     │                                                │
                     │   Worker /transcribe-token + AssemblyAI WS     │
                     └────────────────────────────────────────────────┘

                     ┌────────────────── Local route ─────────────────┐
                     │                                                │
   user voice ───────┼──► SpeechAnalyzer / SFSpeechRecognizer         │
                     │                                                │
                     │   Vision.RecognizeTextRequest ──► OCR + boxes  │
                     │   Foundation Models (text-only, 4K ctx)        │
                     │   [optional] MLX-Swift VLM (8–30 GB downloaded)│
                     │                                                │
                     │   AVSpeechSynthesizer (Neural voices)          │
                     └────────────────────────────────────────────────┘
```

Hybrid mode runs *both* routes in parallel for some primitives — e.g., it asks Apple Foundation Models for a quick summary while still passing the same context to Claude for the planning turn. Claude becomes the source of truth, FM is the cheap pre-perception layer.

## The OCR-pointing trick (the key local-mode unlock)

Claude's pixel-coordinate prediction (the `[POINT:x,y]` tag) is excellent because Anthropic trains for Computer Use. Open-weight VLMs and Foundation Models are notably worse at pixel coordinates — they understand the screen but their *clicks* land off-target.

For local mode, we sidestep pixel prediction entirely:

1. **OCR the screen** with `Vision.RecognizeTextRequest` (free, fast, on-device since iOS 13; the modern async API in iOS 18 / macOS 15). Returns text strings with their `boundingBox` rectangles in screen-pixel coords.
2. **Ask the LLM** (Foundation Models, or any local VLM, or even Claude) to pick which OCR'd element the user is asking about — by *label*, not by coordinates. Output format: just the OCR index, e.g., `{"element_index": 7}`.
3. **Use that bounding box** as the point coordinate. We already know the pixels — the LLM never had to predict them.

```swift
// Sketch — runs inside the plugin/Swoosh primitive layer
let ocr = try await RecognizeTextRequest().run(on: screenshotCGImage)
// ocr is [(text: String, box: CGRect)]

let session = LanguageModelSession(
    systemPrompt: "Pick the index of the screen element the user is asking about."
)
struct Pick: @Generable { @Guide let index: Int }
let pick: Pick = try await session.respond(
    to: "User said: \"\(transcript)\". Elements: \(ocr.enumerated().map { "[\($0)] \($1.text)" })"
)
let pointBox = ocr[pick.index].box   // ← the answer
```

**Strengths:**

- Pointing is exact for any text element (Save button, menu items, links).
- Zero hallucinated coordinates — the boxes are real measurements.
- Free, offline, fast (~50–200 ms total).

**Weaknesses:**

- Icons without labels (gear icon, hamburger menu, app dock icons) don't OCR. Falls back to "approximate region" or asks the user to clarify.
- Custom-rendered UI (Canvas-based apps, some Electron apps) sometimes has poor OCR fidelity.

For these gaps, Local mode has a registered fallback: if OCR misses, try a local VLM (Qwen3-VL via MLX is the default — see model-management section below) for icon-region prediction, accepting the coarser accuracy. Cloud mode has no such gap because Claude does the whole thing.

## New primitives

These extend the catalogue in `09-plugin-system-design.md`. Plugins (and Swoosh agent tools) can call any of them; the generator picks based on the user's mode.

| Primitive | What it does | Where it runs | Notes |
|-----------|--------------|---------------|-------|
| `prompt_apple_local` | Text-in / text-out LLM call | Apple Foundation Models on-device | macOS 26+ only. 4K token context. Use `@Generable` for structured output. **Already in plugin spec.** |
| `prompt_local_vlm` | Image + text in, text out | MLX-Swift hosting Qwen3-VL-8B-Instruct (default) or 4B / 30B variants | Apple Silicon only. Requires 3–18 GB model download depending on size (one-time). Slow first inference (~3 s warmup), then ~1 s/turn on 8B-4bit. |
| `ocr_screen` | Screenshot → text + bounding boxes | `Vision.RecognizeTextRequest` | All macOS 14+. Cheap, fast, accurate. |
| `transcribe_local` | Audio → text | `SpeechAnalyzer` (macOS 26+) or `SFSpeechRecognizer` | Replaces AssemblyAI in Local/Hybrid modes. |
| `tts_local` | Text → spoken audio | `AVSpeechSynthesizer` with Neural voices | Replaces ElevenLabs in Local/Hybrid modes. |
| `prompt_claude` | Cloud Claude call (existing) | Worker `/chat` | Disabled in Local mode. |
| `tts_eleven` | Cloud ElevenLabs (existing) | Worker `/tts` | Disabled in Local mode. |

The mode setting becomes a parameter on the primitive registry: when a plugin declares `prompt_claude` but the user is in Local mode, the runtime either (a) substitutes `prompt_apple_local` if the plugin's `local_fallback: true` flag is set, or (b) refuses to run and tells the user "this plugin requires Cloud mode."

## Generator-prompt bias for cost

The plugin generator (the system prompt that emits manifests) is mode-aware. Its instructions vary:

| Mode | Generator's bias |
|------|------------------|
| **Cloud** | "Prefer `prompt_claude` for any task that needs reasoning beyond classification. Use `prompt_apple_local` only when the user explicitly says 'free' or 'fast'." |
| **Hybrid** | "Default to `prompt_apple_local` unless the task needs vision, ≥4K context, or sophisticated reasoning. Use `prompt_claude` for vision and complex multi-step reasoning. Always set `local_fallback: true`." |
| **Local** | "You may only emit local primitives: `prompt_apple_local`, `prompt_local_vlm`, `ocr_screen`, `transcribe_local`, `tts_local`, plus the host primitives. Emitting `prompt_claude` or `tts_eleven` is an error." |

This is how cost-shifting happens automatically: Cloud-mode users keep getting Claude-quality plugins; Hybrid-mode users get cheap plugins by default with cloud escape hatches; Local-mode users get pure-local plugins.

## Model download UX

Local mode without any models is useless. The user's first switch into Local (or installing a plugin that uses `prompt_local_vlm`) triggers a model-management sheet:

```
┌──────────── Local AI models ──────────────┐
│                                           │
│ Apple Foundation Models      ✓ installed  │
│  (text reasoning, ships with macOS 26)    │
│                                           │
│ Apple Vision OCR              ✓ installed │
│  (ships with macOS)                       │
│                                           │
│ Vision-Language Model         ◌ optional  │
│  Qwen3-VL-8B-Instruct (5.8 GB)  [ Get ]   │  ← default
│  Qwen3-VL-4B-Instruct (3.0 GB)  [ Get ]   │  ← low-memory
│  Qwen3-VL-30B-A3B (18 GB)       [ Get ]   │  ← needs 64 GB+ RAM
│                                           │
│ Recommended for your Mac:                 │
│   Qwen3-VL-8B-Instruct                    │
│ (you have 16 GB RAM, M2 Pro)              │
│                                           │
│ ───────────────────────────────────────── │
│ [ Cancel ]                  [ Install all]│
└───────────────────────────────────────────┘
```

Downloads are resumable, run in the background, and the panel shows progress. Models live in `~/Library/Application Support/Clicky/Models/`. The user can free space by deleting models from this sheet — Clicky degrades gracefully (e.g., drops back to OCR-only pointing if the VLM is removed).

### Download source

Models are pulled from **Hugging Face** with sha256 verification against a manifest shipped in the app bundle:

```json
{
  "models": [
    {
      "id": "qwen3-vl-8b-instruct-4bit",
      "url": "https://huggingface.co/mlx-community/Qwen3-VL-8B-Instruct-4bit/resolve/main/model.safetensors",
      "sha256": "abc123…",
      "size_bytes": 5800000000,
      "min_ram_gb": 16,
      "min_chip_family": "M1",
      "license": "Apache-2.0",
      "recommended_for": "default"
    },
    {
      "id": "qwen3-vl-4b-instruct-4bit",
      "url": "https://huggingface.co/mlx-community/Qwen3-VL-4B-Instruct-4bit/resolve/main/model.safetensors",
      "sha256": "abc123…",
      "size_bytes": 3000000000,
      "min_ram_gb": 8,
      "min_chip_family": "M1",
      "license": "Apache-2.0",
      "recommended_for": "low-memory"
    }
  ]
}
```

**Model selection rationale.** Qwen3-VL (October 2025) is the current SOTA open VLM for screen / UI understanding and was explicitly designed for computer-use agents — Clicky's screenshot-grounding use case. The whole Qwen3-VL family is Apache 2.0, unlike Qwen2.5-VL whose 3B and 72B variants are under the restrictive Qwen license. Always ship `-Instruct`; do *not* ship `Thinking` variants — they don't support `response_format: json_object` and break the OCR-index pick path described above. Image preprocessing must clamp `max_pixels` to ~1024×1024 before sending; Retina screenshots otherwise blow past the 16384-visual-token default and tank latency. The MLX-Swift port needs `mlx-vlm ≥ 0.3.4` to handle Qwen3-VL's processor — verify before locking the SPM revision.

Manifests are bundled, signed alongside the app binary, and updated via Sparkle releases. We do not let the model URLs be dynamically fetched at runtime — that would be a remote code execution surface in disguise.

### MLX-Swift integration

`MLX-Swift` is added as an SPM dependency. A new file `LocalVLMRuntime.swift` owns:

- Model loading (`try MLX.loadModel(at:)`)
- Inference (`session.generate(prompt:image:)`)
- Memory management (unload when idle for ≥5 min, reload on next call)
- Quantization preference (Q4 by default; Q8 for 32GB+ Macs)

See `~/.claude/skills/apple-ai-frameworks/SKILL.md` for the MLX-Swift API specifics.

## Per-turn routing logic

When the user speaks in normal voice mode (not a plugin, not a Swoosh task), the runtime decides where to send the turn:

```
on transcript_finalized(text, screenshots):
  if mode == .cloud:
    return Claude.streaming(text, screenshots)

  if mode == .hybrid:
    # Always cloud for now — local quality isn't there for general Q&A
    # Future: classify the request and route easy ones to FM
    return Claude.streaming(text, screenshots)

  if mode == .local:
    if user_question_seems_to_need_pointing(text):
      ocr = Vision.ocr(screenshots[cursorScreen])
      pick = FoundationModels.pickElement(text, ocr)
      return ResponseWith(point: ocr[pick.index].box, text: FoundationModels.respond(text, ocr_summary))
    else:
      return FoundationModels.respond(text, ocr_summary(screenshots))
```

`user_question_seems_to_need_pointing` is a small heuristic: presence of words like *where*, *click*, *show me*, *find*, *open* triggers the pointing path; everything else is a pure text response. This is a deliberately dumb classifier — it errs toward pointing, and the OCR step is cheap enough to run "just in case."

## Fallback rules

Local mode is supposed to feel like a regression-free experience as often as possible. The runtime's fallback policy:

| Failure | Behavior in Local | Behavior in Hybrid | Behavior in Cloud |
|---------|-------------------|--------------------|--------------------|
| Foundation Models unavailable (pre-macOS 26) | Bail with a *"requires macOS 26"* card | Drop the FM optimization step, do full cloud round-trip | n/a |
| VLM model not installed | Use OCR-only pointing; tell the user *"icon-pointing needs VLM, install it from settings"* if the user asked to point at an icon | Same | n/a |
| OCR finds nothing useful | Fall back to "approximate region" with a fuzzy bubble | Same | Claude handles it |
| Local model returns low confidence | Inline confirmation: *"I'm not sure — try cloud Claude?"* (one-tap upgrade) | Same | n/a |
| Network unavailable | n/a (already offline) | Auto-degrade to local for this turn; surface a banner | Bail with *"network needed for Cloud mode"* |

The *"try cloud Claude?"* one-tap upgrade is the most important UX element — Local-mode users who hit a hard case shouldn't be stuck, they should be able to opt-in cloud-fallback per-turn with one click. After the cloud call, they're back in Local mode for the next turn.

## Hardware tier matrix

What's feasible on what Mac:

| Hardware | Cloud | Hybrid | Local (OCR + FM) | Local (VLM 7B) | Local (VLM 30B+) |
|----------|-------|--------|------------------|----------------|------------------|
| Intel Mac | ✅ | ✅ if macOS 26 supports (it doesn't — Apple Silicon only for FM) | ❌ FM unavailable | ❌ MLX is Apple-Silicon-only | ❌ |
| M1 / M1 Pro / M1 Max | ✅ | ✅ | ✅ | ✅ slow (~2 s/turn) | ⚠️ very slow / OOM |
| M2 / M2 Pro / M2 Max | ✅ | ✅ | ✅ | ✅ usable (~1 s/turn) | ⚠️ slow but works on 32GB+ |
| M3 / M4 family | ✅ | ✅ | ✅ | ✅ fast | ✅ usable on 64GB+ |

The panel's mode picker reads the chip family and disables Local mode on Intel Macs with an explanation. Foundation Models requires macOS 26 *and* Apple Silicon — Hybrid mode is similarly gated unless we restrict its definition to *"prefer local where it works, else cloud."*

## Privacy guarantee semantics

For Local mode to mean what users think it means, two extra guarantees beyond just routing:

1. **Mode-locked allowlist enforcement.** The runtime maintains a list of hosts it's permitted to reach in the current mode:
   - Cloud: Worker + Apple OS update services + (during onboarding) Mux + FormSpark + PostHog.
   - Hybrid: same as Cloud, but the runtime logs and surfaces which calls were avoided.
   - Local: **only loopback** (`127.0.0.1` for Ollama if the user is using it) + Apple OS services. Every other host is blocked at the URLSession layer with a clear error.

2. **Telemetry off.** PostHog initialization is gated on `mode != .local`. Sparkle update checks gated likewise. No analytics events fire while offline.

These are belt-and-suspenders — even if a plugin or a Swoosh-compiled-plugin contains a `http_post` to some allowed domain, Local-mode users see all network calls in an audit panel. This is the "trust but verify" UX.

## Plugin compatibility

When a Local-mode user tries to install a plugin (manually or shared) that declares a `prompt_claude` step:

- If the plugin has `local_fallback: true` on every cloud primitive → it installs with a yellow badge ("falls back to local"). Each cloud call substitutes the local equivalent at runtime.
- If the plugin has cloud primitives without fallbacks → the install dialog shows them in red and warns: *"This plugin needs Cloud mode for steps X, Y. Install anyway?"* Installing leaves the plugin disabled until the user switches mode.

Plugins compiled from Swoosh runs are always emitted with `local_fallback: true` wherever the compiler can confidently substitute (the agent's perception steps almost always have local fallbacks; the *planning* steps usually don't).

## Local Swoosh: when, not if

The current limit on local Swoosh is open-weight tool-use accuracy and planning. The bottleneck is the **agent loop**, not perception (perception is great with OCR + VLM). Specifically:

- Local models are weaker at choosing the next tool from a 20-tool catalogue.
- They sometimes hallucinate tool names or skip required parameters.
- Multi-step planning over 10+ steps degrades sharply.

The Swoosh runtime is designed so this is a *one-component swap* when local tool-use catches up:

```swift
// Today
let plan = try await ClaudeAgent.nextStep(messages, tools: catalogue)

// Future
let plan = switch mode {
    case .cloud:  try await ClaudeAgent.nextStep(...)
    case .hybrid: try await ClaudeAgent.nextStep(...)   // still cloud for now
    case .local:  try await LocalAgent.nextStep(...)    // when ready
}
```

When does "when ready" arrive? Realistic milestones:

- **2026**: Local Swoosh limited to ≤5-step tasks. Cloud-only for anything serious.
- **2027**: Local 30B+ models match Claude-3-Opus on tool-use. Local Swoosh becomes viable for most everyday tasks.
- **2028+**: Local matches Sonnet 4-class on planning. Cloud Swoosh becomes the premium tier, not the default.

Until then, Local-mode users get value from Swoosh via the compile-on-save bridge: someone (or Farza, shipping curated bundles) authors useful Swoosh tasks in Cloud mode and shares them as plugins. Local users install those plugins and run them at zero ongoing cost.

## Cost projection example

For a hypothetical heavy user — 50 voice turns/day, mixed pointing and Q&A — at today's prices (Sonnet 4.6 ~$3 / $15 per M tokens, average turn ~3K image + 200 in + 250 out):

| Mode | $/day | $/month |
|------|-------|---------|
| Cloud | ~$1.20 | ~$36 |
| Hybrid (Claude planner, FM summaries, local TTS) | ~$0.85 | ~$25 |
| Hybrid w/ OCR routing optimization | ~$0.50 | ~$15 |
| Local (no Claude at all) | $0 | $0 |
| Local w/ occasional cloud-fallback (5%) | ~$0.06 | ~$1.80 |

These are rough; exact numbers depend on turn complexity and image dimensions. The point: Hybrid cuts cost roughly in half by default, and Local-with-fallback is functionally free.

## Phased rollout

**Phase L0 — Drop-in local TTS.** Add `tts_local` primitive (`AVSpeechSynthesizer` Neural voices). Add a toggle "use local TTS" to the panel. Zero impact on quality of Claude responses; this is just substituting the voice. Lowest-risk first ship.

**Phase L1 — Local transcription.** Wire `SpeechAnalyzer` (macOS 26+) as a transcription provider option in `BuddyTranscriptionProviderFactory`. AssemblyAI already has a graceful fallback (`AppleSpeechTranscriptionProvider`) so the plumbing is mostly there.

**Phase L2 — OCR-pointing trick.** Add `ocr_screen` + the OCR-bounding-box pointing path. Use it in Hybrid mode as an *optimization* — Claude still runs but the OCR runs in parallel and Claude is given the OCR text alongside the image. Measure whether Claude's pointing improves when given OCR ground truth.

**Phase L3 — Foundation Models integration.** Wire `prompt_apple_local`. Used first for non-vision sub-tasks (summarizing tool results, classifying intent). Becomes the default LLM in Local mode for text-only turns.

**Phase L4 — Mode picker UI.** Add the Cloud / Hybrid / Local switch to the panel. Each plugin install screen shows its mode compatibility. The privacy/cost copy is honest about trade-offs.

**Phase L5 — MLX-Swift VLM.** Ship the model-management sheet. Bundle the manifest of supported VLMs. First-class support for Qwen3-VL-8B-Instruct-4bit as the recommended default (Qwen3-VL-4B-Instruct-4bit on lower-memory Macs). This is the heaviest engineering lift in the offline path.

**Phase L6 — Audit panel & network lockdown.** Implement the network allowlist enforcement at the URLSession layer. Surface an audit log showing every outbound request in the last 7 days. Required for Local mode to *mean* something to privacy-focused users.

Phase L0–L3 can land independently and incrementally improve Cloud and Hybrid mode without committing to Local mode. Phases L4–L6 are the "ship Local mode" bundle.

## Open questions

1. **Foundation Models structured output reliability.** `@Generable` with `@Guide` works well for short structured outputs (the OCR-index pick case is tiny). For the more complex case — a 50-line plugin manifest with nested types — early experimentation will tell us whether FM can replace Claude as the *plugin generator*. Recommendation: stay on Claude for the generator until evidence shows otherwise.
2. **Hybrid mode default behavior.** "Always cloud" or "cloud with FM pre-perception"? Recommendation: ship Phase L2 first and let the data answer this.
3. **MLX vs Ollama** for the VLM runtime. MLX integrates natively but requires building model-loading UX ourselves; Ollama is a separate install with a localhost HTTP API. Recommendation: MLX, because shipping an Ollama install dependency is a non-starter for non-technical users.
4. **Per-plugin override.** Should a Local-mode user be able to flip *one specific plugin* to Cloud mode permanently (not just per-turn)? Recommendation: yes — a per-plugin toggle in the Plugins list, off by default.
5. **Voice clone (Apple Personal Voice)** as an opt-in to make local TTS feel premium. Apple supports it on macOS 14+; setup requires the user's voice training session. Worth surfacing in the panel as an upsell for Local-mode users who don't want the canned Neural voices.

## What this design intentionally does *not* do

- **Doesn't ship multiple cloud providers.** We're not adding OpenAI or Gemini routing. The existing `OpenAIAPI.swift` and `OpenAIAudioTranscriptionProvider.swift` stay as fallbacks for transcription only. Anything new is Claude or local.
- **Doesn't try to make Local mode quality-equivalent to Cloud.** It's positioned in the UI as a *trade-off* the user opts into. No "Local mode but it's secretly cloud sometimes" — every fallback is visible.
- **Doesn't pretend to support Intel Macs in Local mode.** Apple Silicon-only. The mode picker disables Local mode and explains why.
- **Doesn't enable Local Swoosh in v1.** Cloud Swoosh exists; Local Swoosh is a future phase that depends on open-weight model quality (see "Local Swoosh: when, not if").

## TL;DR

Mode is a switch, not a fork. Cloud is today's behavior. Hybrid is "Claude for the hard parts, local for everything else" — cuts cost in half by default. Local is "no network, ever" — pointing accuracy degrades on icons, Swoosh is unavailable, but everything else works. The OCR + Foundation Models combo makes pointing-at-text effectively free and accurate without any pixel inference. MLX-Swift hosts open-weight VLMs for the icon-pointing gap. Per-turn cloud-fallback gives Local users an escape hatch one tap away. Swoosh compile-on-save closes the loop: a Cloud user authors expensive automations, a Local user runs them for free forever.
