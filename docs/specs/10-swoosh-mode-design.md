# Designing Swoosh Mode

> **Status**: design doc / RFC. Sibling to `09-plugin-system-design.md` — Swoosh and Plugins are different runtimes that share primitives and convert into each other.

## The pitch in one paragraph

A **Swoosh task** is a long-running, agentic job. The user describes a task ("research the top 5 SwiftUI animation libraries and put a comparison in `~/notes/animations.md`"). The cursor swooshes off screen as if it's leaving for another desktop. While it's "gone," a Claude agent loop runs on the user's real machine — taking screenshots, deciding actions, calling tools — and the user sees a minimal progress halo or just a dimmed UI. When the task completes, the cursor swooshes back with a result card. If the user likes what happened, they can **save the run as a plugin** — the agent's trace compiles into a deterministic plugin manifest so the next run is replay, not re-inference.

## Architectural decisions, settled

These come from prior conversation with the user. Do not relitigate without going back to them.

1. **No real macOS Spaces.** The "swoosh to another desktop" is a UX illusion: a full-screen overlay window that *looks* like a separate workspace. The agent acts on the user's real Mac through a hidden capture-and-input layer. There is no private CGS API call, no Mission Control automation, no fast user switching.

2. **Real isolation (virtualization) is the eventual destination**, not the v1 plan. Build the agent runtime so the host environment is *abstracted behind a tool layer* — a single `SwooshHost` protocol that v1 implements against the real Mac, and a future v2 swaps for a local VM (`Virtualization.framework`) or a remote sandbox. See `memory/swoosh_isolation_strategy.md`.

3. **Liked runs become plugins.** Swoosh compiles its successful trace into a Phase-2 plugin manifest (`docs/specs/09-plugin-system-design.md`). Future invocations of the same task replay the plugin and never hit the agent loop. See `memory/swoosh_saves_as_plugin.md`.

4. **Swoosh and Plugins are sibling runtimes**, not the same runtime. They share primitives.

5. **Swoosh stays cloud-only in v1.** Even when the rest of Clicky is in Hybrid or Local mode (see `docs/specs/11-offline-and-local-models.md`), Swoosh's agent loop calls Claude (Sonnet 4.6 default, Opus 4.6 for hard tasks). Open-weight tool-use accuracy is not yet reliable enough for multi-step planning. The path to local Swoosh is documented in `11`'s "Local Swoosh: when, not if" section. Compile-on-save still works in any mode — once a Swoosh becomes a plugin, the plugin can use local primitives, which is how Local-mode users still benefit from Swoosh-authored workflows without paying API cost on every re-run.

## How Swoosh and Plugins relate

```
┌────────────────────────────────────────────────────────────────┐
│                       Shared primitive layer                   │
│  capture_screen · click · type · open_app · prompt_claude      │
│  prompt_apple_local · speak · file_read · file_write · …       │
└─────────┬──────────────────────────────────┬───────────────────┘
          │                                  │
          ▼                                  ▼
   ┌──────────────┐                  ┌──────────────────┐
   │ PluginRuntime│                  │ SwooshRuntime    │
   │              │                  │                  │
   │ - linear DAG │                  │ - agent loop     │
   │ - seconds    │                  │ - minutes-hours  │
   │ - cheap      │                  │ - expensive      │
   │ - replay     │                  │ - inference      │
   │   (deter-    │                  │ - branching,     │
   │    ministic) │                  │   error recovery │
   └──────▲───────┘                  └──────┬───────────┘
          │   compile-on-save               │
          └──────────────────────────────────┘
              (Swoosh trace → Plugin manifest)
```

Two arrows worth noticing:

- A Swoosh task can call a Plugin via a `run_plugin` tool (composes existing user-authored plugins as sub-routines).
- A successful Swoosh run can be **compiled** into a Plugin (the "save this swoosh" flow). After that, calling the same task hits the deterministic Plugin runtime, not the Swoosh runtime.

## The agent stack

