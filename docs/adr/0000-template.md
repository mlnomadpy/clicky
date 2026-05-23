# ADR NNNN — Short imperative title

**Status**: Template
**Date**: YYYY-MM-DD
**Deciders**: who-signed-off
**Related**: (links to related ADRs by number, e.g., `[ADR 0005](./0005-nspanel-everywhere.md)`)

<!--
Status values:
  - Proposed              (drafted, not yet accepted)
  - Accepted              (active decision)
  - Accepted (retroactive) (decision was already in the codebase; ADR documents it after the fact)
  - Superseded by ADR NNNN (no longer in effect; link to the replacement)
  - Deprecated            (no longer relevant; nothing replaces it)
  - Rejected              (considered and turned down)
  - Template              (this file; do not change)

Numbering is permanent once an ADR lands on `main`. Never edit a past ADR —
write a new one and set its status to "Superseded by ADR NNNN".
-->

## Context

What problem are we solving? What constraints, prior art, alternatives, and
forces are in play? Cite specific files / line numbers / commits when useful,
e.g. `leanring_buddyApp.swift:14`. Two to six short paragraphs is the right
weight — long enough to capture the trade-off, short enough that a future
reader doesn't skim.

If this ADR documents a decision that was *already made* in the codebase
(retroactive), say so here and explain what the alternatives would have been
at the time.

## Decision

State the decision in 1–3 short paragraphs. Be specific and binary — not "we
considered using X" but "we use X". The reader should be able to act on this
without reading the Context section.

## Consequences

### Positive
- What working in our favor because we made this choice
- Things downstream code can rely on

### Negative
- Real cost of the choice — performance, complexity, lock-in, blast radius
- Things this choice prevents us from doing later

### Neutral / trade-offs
- Things that are neither wins nor losses but the next maintainer should know
- Operational implications (extra moving piece, new permission, etc.)

## Notes

Optional. Anything else worth recording — commit refs, useful links, names
of the people who pushed back, lessons learned during implementation.
