# Designing a Self-Creating Plugin System for Clicky

> **Status**: design doc / RFC. Nothing in this document is built. The goal is to agree on a shape before writing Swift.

## The pitch in one paragraph

Today Clicky has exactly one behavior: hold `ctrl+option`, ask a question, get a screen-aware spoken answer with optional pointing. Everything is hardcoded — the system prompt, the screenshot pipeline, the post-response actions, the hotkeys. A **plugin** in this design is a small, declarative bundle that adds a new trigger → action chain on top of the existing pipeline. Users describe what they want in natural language; Clicky asks Claude to generate the plugin manifest; the user approves it; it goes live. No new app build, no Swift code from us.

Concretely, a user could say *"whenever I'm in Figma and I say 'export this', take a screenshot of the selected layer area, run it through this prompt I'll give you, and save the result to my downloads folder"* — and Clicky would compile that into a runnable plugin.

## Design principles

1. **Declarative, not executable.** Plugins must not be arbitrary code. They are JSON manifests of triggers, actions, and prompt templates. The Swift runtime interprets them. This keeps the security surface bounded.
2. **Every capability is a builtin.** Plugins compose a fixed set of host-provided primitives (capture screen, call Claude, write file, run AppleScript, etc.). We add primitives over time; plugins never extend the primitive set themselves.
3. **Sandbox by default, opt-in for power.** A plugin that needs to write outside `~/Library/Application Support/Clicky/Plugins/<id>/data/` requires explicit user approval at install time, with the specific path listed.
4. **One generator, many runners.** Plugin authoring uses Claude (via the existing `/chat` route, with a special system prompt). Plugin execution is pure local — no LLM call required unless the plugin's own actions include one.
5. **Reversible.** Every plugin can be disabled, exported, edited, or deleted from the panel. State is isolated per-plugin.
6. **Trust gradients.** First-party plugins (shipped by us) > user-authored local plugins > plugins shared/imported from links. Each tier has progressively stricter prompts at install time.

## What a plugin can do (the primitive set)

This is the contract. Plugins compose these and nothing else. Every primitive is implemented in Swift; the manifest only references them by name and parameters.

### Triggers (one of)

| Trigger | Parameters | What fires it |
|---------|------------|---------------|
| `voice_phrase` | `pattern: String`, `match: literal\|fuzzy\|regex` | After push-to-talk transcript matches. |
| `voice_intent` | `description: String` | After push-to-talk transcript matches a NL intent classified by Claude or by Apple's NL framework (post-MVP). |
| `hotkey` | `keys: ["ctrl","option","f"]` | Distinct from the push-to-talk hotkey. Allocated from a reserved range. |
| `menu_item` | `label: String`, `icon?: String` | Appears in a new "Plugins" submenu inside the panel. |
| `app_focus` | `bundle_id: String` | Fires when the user switches to / away from an app (combined with another trigger as a *condition*, never on its own — see below). |
| `schedule` | `cron: String` | Background firing (cron-style). Off by default; needs explicit per-plugin opt-in. |

### Conditions (gates that AND with the trigger)

| Condition | Parameters |
|-----------|------------|
| `frontmost_app` | `bundle_id: String` |
| `screen_count` | `min: Int` |
| `time_of_day` | `between: ["09:00","17:00"]` |
| `accessibility_text_present` | `query: String` — uses AX API on the focused window, if Accessibility is granted |

### Actions (one or more, run in order)

