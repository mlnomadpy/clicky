# Testing Strategy

> **Status**: design doc / RFC. Lands in Phase 0 alongside `specs/13-folder-structure-fsd.md`. Without this, the FSD restructure ships untested and we never get safe refactors.

## State of testing today

`leanring-buddyTests/` contains a single Xcode-generated stub. `leanring-buddyUITests/` contains two launch-test stubs. The release script does not run tests. There is effectively no test suite.

The codebase has been engineered without one — relying on manual Cmd+R + push-to-talk for verification. This worked while there was one developer and one flow. It will not work for the plugin system, Swoosh, three modes, and vector memory.

## Goals

1. **Enable safe refactoring.** The FSD restructure (`specs/13`) moves and splits ~30 files. Without tests, "did it still work?" is a vibe check.
2. **Catch regressions in the primitive set.** Plugins compose primitives; if a primitive breaks, every plugin breaks. Every primitive needs a test.
3. **Make Swoosh's agent loop debuggable.** Agentic systems are easier to debug when each tool has known-good and known-failure tests.
4. **Document behavior through tests.** A passing test is documentation that doesn't rot.
5. **Lower the cost of contribution.** A new contributor (or future Claude Code session) should be able to make a change with confidence.

Non-goals: chasing a coverage number. Coverage targets create incentives to test the wrong things. We target *behavior coverage* — every meaningful path through the primitive set, every spec-required behavior — not line coverage.

## The test pyramid for Clicky

```
                         ▲
                        / \
                       /   \    UI tests          (3–5 total, golden path only)
                      /─────\
                     /       \
                    / Integration\  (~30 — Worker round-trips, multi-feature flows)
                   /─────────────\
                  /               \
                 /     Unit        \  (~150+ — the meat of the suite)
                /───────────────────\
```

- **Unit tests** — fast, pure, run on every save. Test one type at a time with no real network, no real disk, no real audio.
- **Integration tests** — slower, run on PR. Test multiple features wired through `State/` coordinators. May hit `localhost:8787` (a local Worker) or stub URLSession.
- **UI tests** — slowest, run pre-release. Verify the golden path of menu-bar → push-to-talk → response → result. Three or four tests, not more.

## Framework choice

**XCTest** for everything. Reasons:

- Ships with Xcode, no SPM dependency.
- Sup­ports `async`/`await` test methods natively.
- `XCTestExpectation` covers the async-callback cases (CGEvent tap simulation, websocket events).
- `XCUITest` covers the UI tests.

Considered Quick/Nimble — rejected as unnecessary dependency. `XCTAssertEqual` is fine.

For Swift 6 strict concurrency, tests use `@MainActor` where they need to touch the published state objects.

## What we test

### Unit tests (the bulk)

**Per primitive** in the plugin/Swoosh catalogue, at minimum:
- Happy path with valid params.
- Each documented failure mode (scope denied, timeout, malformed input).
- One "unexpected input" test (nil, empty string, huge string).

