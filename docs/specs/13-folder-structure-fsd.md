# Folder Structure — Feature Slice Design

> **Status**: design doc / RFC. The most urgent piece of Phase 0. Until this lands, every new feature in specs 09–12 piles more files onto an already-too-flat top-level directory.

## Why this exists

Today `leanring-buddy/` is 22 Swift files in one flat directory. `CompanionManager.swift` (1026 LOC) imports and coordinates ~10 other files; `OverlayWindow.swift` (881 LOC) is a god view; `BuddyDictationManager.swift` (866 LOC) is both the audio engine and the permission state machine. New work in the specs would add ~15 more files — plugin runtime, plugin store, swoosh runtime, swoosh supervisor, embedding service, vector store, local model runtime, etc. Flat won't scale.

Feature Slice Design (FSD) — originally a frontend convention — solves exactly this: organize by **vertical slice of behavior**, not by horizontal layer (no `models/`, `views/`, `services/` directories). Each slice owns its UI, state, types, and tests.

## Target layout

```
leanring-buddy/
├── App/                                     # entry point, app-level wiring
│   ├── ClickyApp.swift                      # renamed from leanring_buddyApp.swift
│   ├── CompanionAppDelegate.swift           # extracted from leanring_buddyApp.swift
│   ├── AppBundleConfiguration.swift         # was: AppBundleConfiguration.swift
│   ├── Info.plist
│   └── leanring-buddy.entitlements
│
├── Features/                                # one folder per vertical slice
│   ├── VoicePipeline/                       # push-to-talk + transcription
│   │   ├── BuddyDictationManager.swift
│   │   ├── BuddyTranscriptionProvider.swift
│   │   ├── BuddyAudioConversionSupport.swift
│   │   ├── GlobalPushToTalkShortcutMonitor.swift
│   │   └── Providers/
│   │       ├── AssemblyAIStreamingTranscriptionProvider.swift
│   │       ├── OpenAIAudioTranscriptionProvider.swift
│   │       └── AppleSpeechTranscriptionProvider.swift
│   │
│   ├── CursorOverlay/                       # blue triangle + flight animation
│   │   ├── OverlayWindow.swift              # NSWindow subclass + manager
│   │   ├── BlueCursorView.swift             # extracted from OverlayWindow.swift
│   │   ├── BlueCursorWaveformView.swift     # extracted
│   │   ├── BlueCursorSpinnerView.swift      # extracted
│   │   ├── BuddyNavigationAnimator.swift    # bezier-arc flight logic extracted
│   │   ├── OnboardingVideoPlayerView.swift  # extracted
│   │   └── CompanionResponseOverlay.swift
│   │
│   ├── MenuBarPanel/                        # status item + dropdown panel
│   │   ├── MenuBarPanelManager.swift
│   │   ├── CompanionPanelView.swift
│   │   └── Components/
│   │       ├── ModelPickerRow.swift         # extracted from CompanionPanelView
│   │       ├── PermissionsSection.swift     # extracted
│   │       ├── OnboardingEmailSection.swift # extracted
│   │       └── FooterSection.swift          # extracted
│   │
│   ├── ScreenCapture/
│   │   └── CompanionScreenCaptureUtility.swift
│   │
│   ├── ClaudeChat/                          # the AI chat brain
│   │   ├── ClaudeAPI.swift
│   │   ├── ClaudeSystemPrompts.swift        # extracted from CompanionManager
│   │   ├── PointTagParser.swift             # extracted (parsePointingCoordinates)
│   │   ├── PointCoordinateMath.swift        # the screenshot→display math, deduped
│   │   └── ConversationHistory.swift        # extracted
│   │
│   ├── ElevenLabsTTS/
│   │   └── ElevenLabsTTSClient.swift
│   │
│   ├── Onboarding/
│   │   ├── OnboardingFlow.swift             # extracted from CompanionManager
│   │   ├── OnboardingVideoController.swift  # extracted
│   │   ├── OnboardingMusicController.swift  # extracted
│   │   ├── OnboardingDemoInteraction.swift  # extracted (performOnboardingDemoInteraction)
│   │   └── OnboardingEmailSubmission.swift  # extracted (submitEmail)
│   │
│   ├── Permissions/
│   │   ├── PermissionManager.swift          # extracted from CompanionManager
│   │   └── WindowPositionManager.swift      # legacy helpers stay together
│   │
│   ├── Plugins/                             # NEW — spec 09
│   │   ├── PluginManifest.swift             # Codable types + JSON Schema
│   │   ├── PluginRuntime.swift              # orchestrator
│   │   ├── PluginStore.swift                # disk load/save/watch
│   │   ├── PluginSupervisor.swift           # scope + budget checks
│   │   ├── PrimitiveRegistry.swift          # the shared catalogue
│   │   └── Primitives/                      # one file per primitive
│   │       ├── CaptureScreenPrimitive.swift
│   │       ├── PromptClaudePrimitive.swift
│   │       ├── PromptAppleLocalPrimitive.swift
│   │       ├── …
│   │       └── (see specs 09 and 11 for the full list)
│   │
│   ├── Swoosh/                              # NEW — spec 10
│   │   ├── SwooshRuntime.swift              # agent loop
│   │   ├── SwooshHost.swift                 # protocol abstracting real Mac vs future VM
│   │   ├── SwooshSupervisor.swift           # budget + destructive-action gating
│   │   ├── SwooshRecorder.swift             # trace recording
│   │   ├── SwooshCompiler.swift             # trace → plugin manifest
│   │   └── Tools/                           # agent-only meta-tools
│   │       ├── ThinkTool.swift
│   │       ├── ProgressUpdateTool.swift
│   │       └── …
│   │
│   ├── LocalModels/                         # NEW — spec 11
│   │   ├── FoundationModelsRuntime.swift
│   │   ├── LocalVLMRuntime.swift            # MLX-Swift integration
│   │   ├── VisionOCRService.swift           # Vision.RecognizeTextRequest
│   │   ├── ModelDownloadManager.swift
│   │   └── ModeRouter.swift                 # Cloud/Hybrid/Local dispatch
│   │
│   └── VectorMemory/                        # NEW — spec 12
│       ├── EmbeddingService.swift           # NLContextualEmbedding wrapper
│       ├── VectorStore.swift                # SQLite + sqlite-vec
│       ├── ConversationMemory.swift         # use-case wrapper
│       ├── PluginIntentRouter.swift         # use-case wrapper
│       └── ScreenMemory.swift               # use-case wrapper (Phase V3)
│
├── Entities/                                # cross-feature domain types
│   ├── VoiceState.swift                     # CompanionVoiceState enum
│   ├── ScreenCapture.swift                  # CompanionScreenCapture struct
│   ├── PluginManifest.swift                 # imported by Plugins, Swoosh, MenuBarPanel
│   ├── Coordinate.swift                     # CGPoint + display-frame helpers
│   └── ConversationTurn.swift               # the unit of conversation history
│
├── Shared/                                  # truly cross-cutting (no domain)
│   ├── DesignSystem/
│   │   ├── DSColors.swift                   # extracted from DesignSystem.swift
│   │   ├── DSCornerRadius.swift             # extracted
│   │   ├── DSTypography.swift               # extracted
│   │   ├── DSStyles.swift                   # extracted
│   │   └── DSModifiers.swift                # extracted (pointerCursor, etc.)
│   ├── Analytics/
│   │   └── ClickyAnalytics.swift
│   ├── Logging/                             # NEW — replaces ad-hoc print() calls
│   │   ├── ClickyLogger.swift               # os.Logger wrapper
│   │   └── LogCategory.swift
│   └── Concurrency/
│       └── CancellableTaskBag.swift         # NEW — extract the task-cancellation pattern used across CompanionManager
│
├── State/                                   # the central state object — but split
│   ├── CompanionManager.swift               # SHRUNK from 1026 LOC to coordinator only
│   ├── VoicePipelineCoordinator.swift       # extracted
│   ├── AIResponseCoordinator.swift          # extracted (sendTranscriptToClaudeWithScreenshot)
│   ├── OverlayCoordinator.swift             # extracted (cursor visibility, transient hide)
│   └── ModelSelection.swift                 # extracted (selectedModel + setSelectedModel)
│
└── Resources/                               # non-code bundled assets
    ├── Assets.xcassets
    ├── enter.mp3
    ├── eshop.mp3
    ├── ff.mp3
    ├── steve.jpg
    └── codex-add-project.png
```