| Action | Parameters | Notes |
|--------|------------|-------|
| `capture_screen` | `which: cursor\|all\|named:N`, `bind_to: "shot"` | Same code path as the existing `CompanionScreenCaptureUtility`. |
| `capture_region` | `via_user_selection: true \| rect: CGRect`, `bind_to: "shot"` | Drag-to-select UI on top of overlay. |
| `transcript` | `bind_to: "what_user_said"` | The push-to-talk transcript (only valid when trigger is voice-based). |
| `prompt_claude` | `system: String`, `user_template: String`, `images?: [binding]`, `model?: String`, `bind_to: "reply"` | Goes through the existing Worker `/chat`. Template uses `{{binding}}` substitution. |
| `prompt_apple_local` | `system: String`, `user_template: String`, `bind_to: "reply"` | Uses Apple's Foundation Models on-device LLM (macOS 26+). Free, offline. |
| `speak` | `text: String\|binding`, `voice?: String` | ElevenLabs TTS (existing `/tts`) or Apple's TTS as a free path. |
| `point_at` | `coordinate: binding\|literal`, `label?: String` | Reuses the existing `[POINT:...]` flight animation. |
| `clipboard_write` | `text: binding\|literal` | `NSPasteboard`. |
| `clipboard_read` | `bind_to: "clip"` | `NSPasteboard`. |
| `file_write` | `path: String`, `body: binding`, `mime?: String` | Path must satisfy the plugin's declared scopes (see below). |
| `file_read` | `path: String`, `bind_to: "content"` | Same scope rules. |
| `notify` | `title: String`, `body: String\|binding` | `UNUserNotificationCenter`. |
| `applescript` | `script: String` | Only if user granted "AppleScript" scope at install. |
| `shell` | `argv: [String]` | Strongly discouraged. Disabled by default; never offered by the generator. Requires manual edit + a second confirmation. |
| `cursor_overlay_text` | `text: binding\|literal`, `duration_ms: Int` | Show text near the cursor (reuses the onboarding-prompt stream code path). |
| `http_get` / `http_post` | `url: String`, `headers?: {}`, `body?: binding` | Only domains in the plugin's `allowed_domains` allowlist. |

Notably absent: dynamic code, plugin-to-plugin calls (post-MVP), background daemons, kernel extensions.

### Bindings

A plugin run has a small key-value bag (`context`). Each action that produces output declares `bind_to` and writes there. Subsequent actions reference bindings via `{{name}}` in string fields. Bindings are typed and the runtime rejects illegal substitutions (e.g., binding an image into a `String` parameter).

## Manifest shape

```jsonc
{
  "id": "screenshot-to-markdown-notes",
  "name": "Screenshot → Markdown notes",
  "description": "When I say 'note this', captures the screen, asks Claude to summarize it as markdown bullets, and appends it to ~/notes.md.",
  "version": "1",
  "author": "user:tahabhs14@gmail.com",
  "generated_by": "clicky-plugin-generator-v1",
  "generated_at": "2026-05-22T16:55:00Z",
  "scopes": {
    "file_write_paths": ["~/notes.md"],
    "allowed_domains": [],
    "applescript": false,
    "shell": false
  },
  "trigger": {
    "type": "voice_phrase",
    "pattern": "note this",
    "match": "fuzzy"
  },
  "conditions": [],
  "actions": [
    { "op": "capture_screen", "which": "cursor", "bind_to": "shot" },
    { "op": "prompt_claude",
      "system": "You turn screenshots into 3-5 concise markdown bullet notes. No preamble.",
      "user_template": "Summarize what's on this screen as bullets.",
      "images": ["shot"],
      "bind_to": "summary" },
    { "op": "file_write",
      "path": "~/notes.md",
      "body": "\n\n## {{timestamp:iso}}\n{{summary}}\n",
      "append": true },
    { "op": "speak", "text": "noted." }
  ]
}
```

Manifests are validated by a JSON schema (`Plugin.schema.json`) bundled with the app. Unknown ops or extra top-level fields are rejected — that's how we keep the schema honest.

## Where plugins live on disk

```
~/Library/Application Support/Clicky/
  Plugins/
    screenshot-to-markdown-notes/
      manifest.json
      icon.png            (optional, generated by Claude on install)
      data/               (the plugin's per-instance scratch area)
      log.jsonl           (every run, for debugging)
    ...
```

Manifests are flat JSON files, version-controllable, shareable (`shareable-url=clicky://install?manifest=...`).

