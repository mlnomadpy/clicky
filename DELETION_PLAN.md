# Deletion Plan — Dead Code Scheduled for Wave-2 Removal

This document tracks Swift sources flagged by the system audit
(`docs/reference/04-file-reference.md`) and `docs/specs/15-feature-improvements.md`
Tier 1 items §1.4–§1.6 as dead code that is not on the active hot path.

**Nothing in this list is deleted by the PR that introduces this file.**
The PR that introduces this file only marks and documents the intent.
The actual code removal happens in a later **Wave-2 PR**.

### Update — pbxproj surgery is NOT required

When this doc was originally drafted, we expected the Wave-2 PR to also
edit `leanring-buddy.xcodeproj/project.pbxproj` to drop each file's
references. **That assumption was wrong.** The project uses Xcode 16's
`PBXFileSystemSynchronizedRootGroup` (`objectVersion = 77`): the entire
`leanring-buddy/` directory is auto-synchronized via a single group
UUID, and individual Swift files are not registered in `project.pbxproj`
at all. See `docs/specs/wave2-pbxproj-surgery.md` for the full finding.

**Consequence**: removing a Swift file is `git rm <path>` and nothing
else. Adding a Swift file is creating the file and nothing else. The
risk profile of the Wave-2 PR is therefore much lower than originally
documented — no pbxproj surgery, no manual Xcode UI work required for
the deletion itself.

---

## Item 1 — `leanring-buddy/OpenAIAPI.swift`

- **Path / line range**: `leanring-buddy/OpenAIAPI.swift` (entire file, ~142 LOC).
- **Justification**: a full GPT vision client that is not called anywhere
  in the active code paths. The model string defaults to
  `"gpt-5.2-2025-12-11"` — a suspiciously future-dated identifier that
  signals the file has drifted out of sync with reality. Cited by the
  audit in `docs/specs/15-feature-improvements.md` §1.4 and by the file
  reference in `docs/reference/04-file-reference.md` ("Not on the active
  hot path").
- **Removal blocked by**: Wave-2 PR that updates `project.pbxproj`.
- **Verification when removed**: build in Xcode (`Cmd+R`), then a fresh
  push-to-talk round-trip (`ctrl+option` → speak → release → confirm
  Claude responds with text + TTS audio).

---

## Item 2 — `leanring-buddy/ElementLocationDetector.swift`

- **Path / line range**: `leanring-buddy/ElementLocationDetector.swift`
  (entire file, ~335 LOC).
- **Justification**: uses Anthropic's Computer Use API for pointing, but
  the current hot path parses Claude's `[POINT:x,y]` tag directly from
  regular chat responses. The file is unreachable from any active call
  site. Cited by the audit in `docs/specs/15-feature-improvements.md`
  §1.6 and by the file reference in `docs/reference/04-file-reference.md`
  ("Not on the current hot path"). Local-mode pointing
  (`docs/specs/11-offline-and-local-models.md` §OCR-pointing trick) is
  being designed from scratch with Vision OCR + Foundation Models, so
  reusing this file would mostly be a name collision. Git history is
  preserved if a future spec calls for resurrection.
- **Removal blocked by**: Wave-2 PR that updates `project.pbxproj`.
- **Verification when removed**: build in Xcode (`Cmd+R`), then a fresh
  push-to-talk round-trip with a pointing question (e.g., "where's the
  search bar?") and confirm the blue cursor still flies to the target.

---

## Item 3 — Legacy helpers inside `leanring-buddy/WindowPositionManager.swift`

- **Path / line range**: the two methods
  `pinMainWindowToRight(onDisplayID:)` and
  `shrinkOverlappingFocusedWindow(targetDisplayID:)` inside
  `leanring-buddy/WindowPositionManager.swift`.
- **Scope clarification**: **only those two methods**. The permission
  utilities in the same file (`hasAccessibilityPermission`,
  `requestAccessibilityPermission`, Screen Recording helpers, etc.) are
  **not** dead — they are the file's actual purpose and stay.
- **Justification**: these helpers were used when Clicky had a docked
  main window. The current architecture is menu-bar only
  (`LSUIElement=true`, no main window), so the helpers have no caller.
  Cited by the audit in `docs/specs/15-feature-improvements.md` §1.5 and
  by the file reference in `docs/reference/04-file-reference.md`
  ("legacy `pinMainWindowToRight` / `shrinkOverlappingFocusedWindow`
  helpers — not on the current hot path"). §1.5 also recommends
  eventually renaming the surviving file to `PermissionsHelper.swift`
  and moving it under `Features/Permissions/`, but that is part of the
  FSD restructure (`docs/specs/13-folder-structure-fsd.md`), not this
  cleanup.
- **Removal blocked by**: Wave-2 PR that updates `project.pbxproj`
  (only required if the file is also renamed/moved; pure in-file method
  deletion does not require pbxproj edits, but the Wave-2 PR will batch
  this with the FSD rename so the project file changes once).
- **Verification when removed**: build in Xcode (`Cmd+R`), then a fresh
  push-to-talk round-trip, plus a permission re-prompt smoke check
  (revoke Accessibility in System Settings → relaunch → confirm the
  Grant flow still triggers).

---

## Wave-2 PR checklist (for the future agent)

When the Wave-2 PR is opened:

1. Delete the three Swift sources / code blocks listed above.
2. Edit `leanring-buddy.xcodeproj/project.pbxproj` to remove the
   `OpenAIAPI.swift` and `ElementLocationDetector.swift` file references
   (the `PBXBuildFile` + `PBXFileReference` + `PBXSourcesBuildPhase`
   entries). Have the user open Xcode side-by-side and watch the file
   tree update.
3. Open Xcode, build with `Cmd+R`, and run the push-to-talk round-trip.
4. Update `docs/reference/04-file-reference.md` to drop the three rows
   entirely (this PR only annotates them).
5. Update `AGENTS.md` to drop the three rows entirely.
6. Update `docs/specs/15-feature-improvements.md` §1.4–§1.6 to flip the
   status line to "shipped".
7. Update `docs/00-roadmap.md` Phase 0 row to ⏺ Done.
8. Delete this `DELETION_PLAN.md` file (its job is finished).