| Layer | What it is |
|-------|------------|
| **LLM** | Claude (Sonnet 4.6 default; Opus 4.6 for "hard" mode). Routed through the Worker's `/agent` route — a new SSE-streamed route alongside `/chat`. |
| **Loop** | Anthropic Agent SDK semantics — `tool_use` content blocks, `tool_result` blocks, multi-turn until the model returns `stop_reason: "end_turn"` or the runtime hits a budget cap. |
| **Tools** | A registered catalogue, declared in JSON-schema. Categories below. |
| **Host** | The `SwooshHost` protocol — implements each tool against the real Mac in v1; swappable for VM/remote later. |
| **Recorder** | Captures `(observation_before, decision, tool_call, observation_after)` tuples to an in-memory ring buffer + a JSONL file in the task workspace. |
| **Supervisor** | A budget/safety layer that gates every tool call: budget left? destructive? scope allowed? max actions? |
| **UI** | Overlay swoosh-out, working state, swoosh-back, result card. Reuses `OverlayWindow.swift` patterns. |

## Tool catalogue

Strict superset of plugin primitives, with a few agent-only tools added.

### Sensors (read-only)

| Tool | Notes |
|------|-------|
| `capture_screen(which)` | All displays or just the cursor screen. Same code as the existing `CompanionScreenCaptureUtility`. |
| `capture_window(bundle_id?)` | A single window's pixels — useful when the agent wants to focus on one app. |
| `read_accessibility_tree(bundle_id?)` | Returns the AX hierarchy of the focused window as JSON. Cheap, structured, often eliminates the need for vision-heavy screenshots. **Important** — the cheaper the agent's sensors, the cheaper the task. |
| `read_clipboard()` | `NSPasteboard`. |
| `read_file(path)` | Path must be inside the task's declared scope. |
| `list_directory(path)` | Same scope rules. |
| `http_get(url)` | Allowlist-only — the task declares which domains it can read. |

### Actuators (writes / side-effects)

| Tool | Notes |
|------|-------|
| `click(x, y, button?)` | Synthesizes a CGEvent. Requires the cursor be inside the swoosh-controlled region (see below). |
| `type(text)` | Posts key events. **Confirmation gate** if the focused window is one the user marked as sensitive (1Password, banking sites, …). |
| `key_combo(["cmd","s"])` | Same gating. |
| `open_app(bundle_id)` | `NSWorkspace.shared.open`. |
| `move_window(bundle_id, frame)` | AX API. |
| `write_clipboard(text)` | `NSPasteboard`. |
| `write_file(path, body, append?)` | Strict scope allowlist, same as plugins. |
| `applescript(script)` | Opt-in per-task. Off by default. |
| `http_post(url, body)` | Allowlist-only. |
| `run_plugin(plugin_id, params)` | Delegates a step to an installed plugin. The plugin's manifest still enforces its own scopes — the agent cannot escalate by chaining plugins. |
| `notify(title, body)` | User notification — does not break the swoosh illusion. |

### Agent-only meta-tools

| Tool | Notes |
|------|-------|
| `think(thought)` | The model writes private reasoning that doesn't go to the user. Useful for keeping the visible result card clean. |
| `progress_update(text, percent?)` | The agent reports progress to the swoosh overlay. Streamed live to the user. |
| `ask_user(question, options?)` | The swoosh momentarily un-dims so the user can answer; the agent pauses. Counts against the task's interaction budget. |
| `request_destructive_confirm(action, target)` | The runtime is *required* to call this before any irreversible action (file delete, money movement, sending a message, posting publicly). User clicks confirm/deny. |
| `complete(summary, artifacts)` | Marks the task done. `summary` is shown in the result card; `artifacts` is a list of files/links the user can open. |
| `give_up(reason)` | The agent declares it can't finish. Triggers the failure UX. |

The model's system prompt tells it: *"You may only call tools from the catalogue I provide. Inventing a tool name returns an error. If a needed capability doesn't exist, call `give_up` with a precise description of the missing capability."* Same hallucination-defense pattern as the plugin generator.

## The swoosh UX, frame by frame