## The author flow — how the user "codes" a plugin

This is the part the user actually sees.

1. **Enter authoring mode.** From the panel: *"+ New plugin"*. Or by saying *"clicky, let's make a plugin that…"* and Clicky detecting the meta-intent.
2. **Conversation, not form.** A second-tier overlay appears with a chat-style transcript. The user describes what they want. Clicky (running a different system prompt — the *plugin generator* prompt) asks clarifying questions: *"What should I do when this fires?"*, *"Should this also save to a file?"*, *"Are you OK with me writing to ~/notes.md?"*.
3. **Generate the manifest.** Claude returns a manifest in fenced JSON. The host validates it against the schema. If invalid, the host pushes the validation error back into the chat: *"the manifest you returned has `op: 'send_email'` which isn't a real primitive. Use one of [...]. Try again."* This is the loop that prevents hallucinated capabilities.
4. **Preview.** The host renders the manifest in plain English: *"This plugin will: listen for the phrase 'note this' → take a screenshot → ask Claude to summarize → append to ~/notes.md → say 'noted'."* The user sees every primitive and every scope.
5. **Approve scopes.** If `scopes.file_write_paths` is non-empty, the panel shows each path with a checkbox. Same for `allowed_domains`, AppleScript, etc. The user must tick each box before *Install* enables.
6. **Test run.** A *"Try it"* button runs the plugin once with fake or live input. Output is shown in the chat.
7. **Install.** The manifest is written to `~/Library/Application Support/Clicky/Plugins/<id>/`. Triggers register immediately.

## The plugin generator prompt (sketch)

```
You are Clicky's plugin compiler. The user will describe a behavior in natural language.
Your job is to emit a single JSON manifest that conforms to the schema below.

Hard rules:
- Output exactly one JSON object inside a fenced ```json block. No prose.
- Every "op" field must be one of [capture_screen, capture_region, transcript, prompt_claude,
  prompt_apple_local, speak, point_at, clipboard_write, clipboard_read, file_write, file_read,
  notify, applescript, shell, cursor_overlay_text, http_get, http_post]. Refuse to invent ops.
- For any file_write, populate scopes.file_write_paths with the exact path(s).
- For any http_get/http_post, populate scopes.allowed_domains with the exact host(s).
- Never include "applescript" or "shell" unless the user explicitly asks for them by name.
- Bindings use {{name}}. Every binding must be produced by an earlier action's bind_to.
- If the user's description is ambiguous, return a JSON object with only an "ask_user" field
  containing one specific clarifying question. Do not guess.

Schema:
<the JSON Schema, inlined>

Examples:
<3-4 worked examples covering: voice trigger, hotkey trigger, app-focus condition, file write, http>
```

Two things to notice:

- The schema goes *in the prompt*, not just as a post-validator. The model performs much better when it can see the shape.
- The model has an explicit escape hatch (`ask_user`) so it doesn't hallucinate when underspecified. The host turns `ask_user` into the next chat message.

## Runtime: how a plugin fires

There's a single new Swift type, `PluginRuntime`, that owns the plugin store and the trigger registries. It plugs into existing components:

- `CompanionManager` already routes the final transcript to Claude. The runtime intercepts *before* that step: if any installed `voice_phrase` / `voice_intent` plugin matches the transcript, its actions run *instead of* (or *in addition to*, configurable per plugin) the default chat behavior.
- `GlobalPushToTalkShortcutMonitor` gets a sibling, `PluginHotkeyMonitor`, that allocates from a reserved hotkey range and routes to the runtime.
- The menu-bar panel gains a *Plugins* section listing installed plugins with per-plugin enable/disable, last-run status, and an *Edit* button (opens the authoring chat with the manifest pre-loaded).

Execution is sequential, async, and idempotent-by-default. Each action returns a `Result`. On failure, the runtime stops and writes a structured entry to `log.jsonl`. The next press of the push-to-talk button cancels any in-flight plugin run (same `currentResponseTask?.cancel()` pattern that exists today).

## Security model

This is where most of the design weight lives, because *"users add plugins by talking"* is a phishing playground if we're sloppy.

### Threat model

1. A malicious shareable plugin link (`clicky://install?manifest=...`) tries to exfiltrate files or send the user's screenshots to an attacker domain.
2. A well-meaning plugin written by a benign user accidentally writes to `~/Documents` instead of `~/notes.md` because the LLM hallucinated a path.
3. A plugin uses `applescript` to silently empty the trash.
4. A plugin runs on every push-to-talk (because `match: regex /.*/`) and re-prompts Claude expensively in a loop.

