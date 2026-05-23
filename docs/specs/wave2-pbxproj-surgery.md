# Wave 2 — `project.pbxproj` Surgery Plan

Read-only enumeration of every edit the Wave-2 dead-code-removal PR needs
to apply against `leanring-buddy.xcodeproj/project.pbxproj` and the
companion Swift source `leanring-buddy/WindowPositionManager.swift`.

## TL;DR — the surprising finding

The Xcode project uses **`PBXFileSystemSynchronizedRootGroup`** (the
"synchronized folder" reference introduced in Xcode 16 / `objectVersion = 77`).
Every `.swift` file under `leanring-buddy/` is implicitly part of the
target by virtue of living in that folder — **there are no per-file
`PBXFileReference`, `PBXBuildFile`, group, or `PBXSourcesBuildPhase`
entries** for individual Swift files.

Verified by grep against `leanring-buddy.xcodeproj/project.pbxproj`:

```
$ grep -n "OpenAIAPI.swift"             leanring-buddy.xcodeproj/project.pbxproj
(no matches)
$ grep -n "ElementLocationDetector.swift" leanring-buddy.xcodeproj/project.pbxproj
(no matches)
$ grep -n "OpenAI"                       leanring-buddy.xcodeproj/project.pbxproj
(no matches)
$ grep -n "Element"                      leanring-buddy.xcodeproj/project.pbxproj
(no matches)
```

The only `PBXSourcesBuildPhase` entries (lines 247–269) all have empty
`files = ( )` lists. The only `PBXBuildFile` entries (lines 10–11) are
for the Sparkle and PostHog SwiftPM products. The only file references
(lines 32–34) are for the three built `.app` / `.xctest` bundles.

The relevant block is the synchronized root group declaration at
**lines 37–53**:

```
/* Begin PBXFileSystemSynchronizedRootGroup section */
        28F22CC12F56440300A0FC59 /* leanring-buddy */ = {
            isa = PBXFileSystemSynchronizedRootGroup;
            path = "leanring-buddy";
            sourceTree = "<group>";
        };
        28F22CCF2F56440300A0FC59 /* leanring-buddyTests */ = { ... };
        28F22CD92F56440300A0FC59 /* leanring-buddyUITests */ = { ... };
/* End PBXFileSystemSynchronizedRootGroup section */
```

…and the target's `fileSystemSynchronizedGroups` reference at
**lines 117–119**:

```
        fileSystemSynchronizedGroups = (
            28F22CC12F56440300A0FC59 /* leanring-buddy */,
        );
```

**Implication for Wave 2**: deleting `leanring-buddy/OpenAIAPI.swift`
and `leanring-buddy/ElementLocationDetector.swift` from the filesystem
is sufficient. Xcode will pick up the absence on next open. No
`project.pbxproj` edit is required for those two files.

---

## Section 1 — `OpenAIAPI.swift` removal

### pbxproj entries

| Entry kind          | UUID  | Line number | Line content |
|---------------------|-------|-------------|--------------|
| `PBXFileReference`  | none  | n/a         | (file is not individually referenced — covered by synchronized folder group `28F22CC12F56440300A0FC59`) |
| `PBXBuildFile`      | none  | n/a         | (no individual build-file wrapper exists) |
| Group `children`    | none  | n/a         | (no per-file group entry — synchronized folder enumerates the filesystem) |
| `PBXSourcesBuildPhase` `files` | none | n/a | (`28F22CBB2F56440300A0FC59 /* Sources */`, lines 248–254, has empty `files = ( )`) |

### Action

```bash
git rm leanring-buddy/OpenAIAPI.swift
```

No `sed`/no pbxproj edit. The synchronized root group at line 38
(`28F22CC12F56440300A0FC59 /* leanring-buddy */`) will simply not see
the file the next time Xcode reads the folder.

---

## Section 2 — `ElementLocationDetector.swift` removal

### pbxproj entries

| Entry kind          | UUID  | Line number | Line content |
|---------------------|-------|-------------|--------------|
| `PBXFileReference`  | none  | n/a         | (covered by synchronized folder group `28F22CC12F56440300A0FC59`) |
| `PBXBuildFile`      | none  | n/a         | — |
| Group `children`    | none  | n/a         | — |
| `PBXSourcesBuildPhase` `files` | none | n/a | (empty `files = ( )`) |

### Action

```bash
git rm leanring-buddy/ElementLocationDetector.swift
```

No `sed`/no pbxproj edit.

---

## Section 3 — `WindowPositionManager.swift` — method-only removal

The file stays. Only the two legacy methods get deleted.

### `pinMainWindowToRight(onDisplayID:)`

- **File**: `leanring-buddy/WindowPositionManager.swift`
- **Lines to delete**: **153–181** (inclusive)
  - Line 153: `    // MARK: - Window Positioning`
  - Line 154: blank
  - Lines 155–156: doc comment (`/// Positions the app's main window …`)
  - Line 157: `static func pinMainWindowToRight(onDisplayID displayID: CGDirectDisplayID?) {`
  - Lines 158–180: method body
  - Line 181: closing `}`

  The Wave-2 agent should also drop line 182 (the blank line that
  immediately follows) to avoid two consecutive blank lines.

### `shrinkOverlappingFocusedWindow(targetDisplayID:)`