Top-level groups (`App`, `Features`, `Entities`, `Shared`, `State`, `Resources`) live as filesystem directories AND as Xcode groups with matching names.

## FSD layer rules

Strictly enforced. Every Swift file lives in exactly one layer.

```
                  imports allowed
   App   ────────────────────────────────► everything
   State ────────────────────────────────► Features, Entities, Shared
   Features ─────────────────────────────► Entities, Shared
   Entities ─────────────────────────────► Shared
   Shared ───────────────────────────────► (nothing — pure leaves)
```

Cross-feature imports between `Features/X/` and `Features/Y/` are **forbidden**. If two features need to talk, they do so through:

1. A type in `Entities/`, or
2. A coordinator in `State/` that owns both, or
3. A `Notification` posted on `NotificationCenter`.

This rule is the whole point of FSD. Without it, `CompanionManager` is reborn under a different name.

### Why a `State/` layer (FSD usually doesn't have one)

Classic FSD frontends use a per-feature state library and global stores live in `app/` or `widgets/`. Clicky has one big `CompanionManager` that today touches every feature. We split it into thin coordinators (one per major flow) and keep them together in `State/` so the dependency graph is obvious. They are the only files allowed to import multiple features.

Long-term goal: `State/` shrinks as each feature owns more of its own state. The `Coordinator` types are an intermediate step, not a final form.