### Mitigations

| Threat | Mitigation |
|--------|------------|
| Exfiltration via HTTP | `allowed_domains` is mandatory for `http_*`, approved per-domain at install, never wildcards. |
| Bad file paths | `file_write_paths` is a string list, approved verbatim at install, with home-relative expansion only. No globs. |
| AppleScript / shell abuse | Off by default. AppleScript requires per-install consent; shell is hidden behind a manual-edit-only flag with a second confirmation dialog. |
| Runaway loops | The runtime enforces: max 50 actions per run, max 5 runs/minute per plugin, max 1 MB of data passed through bindings, max 30s wall-clock per run. |
| Untrusted shared plugins | A shareable manifest opens the **authoring chat with a security review** instead of installing directly. Clicky narrates each scope and asks for confirmation phrase ("type 'install' to confirm"). |
| Privilege escalation between plugins | No cross-plugin bindings. Each plugin has its own `data/` directory. The runtime never passes one plugin's state to another. |

### What plugins *cannot* do, ever (no scope, no override)

- Read or write outside the plugin's declared paths.
- Execute arbitrary Swift / JavaScript / Python.
- Spawn long-lived background processes.
- Override system permissions (Accessibility, Screen Recording, etc.) — they always go through the user, exactly as they do today.
- Modify other plugins' manifests or data.
- Access Claude-API or AssemblyAI credentials directly (everything still routes through our Worker proxy).

## Cost model

A plugin's `prompt_claude` actions cost real money against our Worker / Anthropic bill. Three guardrails:

1. **Per-plugin budget**, default $0.50/day, configurable per install. When exceeded, the plugin is paused and the user gets a notification.
2. **Aggregate budget** across all plugins, default $5/day.
3. **Free path**: if `prompt_apple_local` works (macOS 26+, English, ≤4K tokens, no images), the generator prefers it. The generator system prompt instructs it to default to the local model when the task fits its constraints.

We can also let advanced users plug in their own Anthropic API key for their own plugins (BYO-key), which cleanly separates Farza's bill from the long tail.

## What this lets users build (concrete examples)

| Prompt | Generated plugin (sketch) |
|--------|---------------------------|
| *"When I say 'log this', take a screenshot, summarize what I'm working on in one line, and append to ~/worklog.md"* | voice_phrase `log this` → capture_screen → prompt_apple_local (free, no image needed if combined with a previous transcript) → file_write `~/worklog.md` append → speak "logged". |
| *"When I open Figma, show me a tip about Figma I might not know"* | trigger: hotkey `ctrl+option+t`, condition: frontmost_app `com.figma.Desktop` → prompt_claude with system "give me one Figma pro tip in 1 sentence" → speak. |
| *"When I say 'translate this', read my clipboard, translate to Spanish, write back to clipboard"* | voice_phrase `translate this` → clipboard_read → prompt_apple_local "translate the following to Spanish" → clipboard_write → notify "translated". |
| *"Every weekday at 9am, summarize my open tabs"* | schedule `0 9 * * 1-5` (requires explicit background opt-in) → applescript to query Safari tabs (requires AppleScript scope) → prompt_apple_local → notify. |
| *"When I click a coding icon I drew on screen, ask Claude to review the code"* | This is the kind of thing the system intentionally *can't* express — we'd need a new primitive (e.g., `image_region_classifier`). The user's request would get an `ask_user` response: *"I don't have a way to detect a hand-drawn icon. Want to use a hotkey instead?"* |