**Per parser / encoder**:
- `PointTagParser`: every example in the system prompt + several malformed cases. (This is the most critical parser in the system — Claude's full output flows through it.)
- `BuddyPushToTalkShortcut.shortcutTransition`: all five shortcut options against all event types.
- `BuddyPCM16AudioConverter`: round-trip integrity at several sample rates.
- `BuddyWAVFileBuilder`: produces a valid RIFF/WAVE header.
- `PluginManifest` Codable round-trip + JSON Schema validation.
- `parsePointingCoordinates`: regex against the system prompt examples.

**Per coordinate-math function**:
- The screenshot-pixel → display-point → AppKit-global conversion at several display configurations (single monitor 16:10, dual monitor with secondary above, dual monitor with secondary to the right with different scale factors).

**Per state machine**:
- `CompanionVoiceState` transitions driven by `BuddyDictationManager` flag combinations.
- `BuddyNavigationMode` transitions on `detectedElementScreenLocation` changes.

**Per data structure**:
- `ConversationHistory` cap behavior at exactly 10 turns.
- `VectorStore` schema migrations.

### Integration tests

**Worker round-trip**:
- `POST /chat` with a small JPEG + prompt → asserts SSE chunks arrive in order, accumulated text is non-empty.
- `POST /tts` with short text → asserts MP3 bytes come back.
- `POST /transcribe-token` → asserts a token field exists.

These run against a local `wrangler dev` instance launched as part of the test target (see "CI" below). They do not run against the live deployed Worker — that would burn API credits on every PR.

**Plugin runtime**:
- Install a hand-crafted manifest from disk.
- Trigger it via a synthetic transcript.
- Assert each action's side effects (file written, clipboard set, primitive called).

**Swoosh runtime**:
- Drive the agent loop with a stubbed Claude that returns a scripted sequence of `tool_use` blocks.
- Assert the trace recorded, the supervisor's destructive-confirm dialogs fired at the right moments, the budget enforced.

**Permission flows**:
- Simulate `AXIsProcessTrusted = false` → assert the panel renders the Grant Accessibility section.
- Toggle to `true` → assert the global shortcut monitor starts within the polling window.

### UI tests

The minimum to prove the app still launches and responds:

1. **Launch test**: app launches, status item appears in menu bar.
2. **Panel toggle**: clicking the status item shows the panel; clicking again hides it.
3. **Onboarding flow**: from a fresh state, all four Grant buttons → email field → Start button → cursor overlay appears.
4. **Push-to-talk golden path**: with mocked permissions (test target injects a fake `BuddyDictationManager`), trigger a press → release cycle and assert the cursor enters listening → processing → responding states.

UI tests touch real `AppKit` APIs but use injected fakes for the network and audio layers.

## Test directory layout

Mirrors `Features/` exactly:

```
leanring-buddyTests/
├── Features/
│   ├── VoicePipeline/
│   │   ├── BuddyPushToTalkShortcutTests.swift
│   │   ├── BuddyDictationManagerTests.swift
│   │   ├── BuddyPCM16AudioConverterTests.swift
│   │   ├── BuddyWAVFileBuilderTests.swift
│   │   └── Providers/
│   │       ├── AssemblyAIStreamingProviderTests.swift
│   │       └── AppleSpeechProviderTests.swift
│   ├── CursorOverlay/
│   │   ├── BuddyNavigationAnimatorTests.swift
│   │   └── BlueCursorViewSnapshotTests.swift
│   ├── ClaudeChat/
│   │   ├── PointTagParserTests.swift
│   │   ├── PointCoordinateMathTests.swift
│   │   └── ConversationHistoryTests.swift
│   ├── Plugins/
│   │   ├── PluginManifestCodableTests.swift
│   │   ├── PluginManifestSchemaTests.swift
│   │   ├── PluginRuntimeTests.swift
│   │   └── Primitives/
│   │       └── (one test file per primitive)
│   ├── Swoosh/
│   │   ├── SwooshRuntimeTests.swift
│   │   ├── SwooshSupervisorTests.swift
│   │   └── SwooshCompilerTests.swift
│   ├── LocalModels/
│   │   ├── VisionOCRServiceTests.swift
│   │   ├── ModeRouterTests.swift
│   │   └── FoundationModelsRuntimeTests.swift
│   └── VectorMemory/
│       ├── EmbeddingServiceTests.swift
│       ├── VectorStoreTests.swift
│       ├── ConversationMemoryTests.swift
│       └── PluginIntentRouterTests.swift
├── Entities/
│   ├── VoiceStateTests.swift
│   └── CoordinateTests.swift
├── Integration/
│   ├── WorkerChatRoundTripTests.swift
│   ├── WorkerTTSRoundTripTests.swift
│   ├── PluginRuntimeIntegrationTests.swift
│   └── SwooshIntegrationTests.swift
├── TestSupport/                            # shared test helpers
│   ├── StubURLProtocol.swift               # intercepts URLSession for unit tests
│   ├── StubClaudeAPI.swift                 # scripted responses
│   ├── StubScreenCapture.swift             # serves canned PNGs
│   ├── StubAudioBuffer.swift               # canned PCM samples
│   └── SampleManifests.swift               # known-good plugin manifests for tests
└── leanring_buddyTests.swift               # smoke test only, can be deleted

leanring-buddyUITests/                       # unchanged location
├── LaunchTests.swift
├── PanelToggleTests.swift
├── OnboardingFlowTests.swift
└── PushToTalkGoldenPathTests.swift
```

## Test doubles & fakes

We don't use a mocking framework. Two patterns instead:

1. **Protocol injection.** Anywhere production code talks to the world, it goes through a protocol. Tests pass a fake. Example:

```swift
protocol ClaudeAPIClient {
    func analyzeImageStreaming(...) async throws -> (text: String, duration: TimeInterval)
}

final class AIResponseCoordinator {
    let claude: ClaudeAPIClient                          // not `ClaudeAPI` concrete type
    // ...
}

// In tests
let stub = StubClaudeAPI(scriptedResponses: [
    .text("noted. [POINT:300,400:save button]")
])
let coordinator = AIResponseCoordinator(claude: stub, ...)
```

2. **URLProtocol stub** for tests that exercise the full URLSession path (the Worker integration tests, AssemblyAI session tests). `StubURLProtocol` intercepts every request and returns canned data. Registered in `setUpWithError` and torn down in `tearDownWithError` per test.

We avoid:
- **Method swizzling** — too fragile, leaks between tests.
- **Mocking frameworks** (e.g., Cuckoo, Mockingbird) — code-generation overhead, debugging difficulty.
- **Singletons in production code** — they pre-empt the fake-via-protocol pattern.

## Sample data

Canned data lives in `leanring-buddyTests/TestSupport/Fixtures/`:

```
Fixtures/
├── audio/
│   ├── hello_world.wav                     # 2-second "hello world" at 16 kHz PCM16
│   ├── silent.wav                          # silence
│   └── noisy.wav                           # background noise
├── screenshots/
│   ├── xcode_with_button.jpg               # 1280×800 known-coords test
│   ├── figma.jpg
│   └── empty_desktop.jpg
├── claude_responses/
│   ├── valid_with_point.sse                # SSE stream
│   ├── valid_no_point.sse
│   ├── error_429.json
│   └── malformed_tag.txt
├── manifests/
│   ├── valid_voice_phrase.json
│   ├── valid_with_local_fallback.json
│   ├── invalid_unknown_op.json
│   └── invalid_scope.json
└── transcripts/
    ├── short.txt                           # "open save dialog"
    └── long.txt                            # multi-paragraph
```

Each fixture is committed to git. Together they're <20 MB (the WAVs are small).

## The TDD policy

For all work after Phase 0:

**Bug fixes**: write a failing test that exhibits the bug first, then fix. The test goes into the same commit as the fix.

**New primitives** (plugin/Swoosh catalogue): the primitive's tests are written *before* the implementation. At minimum: happy path + each declared failure mode.

**New coordinators**: tests for state transitions are written *before* the coordinator. The published outputs are the test fixtures.

**Refactors**: existing tests must keep passing. If a refactor reveals a behavior with no test, add the test before changing the code.

**UI / view code** (SwiftUI views): exempt unless the view has logic beyond layout (e.g., `BuddyNavigationAnimator` is logic-heavy and gets tests; `PermissionsSection` is layout and doesn't).

We do not write tests for:
- Generated code (Codable synthesis, etc.).
- Constants and design-system tokens.
- Third-party library wrappers when they're 1-line passthroughs.
- AppKit / SwiftUI behavior itself (we trust Apple).

## CI

A new GitHub Action runs on every push to `main` and every PR:

```yaml
name: Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Start local Worker
        run: |
          cd worker
          npm install
          # spawn wrangler dev with stub keys in background
          npx wrangler dev --port 8787 &
          npx wait-on http://localhost:8787
      - name: Run tests
        run: |
          xcodebuild test \
            -project leanring-buddy.xcodeproj \
            -scheme leanring-buddy \
            -destination 'platform=macOS' \
            -resultBundlePath TestResults.xcresult
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: test-results
          path: TestResults.xcresult
```

Important: **CI is allowed to run `xcodebuild`** because it's not the user's Mac — there's no TCC state to invalidate. The "don't run xcodebuild" rule in `AGENTS.md` applies to local dev only.

The integration tests use `localhost:8787` (the local Worker) with stub API keys baked into the Worker config; the stub keys are wired so the Worker returns canned responses instead of hitting real upstreams. This avoids burning API credits in CI.

A second job runs UI tests only on release candidate branches — UI tests take 2–3 minutes each, too slow for every PR.

## Test quality bar

A test is good if:

1. **It says what it tests in its name.** `test_parsePoint_withTrailingScreenNumber_extractsScreen2` not `test_parsePoint_2`.
2. **It tests one thing.** If you'd write "and" in the description, it's two tests.
3. **It fails for one reason.** A test that fails when any of three things break gives you no signal about which one.
4. **It's deterministic.** No flakes, no `sleep()`, no real network outside the Worker integration job.
5. **It's fast.** Unit tests < 50 ms each; the full unit suite < 30 s.
6. **It doesn't test the implementation.** Asserting `someInternalArray.count == 3` is fragile; assert observable behavior instead.

If a test is hard to write, the production code is probably wrong. Easier code is the answer, not a mocking framework.

## Snapshot tests for the design system

Optional but valuable: `pointFreeco/swift-snapshot-testing` (MIT, ~3K stars) for `DesignSystem`-driven view snapshots. Catches accidental color or radius drift. Not blocking for Phase 0 but worth adopting after the FSD restructure.

## Migration plan

Phase 0 doesn't try to write the whole suite. The goal is to land the testing *infrastructure* and a meaningful starter set:

**Step 1 — Infrastructure.**
- New `TestSupport/` folder with stubs and fixtures.
- The CI workflow file.
- The local Worker runner that CI uses.
- A `Makefile`-style script (`scripts/test.sh`) that runs the same command locally.

**Step 2 — Pure logic tests (~30 tests).**
- `PointTagParser`, `PointCoordinateMath`, `BuddyPushToTalkShortcut`, `BuddyPCM16AudioConverter`, `BuddyWAVFileBuilder`, `ConversationHistory`.
- These have zero dependencies — no app state, no AppKit. Easy to test, high signal.

**Step 3 — Coordinator tests (~30 tests).**
- After Step 4 of the FSD migration extracts coordinators from `CompanionManager`.
- One test file per coordinator. Tests state transitions and side-effect ordering.

**Step 4 — Integration tests (~10 tests).**
- Worker round-trips against a locally-running stubbed Worker.
- Plugin manifest validation against the schema.

**Step 5 — Per-primitive tests (ongoing).**
- As primitives land for spec 09 / 10 / 11 / 12, each ships with at least 2 unit tests + 1 integration test.

After Phase 0, the suite has ~70 tests. After Phase 5 (the full roadmap), realistically ~200–300 tests.

## What "test-driven" means here, exactly

It does **not** mean strict red-green-refactor for every line. It means:

1. Before you write code that has a clear input/output contract, write the test.
2. Before you fix a bug, write a test that reproduces it.
3. Before you delete code, check that no test depends on it.
4. Before you merge a PR, the suite must be green.

We allow the rule to bend for exploratory work (spikes, prototypes), but the moment a piece of code is meant to ship, it gets a test.

## Open questions

1. **Should we adopt swift-testing** (Apple's newer test framework introduced at WWDC24) instead of XCTest? Recommendation: stay on XCTest for now. Swift-testing is good but the integration with Xcode and CI tools is still maturing. Revisit in 2027.
2. **Coverage gate in CI?** Recommendation: no minimum threshold gate — that gamifies the wrong thing. Show coverage as a report, but don't fail PRs on it.
3. **Property-based testing for the parsers?** `swift-testing-extensions` or `SwiftCheck`. Recommendation: defer. The fixture-based tests catch the high-value cases.
4. **How do we test the bezier-arc animation?** Snapshot tests of intermediate frames are brittle. Recommendation: test the *math* (`BuddyNavigationAnimator.positionAt(t:)`) with unit tests, leave the rendering to manual QA + UI smoke tests.
5. **Should we test the Cloudflare Worker?** It's TypeScript — different toolchain. Recommendation: add a tiny `vitest` suite in `worker/test/` for the request-shaping logic, run in its own CI job.

## TL;DR

XCTest with `async`/`await`. Mirror the FSD folder structure in `leanring-buddyTests/`. Test by behavior, not by coverage. TDD for new primitives + bug fixes. CI runs against a locally-spawned Worker with stub keys so we never burn credits. Phase 0 ships infrastructure + ~30 pure-logic tests; subsequent phases grow the suite as primitives land. No mocking framework, no coverage gate, no swift-testing rewrite — boring choices that make the suite easy to maintain.