## The big file splits

These three files account for 2773 LOC — more than a third of the codebase. Each gets surgical decomposition.

### `CompanionManager.swift` (1026 LOC → ~250 LOC)

Stays the central published `ObservableObject` the panel observes, but delegates most behavior:

```swift
@MainActor
final class CompanionManager: ObservableObject {
    @Published private(set) var voiceState: CompanionVoiceState = .idle
    @Published private(set) var lastTranscript: String?
    // ... published surface for the panel stays the same ...

    let voice: VoicePipelineCoordinator
    let response: AIResponseCoordinator
    let overlay: OverlayCoordinator
    let onboarding: OnboardingFlow
    let permissions: PermissionManager
    let modelSelection: ModelSelection

    // wires Combine cancellables that publish into self.voiceState etc.
    func start() { ... }
    func stop() { ... }
}
```

Each coordinator is ~150–250 LOC and owns a focused slice of what the big class does today.

### `OverlayWindow.swift` (881 LOC → 4 files, none > 300 LOC)

- `OverlayWindow.swift` — the `NSWindow` subclass + `OverlayWindowManager` (~100 LOC)
- `BlueCursorView.swift` — the main SwiftUI view (~300 LOC)
- `BuddyNavigationAnimator.swift` — bezier-arc flight, scale, rotation logic (~200 LOC)
- `BlueCursorWaveformView.swift`, `BlueCursorSpinnerView.swift`, `OnboardingVideoPlayerView.swift` — each in its own file (~80 LOC apiece)

### `BuddyDictationManager.swift` (866 LOC → 3 files)

- `BuddyDictationManager.swift` — the @MainActor state object (~400 LOC)
- `BuddyPushToTalkShortcut.swift` — the enum and transition parsing extracted (~200 LOC)
- `BuddyDictationPermissionGate.swift` — the deduplicating permission request logic (~200 LOC)

### `DesignSystem.swift` (880 LOC → 5 files)

Split by *kind of token*, not by component. `DSColors.swift`, `DSCornerRadius.swift`, `DSTypography.swift`, `DSStyles.swift`, `DSModifiers.swift`. Each is ~150–250 LOC. The `DS` namespace lives in `DSColors.swift` (or its own tiny `DesignSystem.swift`) and the rest are extensions.

## Migration plan

Six steps, each a separate PR. Each PR is *mechanical* — no behavior changes.

### Step 1 — Add the new folders, move *one* feature

Move `Plugins/` would be greenfield, but as a warmup we move an existing feature with few cross-dependencies: **`ScreenCapture/`**. One file, one move, one PR. Verifies the Xcode group ↔ filesystem mapping works.

### Step 2 — Move the leaf features

Move features that import only `Shared` and `Entities`: `VoicePipeline/`, `CursorOverlay/`, `MenuBarPanel/`, `ScreenCapture/`, `ClaudeChat/`, `ElevenLabsTTS/`, `Permissions/`.

After this step, *all* current behavior still works. Files have moved; their *implementations* are unchanged.

### Step 3 — Extract `Entities/` and `Shared/`

Pull the small shared types out of larger files:

- `VoiceState`, `ScreenCapture`, `ConversationTurn`, `Coordinate` go into `Entities/`.
- `DesignSystem.swift` splits into the 5 files under `Shared/DesignSystem/`.
- `ClickyAnalytics.swift` moves under `Shared/Analytics/`.

This is the highest-risk step (lots of import statements change), but still mechanical.

### Step 4 — Split `CompanionManager`

The big one. Introduce the coordinator types in `State/`, move the relevant methods one-by-one with tests covering each. Tests for this step land in Phase 0 alongside `specs/14-testing-strategy.md`.

### Step 5 — Split `OverlayWindow.swift` and `BuddyDictationManager.swift`

Same pattern as Step 4. Sub-views extracted to their own files; logic extracted to dedicated types.

### Step 6 — Add `Shared/Logging/` and migrate `print` calls

Today every `print("🎙️ …")` call is ad-hoc. Introduce `ClickyLogger` (an `os.Logger` wrapper with categories) and migrate over time. Not blocking for the FSD migration but a logical follow-up.

Total: ~6 PRs, none larger than ~50 file moves. Each PR keeps the build green and the existing UX working. No feature work happens during the migration — Phase 0 in the roadmap freezes feature work for this duration.

## Cross-feature communication patterns

| Pattern | When to use | Example |
|---------|-------------|---------|
| **Entity type** | Two features need to pass a value object | `Features/ClaudeChat/` returns `ConversationTurn` to `Features/VectorMemory/` for indexing |
| **State coordinator** | A flow spans multiple features (push-to-talk → screenshot → Claude → TTS → overlay) | `State/VoicePipelineCoordinator` wires these together |
| **NotificationCenter** | One-way fire-and-forget signaling, no data needed | `clickyDismissPanel` notification posted from anywhere, observed by `Features/MenuBarPanel/` |
| **Combine `@Published`** | A feature exposes state for the panel to observe | `Features/Permissions/PermissionManager.hasAccessibility` → bound to the panel UI |

Direct `import Features.X` from `Features.Y` is **not** a pattern. If you reach for it, the right answer is "promote the shared bit to `Entities/` or `Shared/`."

## Naming conventions

- **Feature folder**: PascalCase, singular noun describing the slice (`VoicePipeline`, not `Voice` or `VoicePipelines`).
- **Files**: PascalCase matching the primary type they define (`PluginRuntime.swift` declares `class PluginRuntime`).
- **Test files**: feature folder + `Tests` (e.g., `Tests/VoicePipeline/PointTagParserTests.swift` — mirroring `Features/VoicePipeline/PointTagParser.swift`).
- **Shared design-system tokens**: `DS.Colors.foo`, `DS.CornerRadius.medium` (no change from today).
- **Coordinator types**: `<Flow>Coordinator` suffix in `State/`.

## What this restructure does *not* do

- **Doesn't introduce Swift Package Manager modules.** Each `Features/X/` is a folder, not a Swift package. Modules add build complexity and a real benefit only appears when the codebase is much larger than 30 files. Revisit when we hit ~100 source files.
- **Doesn't change build settings, Xcode targets, or signing.** It's purely file moves + import rewrites. The single `leanring-buddy` target stays.
- **Doesn't rename the typo-preserved `leanring-buddy` root directory.** That's documented as off-limits in `AGENTS.md` and `adr/0014-keep-leanring-misspelling.md`.

## Open questions

1. **Should `Tests/` live at the same level as `App/` and `Features/`, or as a sibling at the repo root?** Recommendation: at the repo root (`leanring-buddyTests/` already exists there). The folder structure inside `leanring-buddyTests/` mirrors `Features/`.
2. **Should `Entities/` be merged into `Shared/`?** They serve different purposes (domain types vs framework wrappers), but it's a judgment call. Recommendation: keep them separate — the import-rule difference (`Entities` → `Shared` only, `Shared` → nothing) is structural enforcement.
3. **What about file-private extensions?** They stay in the file that owns the primary type. No extension-graveyard files like `String+Extensions.swift`.

## TL;DR

Move from 22 flat files into App / Features / Entities / Shared / State / Resources. Vertical slices per feature, strict layer-import rules, three big files (1026 + 881 + 866 LOC) get surgical decomposition into focused types. Six mechanical PRs, no behavior change. After it lands, every spec in `09`–`12` has a clear home for its new files.