That last row is the important one: the system is supposed to *fail loudly* when the primitive set doesn't cover the request, so the user (and us, watching the logs) knows what primitive to build next.

## Phased rollout

**Phase 0 — the kernel.** No user-authored plugins yet. We refactor the existing voice flow into the runtime: the current "transcript → screenshot → prompt → speak → maybe point" pipeline becomes the **default plugin**, defined by a manifest shipped inside the app bundle. This proves the primitive set is sufficient to reproduce what we have today. No new UI.

**Phase 1 — first-party plugins.** We add 3-5 manifests shipped in the bundle (e.g., *Translate clipboard*, *Summarize screen*, *Daily standup*). Users can enable/disable from the panel. Still no authoring UI. Validates the runtime + UX of multiple installed plugins.

**Phase 2 — authoring UI for power users.** Chat-based authoring inside the panel. Generated manifests land in `~/Library/Application Support/Clicky/Plugins/`. Shareable manifest links go through a security-review screen on install. This is when the system becomes user-extensible.

**Phase 3 — plugin marketplace / directory.** Hosted directory of community plugins. Each plugin shows its manifest, scopes, and ratings before install. Optional.

**Phase 4 — primitives extensibility.** Once the primitive set is stable, expose a controlled SDK (Swift package) so trusted developers can ship new primitives as signed bundles. Far future; explicitly out of scope for the "no Swift code" promise above.

## What this changes in the existing codebase

Minimal day-1 changes if we ship Phase 0 first:

- New file: `PluginRuntime.swift` (orchestrator + primitive registry).
- New file: `PluginManifest.swift` (Codable types + schema validator).
- New file: `PluginStore.swift` (load/save to App Support, watch for file changes).
- `CompanionManager` voice-pipeline call site adds one line: *"if any installed plugin matches, dispatch to the runtime; else run the default flow."*
- The default flow itself becomes a bundled manifest.
- The panel gains a *Plugins* row (post-Phase-1).

The Worker doesn't need to change at all — every LLM/TTS/transcribe call still goes through the same `/chat`, `/tts`, `/transcribe-token` routes.

## Open questions

These need a decision before Phase 0 starts:

1. **Pre-empt or augment?** When a plugin matches the voice transcript, should the default "ask Claude about the screen" behavior still run alongside, or be replaced? Recommendation: replace by default, allow `also_run_default: true` in the manifest.
2. **Where do generated manifests live during authoring?** In a `drafts/` subdirectory until installed, or only in memory? Recommendation: drafts directory, so the user can quit and resume.
3. **Local vs cloud LLM for the *generator* itself.** Foundation Models on macOS 26 is fast and free but its 4K context and lack of structured-output reliability may not be enough to emit valid manifests against a 200-line schema. Recommendation: cloud Claude for the generator, local model for plugin-runtime prompts where it fits.
4. **Versioning.** Manifests have a `version` field but no migration story. Recommendation: bump major version of the schema only when we remove a primitive; otherwise additive-only forever.

## What this does *not* try to be

- A general-purpose macOS automation tool. Use Shortcuts / Keyboard Maestro / Hammerspoon for that. Clicky's plugin system is for behaviors that *integrate with the cursor, voice, and Claude*.
- A scripting language. There are no loops, no conditionals beyond the `conditions` array, no expressions. If a behavior needs logic, the right answer is "the LLM action does the logic in its prompt."
- A way to make money. Phase 3 (marketplace) is optional and the plugin runtime stands on its own.

## TL;DR for skeptical reviewers

> *"This is just dynamic dispatch over a fixed primitive table, with the LLM as a glorified UI for filling out a JSON form."*

Yes — and that's the point. The hard work is choosing the primitive set, the schema, the security boundaries, and the generator prompt. Once those exist, "users add features by talking" is essentially free.
