# Designing Vector Search & Memory

> **Status**: design doc / RFC. Companion to `09-plugin-system-design.md`, `10-swoosh-mode-design.md`, and `11-offline-and-local-models.md`.

## Why this exists

Three concrete problems vector search solves in Clicky:

1. **Conversation memory beyond the 10-turn cap.** Today `CompanionManager.conversationHistory` keeps the last 10 turns and discards the rest. Users notice — *"remember that Swift thing yesterday?"* returns a blank stare.
2. **Plugin discovery and intent routing.** The `voice_phrase` plugin trigger relies on exact / fuzzy string matching, which doesn't scale past a handful of plugins.
3. **Optional long-term screen memory** — a Rewind-style feature where Clicky can answer *"what was that error from this morning?"*. High value, high privacy stakes — strictly opt-in.

All three run on the same infrastructure: a tiny local vector store, fed by an on-device embedder, queried at relevant moments in the pipeline.

## Settled choices

These come from earlier conversation. Don't relitigate without going back to the user.

1. **Embeddings stay on-device.** No third-party embedding API. Apple's `NLContextualEmbedding` (iOS 17+ / macOS 14+) is the default. Free, multilingual, 512-dim.
2. **Storage is local-only**. SQLite + the `sqlite-vec` extension (1 KB MIT-licensed, exact + ANN kNN, no separate server, no daemon).
3. **Three use cases, three feature flags**. Conversation memory ships on; plugin intent routing ships on once 5+ plugins are installed; screen memory ships **off** and never auto-enables.
4. **Works in all three modes** (Cloud / Hybrid / Local). Retrieval is always local; only the *consumer* of retrieved context differs (Claude vs Foundation Models).

## What we *won't* do

- **No remote vector DB.** No Pinecone / Qdrant / Weaviate / Postgres+pgvector. The whole point is "your memory never leaves your Mac."
- **No multimodal embeddings (CLIP-style).** Possible, but the marginal accuracy gain over embedding the OCR text is small, and CLIP-quality models are heavy. The OCR-then-text-embed path is enough.
- **No knowledge-base / file-upload feature.** Different product. Resist scope creep.
- **No fine-tuning the embedder.** `NLContextualEmbedding` is good enough off the shelf for these use cases.

## On-device stack

```
                  ┌──────────────────────────────────────────┐
                  │ EmbeddingService                         │
                  │   - one wrapper around                   │
                  │     NLContextualEmbedding (default)      │
                  │     or a bundled CoreML model (fallback) │
                  │   - returns [Float] of length 512        │
                  └─────────────┬────────────────────────────┘
                                │
                  ┌─────────────▼────────────────────────────┐
                  │ VectorStore                              │
                  │   - SQLite + sqlite-vec                  │
                  │   - schema: items + embeddings columns   │
                  │   - kNN via vec_distance_cosine          │
                  └─────────────┬────────────────────────────┘
                                │
              ┌─────────────────┼─────────────────┐
              ▼                 ▼                 ▼
       ┌─────────────┐  ┌─────────────┐  ┌─────────────┐
       │ Conversation│  │ Plugin      │  │ Screen      │
       │ Memory      │  │ Intents     │  │ Memory      │
       │ (Phase V1)  │  │ (Phase V2)  │  │ (Phase V3)  │
       └─────────────┘  └─────────────┘  └─────────────┘
```

### `EmbeddingService`

```swift
@MainActor
final class EmbeddingService {
    private let model: NLContextualEmbedding

    init() async throws {
        guard let embedding = NLContextualEmbedding(language: .english) else {
            throw EmbeddingError.unavailable
        }
        if !embedding.hasAvailableAssets {
            try await embedding.requestAssets()
        }
        try embedding.load()
        self.model = embedding
    }

    func embed(_ text: String) throws -> [Float] {
        guard let vector = try? model.embeddingResult(for: text, language: .english) else {
            throw EmbeddingError.failed
        }
        // sentenceEmbedding is a [Double]; convert + normalize to unit length so
        // cosine similarity is equivalent to dot product (faster in sqlite-vec).
        return normalize(vector.sentenceEmbedding.map(Float.init))
    }
}
```

`NLContextualEmbedding` requires an asset download on first use (~150 MB). The asset is bundled with the OS on recent macOS versions but on older ones requires `requestAssets()`. UX: show a one-time progress bar during onboarding *after* permissions and *before* the first push-to-talk.

### `VectorStore` schema

One SQLite file at `~/Library/Application Support/Clicky/embeddings.db`. Three logical tables (the actual `sqlite-vec` columns are stored in companion vec tables; this is the conceptual schema):