- **File**: `leanring-buddy/WindowPositionManager.swift`
- **Lines to delete**: **183–251** (inclusive)
  - Line 183: `    // MARK: - Shrink Overlapping Windows`
  - Line 184: blank
  - Lines 185–187: doc comment (`/// Checks if the frontmost …`)
  - Line 188: `static func shrinkOverlappingFocusedWindow(targetDisplayID: CGDirectDisplayID?) {`
  - Lines 189–250: method body
  - Line 251: closing `}`

  Line 252 (the blank line) and line 253 (`}` closing the class) stay.
  Lines 254+ (the `NSScreen` extension) stay.

### Combined recommendation

Delete **lines 153–251** in one contiguous range, then squash any
double-blank-line residue. After the cut the file should end with the
`permissionRequestPresentationDestination(...)` method's closing `}`
(currently at line 151), followed by a blank line, then the closing
class brace, then the `NSScreen` extension.

### Call-site search

Searched the entire worktree (`leanring-buddy/` + `docs/` + `worker/`)
for both method names. Findings:

| Reference                                                       | Type                |
|-----------------------------------------------------------------|---------------------|
| `leanring-buddy/WindowPositionManager.swift:157` `pinMainWindowToRight` | the definition itself |
| `leanring-buddy/WindowPositionManager.swift:188` `shrinkOverlappingFocusedWindow` | the definition itself |
| `AGENTS.md:75`                                                  | doc mention         |
| `DELETION_PLAN.md:59,60,71`                                     | doc mention         |
| `docs/reference/04-file-reference.md:72`                        | doc mention         |
| `docs/reference/03-features.md:186,187`                         | doc mention         |
| `docs/specs/15-feature-improvements.md:74`                      | doc mention         |
| `docs/adr/0007-sandbox-disabled.md:13`                          | doc mention (only `shrinkOverlappingFocusedWindow`) |

**No Swift call sites.** Neither method is invoked anywhere in the
`leanring-buddy/` target. The Wave-2 PR does not need to drop any
call site — only the definitions. Doc mentions can be updated as part
of the Wave-2 doc-housekeeping pass, but they are not load-bearing
references.

---

## Section 4 — Verification checklist for the Wave-2 agent

Run after applying the deletions, before opening the PR:

- [ ] `git grep -n "OpenAIAPI"` returns only matches inside
      `leanring-buddy/OpenAIAudioTranscriptionProvider.swift` (the
      `OpenAIAPIKey` Info.plist key — not the class) and inside
      `docs/`. **No matches in any other `leanring-buddy/*.swift` file.**
- [ ] `git grep -n "ElementLocationDetector"` returns only `docs/`
      matches. **Zero matches in `leanring-buddy/`.**
- [ ] `git grep -n "pinMainWindowToRight"` returns only `docs/`
      matches. **Zero matches in `leanring-buddy/`.**
- [ ] `git grep -n "shrinkOverlappingFocusedWindow"` returns only
      `docs/` matches. **Zero matches in `leanring-buddy/`.**
- [ ] `plutil -lint leanring-buddy.xcodeproj/project.pbxproj` exits 0
      (pbxproj is a valid plist — relevant even though we didn't edit
      it, as a paranoia sanity check).
- [ ] `wc -l leanring-buddy.xcodeproj/project.pbxproj` reports **635
      lines** — unchanged from the pre-Wave-2 baseline. (Synchronized
      folder reference; we expect zero pbxproj diff.)
- [ ] `git status` shows exactly three modified/deleted paths
      (`leanring-buddy/OpenAIAPI.swift` deleted,
      `leanring-buddy/ElementLocationDetector.swift` deleted,
      `leanring-buddy/WindowPositionManager.swift` modified) — plus
      whatever doc updates the Wave-2 PR opts to include.
- [ ] Xcode opens the project without "missing file" warnings and the
      target builds. (User's manual verification — do NOT run
      `xcodebuild` from the terminal, see `CLAUDE.md`.)

---

## Section 5 — Risk notes

The biggest risk in pbxproj surgery is leaving an orphaned UUID
reference — for example, removing a `PBXFileReference` but forgetting
the matching `PBXBuildFile`, which causes Xcode to fail to open the
project with a "missing object" plist error. **That risk is moot in
this case**: because the project uses `PBXFileSystemSynchronizedRootGroup`,
the Wave-2 PR doesn't touch `project.pbxproj` at all for the two
file-deletions. The only at-risk edit is the in-file line range
deletion inside `WindowPositionManager.swift`, where the worst case is
a Swift compile error from an unbalanced brace — caught immediately by
Xcode and trivially recoverable.

If anything does go wrong:

```bash
# Revert just the pbxproj (paranoia — should be a no-op):
git checkout HEAD -- leanring-buddy.xcodeproj/project.pbxproj

# Revert the WindowPositionManager edit:
git checkout HEAD -- leanring-buddy/WindowPositionManager.swift

# Restore the deleted files from the previous commit:
git checkout HEAD~1 -- leanring-buddy/OpenAIAPI.swift leanring-buddy/ElementLocationDetector.swift
```

A second consideration is that the synchronized-folder feature is
relatively new (Xcode 16+). If the Wave-2 agent or any contributor is
on an older Xcode, the "auto-pickup on file removal" behavior may
silently not happen and the deleted files will still appear in the
project navigator (greyed-out). The mitigation is to require the
Wave-2 PR be opened, reviewed, and merged using Xcode 16.2 or later —
which is already the project's `objectVersion = 77` minimum.