1. **Idle.** Normal Clicky. User clicks the panel's *Swoosh* button or says "clicky, swoosh this — research X and write Y."
2. **Task definition.** A small overlay sheet appears. The user types/dictates the task; Claude (one cheap up-front call, not in the agent loop) extracts: intent, scope of files it can touch, allowed domains, hard budget. The user sees and approves all four.
3. **Swoosh-out.** The cursor overlay animates the triangle off the side of the screen with a curved trail. The user's whole screen dims behind a translucent dark overlay. Cursor returns to its normal OS shape mid-animation so the user can still see where their pointer is.
4. **Working state.** The dim overlay carries a small floating progress card: current step ("scanning research", "writing to file"), elapsed time, tokens/dollars spent so far, a *Cancel* button. The agent loop is running underneath; the user can still see and use their screen but is gently encouraged not to disturb it.
5. **Interruption handling.** If the user moves their cursor or types, the supervisor pauses the agent and asks: *"You moved — should I pause Swoosh until you say so?"* This avoids the agent racing the user.
6. **Result card.** On `complete`, the cursor swooshes back to its idle position carrying a result card: summary, list of files changed / artifacts created, total cost, and three buttons — *Run again*, *Save as plugin*, *Discard*.
7. **Failure card.** On `give_up` or budget exhaustion, similar card with what was done so far and an *Undo where possible* button (uses the audit log to reverse reversible actions).

The swoosh-out + swoosh-back are the only places where the illusion of "another desktop" lives. The work itself is right there on the user's screen — the dim overlay is what sells "this is happening elsewhere."

## Safety supervisor

This sits between the model and every tool call. Every call is checked:

1. **Schema** — does the tool exist? are the parameters well-formed?
2. **Scope** — is the file path / domain / app inside the task's declared allowlist?
3. **Budget** — are we under the dollar cap? action count? wall clock?
4. **Destructive class** — is the call in the destructive set? If yes, the supervisor inserts a `request_destructive_confirm` call before the actual action and waits for the user.
5. **Rate** — no more than N actions per minute. Prevents pathological loops.

Destructive set (non-exhaustive): `write_file` with `append=false` and existing file; any `applescript`; any `http_post`; any `key_combo` targeting `cmd+delete` or `cmd+shift+delete`; any tool call when the focused window is on the sensitive-app list.

Audit log: every tool call + result is written to `~/Library/Application Support/Clicky/Swoosh/<task-id>/audit.jsonl`. Includes a screenshot before and after every actuator. The user can replay it visually after the fact. This is also the input to plugin compilation.

## Worker changes

A new route, `POST /agent`. Wire-compatible with Anthropic's Messages streaming, but with `tools` populated from the Swoosh tool catalogue and `tool_choice: "auto"`. The Worker forwards verbatim, just like `/chat`.

```
POST /agent → api.anthropic.com/v1/messages (stream)
   body: { model, max_tokens, system, tools, messages, stream: true }
   response: SSE — each tool_use block triggers a host-side execution,
             the host posts the next turn with tool_result blocks.
```

The agent loop itself runs **client-side** on the Mac, not in the Worker. This matters: the tools execute locally (clicking, screen-grabbing), and tunneling those through Cloudflare would be ridiculous. The Worker is purely the LLM proxy.

## Saving a Swoosh as a plugin

The headline feature for cost control.

### What gets recorded

During execution, the recorder produces a trace:

```jsonc
{
  "task_id": "swoosh-2026-05-22-1657",
  "user_prompt": "make a daily standup summary in ~/notes/standup.md",
  "scopes_approved_by_user": { "files": ["~/notes/standup.md"], "domains": ["github.com"] },
  "model": "claude-sonnet-4-6",
  "started_at": "2026-05-22T16:57:00Z",
  "ended_at":   "2026-05-22T17:02:14Z",
  "cost_usd": 1.23,
  "steps": [
    {
      "step": 1,
      "observation": { "screen_capture": "step-1.jpeg" },
      "thinking": "I need to gather today's GitHub activity first.",
      "tool_call": { "name": "http_get", "params": { "url": "https://api.github.com/users/farzaa/events" } },
      "tool_result": { "status": 200, "body": "[…]" }
    },
    …
    { "step": 14, "tool_call": { "name": "complete", "params": { … } } }
  ]
}
```

### What the compiler does

When the user clicks **Save as plugin**, the runtime fires one final Claude call with:

- The user's original prompt
- The full trace (or a summarized view if it's huge)
- The plugin schema (the same one in `09-plugin-system-design.md`)
- An explicit compilation prompt

The compiler's job:

1. **Strip exploration.** The agent may have tried three approaches before one worked — keep only the successful path.
2. **Collapse to primitives.** Each `tool_call` maps 1:1 to a plugin primitive (the tool catalogue is a strict superset). Map them.
3. **Parameterize.** Identify literal values that should be inputs next time (filenames, URLs, dates). Emit them as `{{params.X}}` references with sensible defaults.
4. **Emit a manifest.** Conform to the Phase-2 plugin schema. Include scope declarations that match what the user already approved for the original Swoosh task.
5. **Mark `swoosh_fallback` per step.** Default: `false`. Optional: per-step opt-in to fall back to agent mode if a deterministic replay fails (UI changed, web page restructured). The user toggles this in the review screen.

The compilation prompt explicitly says: *"You are converting an agent trace into a deterministic plugin manifest. You may NOT add steps the trace didn't contain. You may REMOVE exploratory dead-ends. You may RENAME literals into parameters. The user will review your output before it installs."*

### Review and install

Same UI as user-authored plugins from `09-plugin-system-design.md` Phase 2: the user sees the manifest in plain English, ticks the scope checkboxes (mostly pre-ticked because they approved the same scopes for the Swoosh), and clicks Install. The compiled plugin lands in `~/Library/Application Support/Clicky/Plugins/` like any other.

### What this buys

| | First Swoosh run | Saved Plugin replay |
|---|------------------|---------------------|
| Cost | $1–5 (agent loop) | ~$0 if no `prompt_claude` actions; cents otherwise |
| Time | Minutes | Seconds |
| Determinism | Stochastic | Deterministic until external state shifts |
| Failure recovery | Built-in (agent reasons) | None unless `swoosh_fallback: true` per step |

This is the answer to *"how does Swoosh stay affordable"* — repeated tasks migrate to deterministic replays as the user finds patterns that work.

## Configuration

`UserDefaults` additions:

- `swooshDailyBudgetUSD` — default `$5`, hard cap, user can lower but not raise above a per-account ceiling.
- `swooshPerTaskBudgetUSD` — default `$2`, configurable per task at definition time.
- `swooshAllowDestructiveByDefault` — default `false`. When false, every destructive action gates on `request_destructive_confirm`. When true (advanced users only), only the most catastrophic ones do.
- `swooshSensitiveAppBundleIds` — array of bundle IDs the agent must not click/type in. Pre-populated with `com.agilebits.onepassword7`, `com.1password.1password`, and a few obvious banking apps.

`AGENTS.md` will need an addition documenting:

- The new `/agent` Worker route.
- The two runtimes (Plugin, Swoosh) and the compile-on-save bridge.
- The `SwooshHost` abstraction and why it exists (future virtualization).

## Phased rollout

**Phase S0 — Foundations.** Add `SwooshHost`, `SwooshRuntime`, `SwooshSupervisor`, `SwooshRecorder` types. Implement the tool catalogue. No UI yet — drive it from unit tests / a developer-only menu item. Verify the agent loop completes for 3 hand-crafted test tasks within budget.

**Phase S1 — Internal UX.** Wire the swoosh-out/swoosh-back animations into the existing `OverlayWindow.swift`. Add the working state overlay and result card. Internal-only; the Swoosh entry point is hidden behind a debug flag.

**Phase S2 — Public preview.** Add the *Swoosh* button to the panel. Ship with a strict default per-task budget cap of $1 and a hard daily cap of $3. Telemetry: success rate, cost per task, cancel rate, "save as plugin" rate.

**Phase S3 — Compile-on-save.** Implement trace → plugin manifest compilation. Requires the plugin system from `09-plugin-system-design.md` to be at Phase 2 (authoring UI exists). Compiled plugins appear in the Plugins list with a *"from Swoosh"* badge.

**Phase S4 — Real isolation.** Swap the `SwooshHost` v1 (real Mac) for a v2 backend — either a local `Virtualization.framework` VM with a macOS guest, or a remote sandboxed compute target Clicky drives over RPC. At this point the swoosh illusion stops being an illusion: the agent is genuinely operating somewhere else.

## Open questions

1. **Where does the agent loop *physically* run during v1?** Options:
   - On the macOS app's main process. Simplest, but a runaway loop could starve the UI.
   - In a separate XPC service. Better isolation; more wiring.
   - In a hidden Swift Concurrency `Task` group with strict cancellation. Recommendation: this, plus a watchdog.
2. **How does the agent "see" the screen without the swoosh overlay being in every screenshot?** The screenshot tool must exclude Clicky's own windows (the existing `CompanionScreenCaptureUtility` already does — reuse).
3. **What happens if the user clicks during the agent's `click(x, y)` call?** Recommendation: the supervisor briefly pauses input via a `CGEvent` tap on input events for the ~50ms around each actuator call. Trade-off: a felt sluggishness if the user happens to type at that exact moment.
4. **Should Swoosh tasks be cancelable mid-action?** Yes — Cancel should issue a `Task.cancel()`, halt at the next supervisor checkpoint, and run an "attempt to undo" pass using the audit log.
5. **Multi-step destructive confirmations get annoying.** Idea: a *"trust me for this task"* checkbox in the first confirm dialog — disables further confirmations *for this single task*, never globally. Worth testing.

## What this design intentionally does *not* do

- **Doesn't run on the user's behalf when they're away.** Swoosh requires the user to be at the machine, watching, ready to confirm. Scheduled / unattended Swoosh is a separate, much harder design (the user can't confirm destructives; harder to detect "the UI changed").
- **Doesn't try to be a general-purpose RPA tool.** We do not compete with UI-Path / Robocorp / Hammerspoon. The point is *natural-language-described tasks within Clicky's existing voice/cursor mental model*.
- **Doesn't ship full automation in v1.** Compiled plugins from Swoosh are the *only* form of replayable automation in v1. We do not let users write Swoosh tasks in YAML or any DSL — it's always *describe in language → agent runs → save if it worked.*