```sql
-- Conversation memory: every user/assistant turn ever
CREATE TABLE conversation_turns (
  id              INTEGER PRIMARY KEY,
  timestamp       INTEGER NOT NULL,         -- unix epoch
  role            TEXT NOT NULL,            -- "user" | "assistant"
  text            TEXT NOT NULL,
  app_bundle_id   TEXT,                     -- foreground app when turn happened (NULL if unknown)
  plugin_id       TEXT                      -- which plugin handled this turn, if any
);
CREATE VIRTUAL TABLE conversation_turns_vec USING vec0(
  embedding float[512]
);

-- Plugin intents: one row per installed plugin
CREATE TABLE plugin_intents (
  plugin_id       TEXT PRIMARY KEY,
  description     TEXT NOT NULL,            -- the plugin's name + description
  example_phrases TEXT                      -- optional, JSON array
);
CREATE VIRTUAL TABLE plugin_intents_vec USING vec0(
  embedding float[512]
);

-- Screen memory (Phase V3, opt-in only)
CREATE TABLE screen_observations (
  id              INTEGER PRIMARY KEY,
  timestamp       INTEGER NOT NULL,
  app_bundle_id   TEXT NOT NULL,
  ocr_text        TEXT NOT NULL,
  screenshot_path TEXT,                     -- relative to ~/Library/.../Clicky/screen_memory/
  expires_at      INTEGER NOT NULL          -- timestamp + retention_seconds
);
CREATE VIRTUAL TABLE screen_observations_vec USING vec0(
  embedding float[512]
);
```

### Retrieval — the only query pattern that matters

```swift
func similar(to query: String, in source: VectorSource, topK: Int) async throws -> [Hit] {
    let queryVector = try embedder.embed(query)
    // sqlite-vec: SELECT ... WHERE embedding MATCH ? AND k = ?
    return try db.execute("""
        SELECT id, distance FROM \(source.tableName)_vec
        WHERE embedding MATCH ? AND k = ?
        ORDER BY distance
    """, parameters: [queryVector, topK])
        .map { Hit(id: $0.id, distance: $0.distance) }
}
```

`vec_distance_cosine` is implicit when the vector is unit-normalized at insert time. The whole query takes <5 ms for stores under 100K rows on Apple Silicon.

## Phase V1 — Conversation memory

The cheap, high-value piece. Ship first.

### Capture

In `CompanionManager.sendTranscriptToClaudeWithScreenshot`, after the exchange is appended to `conversationHistory`:

```swift
await embeddingsService.recordTurn(role: .user, text: transcript)
await embeddingsService.recordTurn(role: .assistant, text: spokenText)
```

Both calls are non-blocking — they fire-and-forget into a serial dispatch queue inside `EmbeddingService`. If embedding fails, the turn isn't indexed; the rest of the pipeline doesn't care.

### Retrieve

Before constructing the Claude / Foundation Models prompt, retrieve relevant older turns:

```swift
let recent = conversationHistory   // unchanged: last 10 turns verbatim
let retrieved = try await embeddingsService.similar(to: transcript, in: .conversation, topK: 3)
    .filter { $0.distance < 0.45 }   // tune empirically; smaller = more similar
    .filter { !recent.contains(byId: $0.id) }  // de-dupe with the recent window

let systemContext = """
\(Self.companionVoiceResponseSystemPrompt)

Earlier exchanges that may be relevant:
\(retrieved.map { "user: \($0.userText)\nassistant: \($0.assistantText)" }.joined(separator: "\n\n"))
"""
```

The retrieved context is appended *to the system prompt*, not to the messages array. This keeps the chronological message history clean and lets Claude treat retrieved bits as "background knowledge" rather than "the conversation."

### Budget

A retrieved turn is small (~100 tokens), top-3 caps total at ~300 tokens — negligible. We can grow this to top-5 later if useful.

### Cap

Conversation history grows forever, but realistically a heavy user produces ~500 turns/day → ~3.5K turns over a week → manageable. Soft cap: 100K rows total, evict oldest beyond that. Hard cap: 1 GB database file, with an "I'm getting big" warning at 800 MB.

### Privacy

The DB file is in the user's library. No cloud sync. A *Clear conversation memory* button in the panel deletes all rows in `conversation_turns` and `conversation_turns_vec`. Disabling the feature stops new writes and deletes existing rows.

## Phase V2 — Plugin intent routing

Once 5+ plugins are installed, exact-match `voice_phrase` triggers become a poor UX. Vector search makes intent routing real.

### Capture

At plugin install / update, embed the plugin's `name` + `description` + optional `example_phrases`:

```swift
let docs = [
    plugin.name,
    plugin.description,
    plugin.examplePhrases.joined(separator: ". ")
].joined(separator: ". ")

await embeddingsService.recordPluginIntent(pluginId: plugin.id, text: docs)
```

### Match

When a transcript arrives, before the default Claude flow runs:

```swift
let hits = try await embeddingsService.similar(to: transcript, in: .pluginIntent, topK: 3)
    .filter { $0.distance < 0.35 }  // tighter threshold than conversation

guard let top = hits.first else { return defaultFlow() }

switch top.distance {
case ..<0.20:
    // Very confident — auto-fire the plugin
    runtime.dispatch(top.pluginId, transcript: transcript)
case ..<0.35:
    // Less confident — ask the user
    overlay.showSuggestion("Run \(plugin.name)?")
default:
    defaultFlow()
}
```

Thresholds are empirical and tuned during Phase V2 beta. Per-plugin auto-fire opt-in is in the plugin manifest:

```jsonc
{
  "trigger": {
    "type": "voice_intent",
    "examples": ["take a note of this", "save this for later"],
    "auto_fire_distance": 0.22   // optional override
  }
}
```

### What this replaces

The `voice_phrase` trigger from `09-plugin-system-design.md` stays for users who want literal-string matching. `voice_intent` is the new trigger powered by V2. The plugin generator's system prompt is updated to prefer `voice_intent` over `voice_phrase` for natural-language tasks.

## Phase V3 — Screen memory (opt-in, behind a feature flag)

The Rewind-like feature. Powerful, useful, and a privacy bomb if mishandled.

### Capture (only when enabled)

Every time `CompanionScreenCaptureUtility.captureAllScreensAsJPEG()` runs (i.e., per push-to-talk turn) AND screen memory is enabled:

1. Run `Vision.RecognizeTextRequest` on each screen capture → array of `(text, boundingBox, confidence)`.
2. Concatenate the high-confidence text strings, capped at ~500 tokens per screen.
3. Skip insertion if the foreground app's bundle ID is on the user's exclusion list.
4. Embed the concatenated text and insert into `screen_observations` + the vec table.
5. Store a thumbnail of the screenshot at 256 px max edge (≈ 20 KB JPEG) for the result UI.

This happens **after** the user's normal voice turn — never before, so capture latency doesn't gate the user-facing response.

### Retrieve

A new plugin primitive: `retrieve_screen_memory(query, top_k, time_window?)`. Returns hits with timestamp, text, thumbnail path, and app name. Used by plugins like *"what was that error message?"*.

The runtime also surfaces it via a dedicated query mode in the panel: *"Ask my memory"* → small overlay with a text field → results with thumbnails and timestamps. This is the most visible screen-memory feature.

### Privacy controls (mandatory before V3 ships)

These all live in the panel under *Privacy & Memory*:

| Control | Default | Purpose |
|---------|---------|---------|
| **Master toggle** | OFF | The whole feature off unless the user opts in. |
| **Retention** | 7 days | Auto-delete after N days. Options: 1, 7, 30, 90 days, indefinite. |
| **Excluded apps** | 1Password, Mail, Signal, browser private windows | User can add or remove. Pre-populated with the obvious privacy-sensitive apps. |
| **Indexed apps allowlist** | All except above | Optional inverse — *only* index these apps. For paranoid users. |
| **Forget this hour** button | — | Deletes all observations from the past hour with a single tap. |
| **Forget [specific app]** button | — | Deletes all observations for one app. |
| **Browse memory** | — | A simple list view of recent observations the user can scrub through and delete individually. |
| **Pause for** | — | Stop indexing for 5 min / 1 hour / until midnight. |

The exclusion list is checked **after** capture but **before** OCR/embedding/insert — minimizing what touches the index in the first place.

### Auto-purge

A background task on app launch removes any row where `expires_at < now`. This is cheap (single SQL DELETE).

### What screen memory does NOT do

- No cloud sync. Ever.
- No sharing with plugins that don't have `screen_memory_read` scope.
- No exporting to a third-party service via a plugin's `http_post` primitive — the runtime blocks this combination explicitly (a plugin can't both query screen memory and call out to a non-loopback domain in the same run).
- No always-on background capture. Only captures during the user's voice turns (which only happen when they push the hotkey). This is a meaningful difference from Rewind, which captures continuously.

## Integration with the plugin system

Three new primitives extend the catalogue in `docs/specs/09-plugin-system-design.md`:

