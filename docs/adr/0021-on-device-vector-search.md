# ADR 0021 — Vector search runs on-device with `NLContextualEmbedding` + `sqlite-vec`

**Status**: Proposed
**Date**: 2026-05-22
**Deciders**: Farza, Claude Code session
**Related**: [ADR 0006](./0006-in-memory-conversation-history.md), [ADR 0018](./0018-cloud-hybrid-local-mode-picker.md)
**Source spec**: `docs/specs/12-vector-search-and-memory.md`

## Context

Clicky needs vector search for three use cases (see `specs/12`):

1. Conversation memory beyond the 10-turn in-memory cap.
2. Plugin discovery and intent routing once 5+ plugins are installed.
3. Optional long-term screen memory (Rewind-like).

The realistic stack options:

1. **Cloud embedding API** (OpenAI text-embedding-3, Voyage, Cohere) + remote vector DB (Pinecone, Qdrant, Weaviate). Powerful, but breaks the privacy posture for any user who cares — every conversation turn would leave the device.
2. **Cloud embedding API + local store**. Reduces blast radius but the embedding text still leaves the device.
3. **Local embedding + local store.** Privacy-clean but quality depends on the local embedder.

For the local-embedder options:

- **Apple `NLContextualEmbedding`** (iOS 17+ / macOS 14+) — Apple's framework. 512-dim, multilingual, on-device, free, requires an asset download (~150 MB) the first time.
- **Sentence-transformers via Core ML** — third-party models converted from PyTorch. Higher quality but a build-time conversion pipeline + model-storage burden.
- **`NLEmbedding`** (legacy) — predecessor to `NLContextualEmbedding`. Lower quality, deprecated trajectory.

For the local-store options:

- **`sqlite-vec`** — SQLite extension, 1 KB compiled, MIT, exact + ANN kNN, no separate server.
- **LanceDB / Pinecone-local** — heavier dependencies, more capable but unnecessary for our scale.
- **In-memory only** — fast but doesn't survive app launches.

## Decision

We use **Apple `NLContextualEmbedding`** as the embedding model and **SQLite + the `sqlite-vec` extension** as the vector store. Both on-device. Both free. Both bundled.

The database lives at `~/Library/Application Support/Clicky/embeddings.db`. Embeddings are unit-normalized at insert time so cosine similarity becomes dot product (faster in `sqlite-vec`). Three logical tables: `conversation_turns`, `plugin_intents`, `screen_observations` (the last one only populated when the user opts in to screen memory).

The whole stack works identically in Cloud / Hybrid / Local modes — it's local-only by design. This is what lets us promise "your memory never leaves your Mac" in any mode.

## Consequences

### Positive

- Zero ongoing API cost. No bills, no rate limits, no provider lock-in.
- True privacy: the embedded text never leaves the device. This is the only way to deliver opt-in screen memory ethically.
- Latency is sub-10-ms for queries against ~100K rows on Apple Silicon. Imperceptible.
- No server, no daemon, no separate process. Single SQLite file the user can back up or delete.
- `sqlite-vec` is tiny (~1 KB statically linked) — negligible app-binary impact.
- `NLContextualEmbedding` is bundled with the OS on recent macOS versions; the one-time asset download (when needed) is borne by Apple.

### Negative

- `NLContextualEmbedding` requires macOS 14+. Older systems get either a degraded experience (legacy `NLEmbedding`) or the feature is disabled entirely. Most of Clicky's user base is already 14+.
- 512-dim embeddings are smaller than state-of-the-art (1536, 3072). Quality is good but not best-in-class. For Clicky's three use cases this is acceptable; for a "company-grade RAG" product it wouldn't be.
- If Apple silently updates the embedding model in a future macOS release, old embeddings may no longer be comparable to new ones. `specs/12` proposes storing a model-version column per row and re-embedding lazily — a real maintenance burden if it happens.
- Multilingual support is good but uneven. Non-English voice transcripts may retrieve less reliably until validated.
- `sqlite-vec` is younger than its alternatives; some API churn possible. The file format is stable, however.

### Neutral / trade-offs

- The retrieval pipeline is dead-simple: one SQL query with a vector match. We don't need a graph index, a hybrid retriever, or a re-ranker for our scale. If we ever do, switching from `sqlite-vec` to LanceDB is a backend change, not a redesign.
- No cloud option is offered. A privacy-paranoid user gets what they want; an enterprise-RAG user is not the target.

## Notes

- This ADR partially supersedes [ADR 0006](./0006-in-memory-conversation-history.md). The "10 turns in memory" remains the *recency window*; the vector store provides the *long-term recall*. Both coexist.
- The screen-memory feature ships **off by default** and gated behind privacy controls (retention, app exclusion list, "forget this hour" button). This is documented in `specs/12` and is the only ethical way to ship Rewind-class functionality without breaking trust.
- A future ADR may revisit if Apple ships a meaningfully better local embedder, or if `sqlite-vec` becomes unmaintained. The retrieval API is small enough that the implementation could be swapped without changing callers.