## Cost reduction via local models *during* a Swoosh run

Beyond compile-on-save, there's a second cost lever: the agent's *observations* don't all need to go through Claude. Two specific places where a Swoosh run can call cheap local models without compromising the planner's reasoning:

- **OCR-instead-of-vision for screen observations.** The agent's `capture_screen` tool can be augmented by `read_text_from_screen()` (powered by `Vision`'s `RecognizeTextRequest`). When the agent just needs to know "what's on the screen as text," sending OCR text + bounding boxes to Claude is dramatically cheaper than re-sending the JPEG. The planner stays Claude; the perception is free.
- **Summarization with Foundation Models.** If the agent retrieves a long web page or file and only needs a 1-sentence gist, route that summarization through `prompt_apple_local` (Foundation Models, on-device, free) instead of a Claude turn. The planner sees the gist as a tool result.

Both are opt-in optimizations the agent's system prompt can recommend, gated by the supervisor (which knows the user's mode setting). In **Local mode** (see doc 11), these become defaults. In **Cloud mode**, they're disabled — the user is paying for the maximum-quality path.

The supervisor's mode-aware tool routing:

| Mode | Planner LLM | Vision tool | Summarization tool | Decision LLM for "which OCR box matches the request" |
|------|-------------|-------------|--------------------|------------------------------------------------------|
| **Cloud** | Claude | full JPEG to Claude | Claude | Claude |
| **Hybrid** | Claude | OCR text + JPEG (Claude sees both) | Foundation Models when ≤4K tokens | Foundation Models |
| **Local** | *Swoosh disabled* — UI explains why | — | — | — |

The third row is the honest answer: Swoosh requires Claude in v1. A user in Local mode who tries to start Swoosh sees a panel that says *"Swoosh needs Claude's planner. Switch to Hybrid for this task, or use a saved Swoosh-plugin instead."* The compile-on-save bridge is what makes this acceptable — Local-mode users still benefit from Swoosh-built automations, they just can't author new ones.

## TL;DR

Swoosh is "Clicky goes somewhere and does the thing." The "somewhere" is an overlay illusion now and a real VM later. Successful runs compile into deterministic plugins so repeated tasks stop being expensive — and the resulting plugins can use local primitives even when the original Swoosh used Claude, so Local-mode users get the same automations at zero cost. The plugin runtime and the Swoosh runtime are different code paths but share the same primitive catalogue, and that catalogue is the contract that keeps the whole system honest.