| Primitive | What it does | Scope required |
|-----------|--------------|----------------|
| `retrieve_similar(source, query, top_k)` | Queries any of the vector sources the plugin has scope for. | `vector_read: ["conversation"]` etc. |
| `retrieve_screen_memory(query, top_k, time_window?)` | Convenience wrapper around screen observations. | `screen_memory_read: true` + master toggle must be on. |
| `embed_text(text)` | Returns a 512-dim embedding. Mostly useful for advanced plugins doing their own kNN over plugin-specific data. | `vector_compute: true` |

The plugin generator's system prompt is updated to know about these. It biases toward using `retrieve_similar(.conversation)` when the user's task is about recall ("remind me what we discussed about X").

## Integration with Swoosh

The Swoosh agent gets a corresponding tool — `retrieve_similar` — for two scenarios:

1. **Reuse prior decisions.** Before re-doing research the user already did, the agent queries conversation memory. If a similar previous discussion exists, the agent can summarize-and-confirm instead of re-running expensive research.
2. **Identify recurring patterns.** The agent can check whether this task has been attempted before, and if so, refer the user to the existing saved plugin (the compile-on-save bridge).

Screen memory is **not** exposed to Swoosh by default — the agent gets to see the current screen, not the user's history. A per-task opt-in could change this later, but the default is "no past visual snooping."

## Phased rollout

**Phase V0 — Infrastructure.** Add `EmbeddingService`, `VectorStore`, schema, basic CRUD. Wire `NLContextualEmbedding` and validate the asset-download UX. No user-facing surface yet.

**Phase V1 — Conversation memory.** Capture every turn, retrieve top-3 with cosine threshold, inject into system prompt. Ship the *Clear conversation memory* button. Measure: do retrieved turns improve user satisfaction (less "do you remember…" frustration)?

**Phase V2 — Plugin intent routing.** Index plugin intents at install/update. Replace `voice_phrase` matching with `voice_intent` for plugins that opt in. Tune thresholds in beta. Ship the suggestion UX ("Run X?") and the per-plugin auto-fire setting.

**Phase V3 — Screen memory (opt-in, behind flag).** Ship the privacy controls *first*, then the capture pipeline. Default off, with onboarding that explicitly describes what gets indexed. Add `retrieve_screen_memory` to the plugin catalogue.

**Phase V4 (post-MVP) — Memory editing UX.** A panel view that lets users browse, search, edit, and delete entries across all three sources. Useful as the indexes grow.

## Hardware & OS requirements

- `NLContextualEmbedding`: macOS 14+ (iOS 17+). Below this, fall back to a bundled small CoreML embedding model (or disable the feature with a clear message).
- `sqlite-vec`: pure C, runs anywhere SQLite does. Bundled as a static library.
- Disk: ~100 MB / 100K rows including embeddings and thumbnails. Screen memory at default 7-day retention typically settles under 500 MB.

## Cost

Zero ongoing API cost — everything is on-device. The one-time costs:

- `NLContextualEmbedding` asset download (~150 MB on first use) — borne by Apple, free to us.
- Disk space for the SQLite file — the user's, capped by retention policy.

This is what makes the feature compatible with all three modes (Cloud / Hybrid / Local) — Local-mode users get full vector search with no compromises.

## Open questions

1. **Threshold tuning.** The cosine-distance thresholds (`0.45` for conversation, `0.35` for intent, `0.20` for auto-fire) are starting points. Phase V1 and V2 should ship with a hidden setting to tweak them and gather data.
2. **Multi-lingual.** `NLContextualEmbedding` supports many languages but embedding quality varies. We should test it with non-English voice transcripts before claiming "works in any language."
3. **Should we embed the screenshot (OCR-text) alongside the conversation turn?** It would let *"remember when I was looking at that Figma file"* work — but doubles the index size. Recommendation: defer to Phase V3 when screen memory exists in parallel.
4. **Re-embedding after model upgrades.** If `NLContextualEmbedding`'s asset is upgraded by a future macOS release, old embeddings may not be comparable to new ones. Recommendation: store the model version with each row, re-embed lazily on read if mismatched.
5. **Plugin marketplace and intent collisions.** Two plugins with similar descriptions will collide in intent routing. The runtime needs a tiebreaker — recently-used? user-preferred? alphabetical? Recommendation: most-recently-used wins, with the suggestion UX surfacing both.

## TL;DR

Three features, one infrastructure. Conversation memory ships first because it's cheap and high-value. Intent routing ships next because it makes the plugin system actually usable past 5 plugins. Screen memory ships last because it's a privacy decision more than a technical one — the controls need to be excellent before the capture pipeline turns on. Everything runs on-device with Apple's free embedding model and SQLite. Zero cloud, zero ongoing cost, works identically in Cloud / Hybrid / Local modes.
