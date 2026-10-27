# CrystalDiskMark Mac Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS CrystalDiskMark 9.0.3 replica for the default four-test profile, using SwiftUI and a bundled C++ POSIX benchmark engine.

**Architecture:** The SwiftUI app owns the window, menus, settings, volume selection, progress, and result rendering. It launches a bundled C++17 `DiskMarkEngine` with a JSON job list. The engine creates a test file with `F_NOCACHE`, runs warm-up and measured I/O with a capped worker pool, emits newline-delimited JSON events, and cleans up its test directory.

**Tech Stack:** Swift 6.4, SwiftUI, SwiftPM, C++17, POSIX `pread`/`pwrite`, Swift Testing, `clang++`, macOS 27 arm64, ad-hoc signing.

**Spec:** `/Users/xu/Projects/CrystalDiskMarkMac/docs/superpowers/specs/2026-10-27-crystaldiskmark-mac-design.md`

> **Toolchain note (2026-10-28):** XCTest is unavailable with Command Line Tools only. All Swift tests in this plan use Swift Testing (`import Testing`, `@Test`, `#expect`); translate the XCTest-style snippets accordingly. `Package.swift` loads the Command Line Tools `libTestingMacros.dylib` plugin when present, so plain `swift test` works.

## Global Constraints

- Platform: macOS 27.0+, arm64 only. No universal binary, Intel support, App Store, notarization, or auto-update.
- Build toolchain: Command Line Tools only. No `xcodebuild`, no `.xcodeproj`, no external package manager.
- App: `CrystalDiskMark Mac`, bundle id `local.xu.CrystalDiskMarkMac`, version `0.1.0`, non-sandboxed, ad-hoc signed.
- Default profile: four tests `SEQ1M Q8T1`, `SEQ1M Q1T1`, `RND4K Q32T1`, `RND4K Q1T1`; 1 GiB file; 3 measured runs; 5 s per run; 5 s interval; MB/s.
- CDM order: all reads, extra interval between groups, all writes. One full-duration warm-up per operation. Intervals only after the last measured run of an operation. Seven intervals for a default read+write run.
- Worker concurrency cap: 128 total (`queueDepth × threads`). Default profile maximum is 32. NVMe preset Q32T16 is disabled in v1.
- Boot volume target: `~/Library/Caches/CrystalDiskMarkMac`. External volume target: `<volume>/CrystalDiskMarkMac` only when writable. Never silently benchmark a different disk.
- Free-space rule: `testSize + 512 MiB` must be available at selection time and before every test.
- Write path: no `fsync` or `F_FULLFSYNC` after measured writes. Setup `fsync` before read jobs only. Disclose volatile-cache effects.
- Copy/Save Text: CDM-style fixed-width result block, not TSV. Save Image: PNG at 2× scale.
- Menus: native macOS menu bar. Profile, Theme, and Language are visible but disabled/deferred. No custom Windows-style menu strip.
- Branding: working title only; new icon; attribution to CrystalDiskMark and Microsoft DiskSpd; not affiliated with CrystalMark.
- Tests: `swift test`, `Scripts/test-engine.sh`, and `Scripts/build-app.sh` must pass before completion.

## Review Focus

1. **Boot volume and unwritable target:** selecting `/` or an unwritable external volume must produce a clear error and must not benchmark another disk. The boot volume maps to the caches directory.
2. **Cancel, quit, and helper termination:** stopping during warm-up, a measured run, or an interval must leave no `CrystalDiskMarkMac-*` directory; partial results must be marked stale, never presented as fresh.
3. **Free-space boundary:** a request equal to free space, or above `testSize + 512 MiB`, must abort before creating the test file.
4. **Helper crash, missing helper, or malformed NDJSON:** the UI must leave the running state, show an error, and never fabricate a result.
5. **Queue/thread cap:** `queue × threads > 128` must be rejected by settings and by the engine config parser; the default four-test profile must remain exact.

## File Structure

```
CrystalDiskMarkMac/
├── Package.swift
├── Sources/
│   ├── CrystalDiskMarkMac/
│   │   └── CrystalDiskMarkMacApp.swift
│   ├── CrystalDiskMarkMacCore/
│   │   ├── Theme.swift
│   │   ├── Models/
│   │   │   ├── BenchmarkTypes.swift
│   │   │   ├── AppSettings.swift
│   │   │   ├── BenchmarkJob.swift
│   │   │   └── BenchmarkResult.swift
│   │   ├── Services/
│   │   │   ├── SettingsStore.swift
│   │   │   ├── BenchmarkJobBuilder.swift
│   │   │   ├── VolumeCatalog.swift
│   │   │   ├── EngineEvent.swift
│   │   │   ├── EngineRunner.swift
│   │   │   ├── ResultAggregator.swift
│   │   │   ├── ResultFormatter.swift
│   │   │   └── ResultImageRenderer.swift
│   │   ├── ViewModels/
│   │   │   └── BenchmarkViewModel.swift
│   │   └── Views/
│   │       ├── MainView.swift
│   │       ├── ResultRowView.swift
│   │       ├── MeterView.swift
│   │       ├── SettingsView.swift
│   │       └── AboutView.swift
│   ├── DiskMarkEngineCore/
│   │   ├── include/diskmark/config.h
│   │   ├── include/diskmark/test_file.h
│   │   ├── include/diskmark/engine.h
│   │   ├── include/diskmark/events.h
│   │   ├── config.cpp
│   │   ├── json.cpp
│   │   ├── test_file.cpp
│   │   ├── engine.cpp
│   │   └── events.cpp
│   └── DiskMarkEngine/
│       └── main.cpp
├── Tests/
│   ├── CrystalDiskMarkMacCoreTests/
│   │   ├── AppSettingsTests.swift
│   │   ├── BenchmarkJobBuilderTests.swift
│   │   ├── EngineEventTests.swift
│   │   ├── EngineRunnerTests.swift
│   │   ├── BenchmarkViewModelTests.swift
│   │   ├── ResultFormatterTests.swift
│   │   └── ViewRenderTests.swift
│   └── EngineCoreTests/
│       └── main.cpp
├── Scripts/
│   ├── Info.plist
│   ├── build-app.sh
│   ├── test-engine.sh
│   └── make-icon.swift
├── Resources/
│   └── AppIcon.icns
├── docs/superpowers/specs/2026-10-27-crystaldiskmark-mac-design.md
├── docs/superpowers/plans/2026-10-27-crystaldiskmark-mac.md
├── LICENSE
├── NOTICE
├── README.md
└── .gitignore
```

---

### Task 1: Scaffold the package, app bundle, and blank window

**Files:**
- Create: `Package.swift`
- Create: `Sources/CrystalDiskMarkMac/CrystalDiskMarkMacApp.swift`
- Create: `Sources/CrystalDiskMarkMacCore/Theme.swift`
- Create: `Sources/CrystalDiskMarkMacCore/Views/MainView.swift` (placeholder)
- Create: `Scripts/Info.plist`
- Create: `Scripts/build-app.sh`
- Create: `LICENSE`, `NOTICE`, `README.md`, `.gitignore`
- Create: `Tests/CrystalDiskMarkMacCoreTests/ViewRenderTests.swift`

**Interfaces:**
- Produces: `CrystalDiskMarkMacCore` library module; `CrystalDiskMarkMac` executable; `Theme` colors/fonts; `MainView(model:)` placeholder.
- Produces: `Scripts/build-app.sh` creates `build/CrystalDiskMarkMac.app`.

- [ ] **Step 1: Initialize the repo and directories**

Run:

```bash
cd /Users/xu/Projects/CrystalDiskMarkMac
git init
mkdir -p Sources/CrystalDiskMarkMac Sources/CrystalDiskMarkMacCore/Models Sources/CrystalDiskMarkMacCore/Services Sources/CrystalDiskMarkMacCore/ViewModels Sources/CrystalDiskMarkMacCore/Views Tests/CrystalDiskMarkMacCoreTests Tests/EngineCoreTests Scripts Resources
```

- [ ] **Step 2: Write `Package.swift`**

Use `swift-tools-version: 6.0`, `platforms: [.macOS("27.0")]`, `swiftLanguageModes: [.v5]`, and `cxxLanguageStandard: .cxx17`. Targets: `CrystalDiskMarkMacCore` library, `CrystalDiskMarkMac` executable, `CrystalDiskMarkMacCoreTests` test target. Add the C++ targets in Task 4.

- [ ] **Step 3: Write the placeholder app and theme**

`Theme.swift` defines static colors: `window #1B1B1B`, `panel #242424`, `track #333333`, `read #4CD964`, `write #32ADE6`, `primaryText #F5F5F5`, `secondaryText #9A9A9A`, plus `numberFont` (monospaced digits, 32 pt bold).

`MainView` is a fixed `480 × 300` dark rectangle with the text `CrystalDiskMark Mac`.

`CrystalDiskMarkMacApp.swift` uses `@main`, creates a `WindowGroup`, sets `.windowResizability(.contentSize)`, and renders `MainView`.

- [ ] **Step 4: Write `Scripts/Info.plist`**

Include:

```xml
<key>CFBundleIdentifier</key><string>local.xu.CrystalDiskMarkMac</string>
<key>CFBundleName</key><string>CrystalDiskMark Mac</string>
<key>CFBundleExecutable</key><string>CrystalDiskMarkMac</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>27.0</string>
<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSRemovableVolumesUsageDescription</key>
<string>CrystalDiskMark Mac needs access to the selected external volume to create and remove its temporary benchmark file.</string>
<key>NSHumanReadableCopyright</key>
<string>Based on CrystalDiskMark © 2007–2026 hiyohiyo. Not affiliated with CrystalMark.</string>
```

- [ ] **Step 5: Write `Scripts/build-app.sh`**

The script must fail if `uname -m` is not `arm64`, run `swift build -c release --arch arm64`, obtain the bin path with `swift build -c release --arch arm64 --show-bin-path`, create `build/CrystalDiskMarkMac.app/Contents/MacOS` and `Contents/Resources`, copy the executable, copy `Scripts/Info.plist`, copy `Resources/AppIcon.icns` if present, sign nested code before the app, and run `codesign --verify --deep --strict`.

- [ ] **Step 6: Verify the blank app**

Run:

```bash
swift build
Scripts/build-app.sh
open build/CrystalDiskMarkMac.app
```

Expected: a 480 × 300 dark window titled `CrystalDiskMark Mac`.

- [ ] **Step 7: Commit**

```bash
git add .
git commit -m "chore: scaffold CrystalDiskMark Mac app bundle"
```

---

### Task 2: Settings model, defaults, and validation

**Files:**
- Create: `Sources/CrystalDiskMarkMacCore/Models/BenchmarkTypes.swift`
- Create: `Sources/CrystalDiskMarkMacCore/Models/AppSettings.swift`
- Create: `Sources/CrystalDiskMarkMacCore/Services/SettingsStore.swift`
- Create: `Tests/CrystalDiskMarkMacCoreTests/AppSettingsTests.swift`

**Interfaces:**
- Produces: `BenchmarkType` (`.sequential`, `.random`; raw values `sequential`, `random`), `BenchmarkOperation` (`.read`, `.write`; raw values `read`, `write`), `BenchmarkUnit` (`.mbps`, `.gbps`, `.iops`, `.microseconds`), `DataPattern` (`.random`, `.zero`; raw values `random`, `zero`), `BenchmarkMode` (`.readWrite`, `.readOnly`, `.writeOnly`), `BenchmarkProfile` (`.defaultProfile`, `.peak`, `.realWorld`, `.demo`; raw values `default`, `peak`, `realWorld`, `demo`).
- Produces: `TestDefinition` with `id: String`, `type: BenchmarkType`, `blockSizeBytes: UInt64`, `queues: Int`, `threads: Int`, computed `label: String`.
- Produces: `BenchmarkProfile` with computed `displayName` (`Default`, `Peak`, `Real World`, `Demo`).
- Produces: `AppSettings` with `testCount`, `testSizeIndex`, `unit`, `tests: [TestDefinition]`, `measureTime`, `intervalTime`, `dataPattern`, `benchmarkMode`, `profile`, `targetPath`; `static let defaults`; static presets `flashMemory` and `nvme`; `testSizeBytes: UInt64`; `testSizeLabel: String`; `validate() -> [ValidationIssue]`.
- Produces: `SettingsStore` with `load() -> AppSettings` and `save(_:)`.
- Produces: `ValidationIssue` with `field: String`, `message: String`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import CrystalDiskMarkMacCore

final class AppSettingsTests: XCTestCase {
    func testDefaultsMatchCrystalDiskMark() {
        let s = AppSettings.defaults
        XCTAssertEqual(s.testCount, 3)
        XCTAssertEqual(s.testSizeIndex, 6)
        XCTAssertEqual(s.unit, .mbps)
        XCTAssertEqual(s.profile, .defaultProfile)
        XCTAssertEqual(s.tests.map(\.label), ["SEQ1M Q8T1", "SEQ1M Q1T1", "RND4K Q32T1", "RND4K Q1T1"])
        XCTAssertEqual(s.tests.map(\.id), ["seq-1m-q8t1", "seq-1m-q1t1", "rnd-4k-q32t1", "rnd-4k-q1t1"])
        XCTAssertEqual(s.tests.map(\.blockSizeBytes), [1_048_576, 1_048_576, 4_096, 4_096])
        XCTAssertEqual(s.tests.map(\.queues), [8, 1, 32, 1])
        XCTAssertEqual(s.tests.map(\.threads), [1, 1, 1, 1])
        XCTAssertEqual(s.measureTime, 5)
        XCTAssertEqual(s.intervalTime, 5)
    }

    func testTestSizeMapping() {
        XCTAssertEqual(AppSettings.defaults.testSizeBytes, 1_073_741_824)
        var s = AppSettings.defaults
        s.testSizeIndex = 0
        XCTAssertEqual(s.testSizeBytes, 16_777_216)
        XCTAssertEqual(s.testSizeLabel, "16 MiB")
        s.testSizeIndex = 12
        XCTAssertEqual(s.testSizeBytes, 68_719_476_736)
        XCTAssertEqual(s.testSizeLabel, "64 GiB")
    }

    func testValidationRejectsConcurrencyAbove128() {
        var s = AppSettings.defaults
        s.tests[0].queues = 32
        s.tests[0].threads = 5
        XCTAssertTrue(s.validate().contains { $0.field == "threads" })
        s.tests[0].threads = 4
        XCTAssertFalse(s.validate().contains { $0.field == "threads" })
    }

    func testSettingsRoundTrip() {
        let suiteName = "AppSettingsTests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(defaults: suite)
        var s = AppSettings.defaults
        s.unit = .iops
        s.testCount = 7
        s.tests[0].blockSizeBytes = 512
        store.save(s)
        XCTAssertEqual(store.load(), s)
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `swift test --filter AppSettingsTests`
Expected: FAIL because the types do not exist.

- [ ] **Step 3: Implement the types and store**

Use the exact default table from the spec. `testSizeBytes` maps indexes `0...12` to `[16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768, 65536]` MiB. `testSizeLabel` uses `MiB` below 1024 and `GiB` at or above 1024.

`validate()` checks:

- `testCount` in `1...9`
- `testSizeIndex` in `0...12`
- `measureTime` in `[1,2,3,4,5,6,7,8,9,10,20,30,60]`
- `intervalTime` in `[0,1,3,5,10,30,60,180,300,600]`
- each test: `blockSizeBytes` in `[512, 1024, 2048, 4096, 8192, 16384, 32768, 65536, 131072, 262144, 524288, 1048576, 2097152, 4194304, 8388608]`, `queues` in `1...32`, `threads` in `1...16`, `queues * threads <= 128`
- labels: sequential `SEQ{size}M` for MiB blocks and `SEQ{size}K` for KiB; random `RND{size}M`/`RND{size}K`; append ` Q{q}T{t}`. 512 B is `SEQ512B`/`RND512B`.
- default test IDs: `seq-1m-q8t1`, `seq-1m-q1t1`, `rnd-4k-q32t1`, `rnd-4k-q1t1`.
- `targetPath` defaults to `~/Library/Caches/CrystalDiskMarkMac` (boot volume).

`SettingsStore` writes the scalar keys `TestCount`, `TestSize`, `TestUnit`, `MeasureTime`, `IntervalTime`, `TestData`, `Benchmark`, `Profile`, `TargetPath`, and per-test keys `BenchType0...3`, `BenchSize0...3`, `BenchQueues0...3`, `BenchThreads0...3`. `BenchSize0...3` stores KiB as a `Double`, so 512 B is `0.5`.

- [ ] **Step 4: Run tests to verify pass**

Run: `swift test --filter AppSettingsTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CrystalDiskMarkMacCore/Models Sources/CrystalDiskMarkMacCore/Services/SettingsStore.swift Tests/CrystalDiskMarkMacCoreTests/AppSettingsTests.swift
git commit -m "feat: add CrystalDiskMark settings model"
```

---

### Task 3: Build the CDM job list

**Files:**
- Create: `Sources/CrystalDiskMarkMacCore/Models/BenchmarkJob.swift`
- Create: `Sources/CrystalDiskMarkMacCore/Services/BenchmarkJobBuilder.swift`
- Create: `Tests/CrystalDiskMarkMacCoreTests/BenchmarkJobBuilderTests.swift`

**Interfaces:**
- Produces: `BenchmarkJob` with `id`, `label`, `operation: BenchmarkOperation`, `run`, `warmup`, `mode: BenchmarkType`, `blockSizeBytes`, `queueDepth`, `threads`, `durationSeconds`, `intervalAfterMs`; all `Codable` and `Equatable`.
- Produces: `EngineConfig` with `target`, `fileSizeBytes`, `dataPattern`, `jobs`; `Codable` and `Equatable`.
- Produces: `BenchmarkJobBuilder.allTests(settings:target:) -> EngineConfig`
- Produces: `BenchmarkJobBuilder.singleTest(settings:testIndex:target:) -> EngineConfig`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import CrystalDiskMarkMacCore

final class BenchmarkJobBuilderTests: XCTestCase {
    let target = URL(fileURLWithPath: "/tmp/cdm-test")

    func testDefaultAllTestsHas32JobsAndCDMOrder() {
        let c = BenchmarkJobBuilder.allTests(settings: .defaults, target: target)
        XCTAssertEqual(c.jobs.count, 32)
        XCTAssertEqual(c.jobs.prefix(16).map(\.operation), Array(repeating: .read, count: 16))
        XCTAssertEqual(c.jobs.suffix(16).map(\.operation), Array(repeating: .write, count: 16))
        XCTAssertEqual(c.jobs.prefix(16).map(\.id).first, "seq-1m-q8t1-read")
        XCTAssertEqual(c.jobs.suffix(16).map(\.id).last, "rnd-4k-q1t1-write")
    }

    func testIntervalsOnlyAfterLastMeasuredRun() {
        let c = BenchmarkJobBuilder.allTests(settings: .defaults, target: target)
        let intervalJobs = c.jobs.filter { $0.intervalAfterMs > 0 }
        XCTAssertEqual(intervalJobs.count, 7)
        XCTAssertTrue(intervalJobs.allSatisfy { !$0.warmup && $0.run == 3 })
    }

    func testReadOnlyHasThreeIntervals() {
        var s = AppSettings.defaults
        s.benchmarkMode = .readOnly
        let c = BenchmarkJobBuilder.allTests(settings: s, target: target)
        XCTAssertEqual(c.jobs.count, 16)
        XCTAssertEqual(c.jobs.filter { $0.intervalAfterMs > 0 }.count, 3)
    }

    func testSingleTestRunsReadThenWrite() {
        let c = BenchmarkJobBuilder.singleTest(settings: .defaults, testIndex: 0, target: target)
        XCTAssertEqual(c.jobs.count, 8)
        XCTAssertEqual(c.jobs.prefix(4).map(\.operation), Array(repeating: .read, count: 4))
        XCTAssertEqual(c.jobs.suffix(4).map(\.operation), Array(repeating: .write, count: 4))
        XCTAssertEqual(c.jobs.filter { $0.intervalAfterMs > 0 }.count, 1)
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `swift test --filter BenchmarkJobBuilderTests`
Expected: FAIL because the types do not exist.

- [ ] **Step 3: Implement the builder**

`allTests` builds read jobs for tests `0...3`, then write jobs for tests `0...3`. Each operation has run `0` as warm-up and runs `1...testCount` as measured. Set `intervalAfterMs` only on the last measured run of:

- read tests 0, 1, 2
- read test 3 only when the mode is `.readWrite` (the inter-group interval)
- write tests 0, 1, 2

`singleTest` builds read jobs then write jobs for one test; the interval goes on the last measured read run when both operations exist.

- [ ] **Step 4: Run tests to verify pass**

Run: `swift test --filter BenchmarkJobBuilderTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CrystalDiskMarkMacCore/Models/BenchmarkJob.swift Sources/CrystalDiskMarkMacCore/Services/BenchmarkJobBuilder.swift Tests/CrystalDiskMarkMacCoreTests/BenchmarkJobBuilderTests.swift
git commit -m "feat: build CDM-ordered benchmark jobs"
```

---

### Task 4: C++ config model and strict JSON parser

**Files:**
- Create: `Sources/DiskMarkEngineCore/include/diskmark/config.h`
- Create: `Sources/DiskMarkEngineCore/config.cpp`
- Create: `Sources/DiskMarkEngineCore/json.cpp`
- Create: `Sources/DiskMarkEngine/main.cpp` (minimal `--config` entry)
- Create: `Tests/EngineCoreTests/main.cpp`
- Create: `Scripts/test-engine.sh`
- Modify: `Package.swift` add `DiskMarkEngineCore` and `DiskMarkEngine` targets.

**Interfaces:**
- Produces: `diskmark::Job` with the same fields as `BenchmarkJob`.
- Produces: `diskmark::Config` with `target`, `fileSizeBytes`, `dataPattern`, `jobs`.
- Produces: `diskmark::parseConfig(std::string_view) -> Config`, throwing `diskmark::ConfigError` with `code` and `message`.
- Produces: `Scripts/test-engine.sh` compiles core + tests with `clang++ -std=c++17 -I Sources/DiskMarkEngineCore/include -pthread`.

- [ ] **Step 1: Write the failing C++ tests**

In `Tests/EngineCoreTests/main.cpp`, use `assert` and a `expectThrows` helper. Cover:

- the full sample config parses one job with exact values;
- multiple jobs preserve order;
- missing `target`, empty `jobs`, non-positive `fileSizeBytes`, unknown `dataPattern`, `blockSizeBytes == 0`, `durationSeconds == 0`, `queueDepth == 0`, `threads == 0`, `queueDepth * threads > 128`, malformed JSON, and trailing garbage all throw;
- `dataPattern` accepts `random` and `zero` only.

Example assertion:

```cpp
auto cfg = diskmark::parseConfig(R"({
  "target":"/tmp/x","fileSizeBytes":1073741824,"dataPattern":"random",
  "jobs":[{"id":"a","label":"A","operation":"read","run":0,"warmup":true,
  "mode":"sequential","blockSizeBytes":1048576,"queueDepth":8,"threads":1,
  "durationSeconds":5,"intervalAfterMs":5000}]
})");
assert(cfg.jobs.size() == 1);
assert(cfg.jobs[0].queueDepth == 8);
```

- [ ] **Step 2: Run tests to verify failure**

Run: `Scripts/test-engine.sh`
Expected: FAIL because the parser and core types do not exist.

- [ ] **Step 3: Implement the config parser**

Write a small strict recursive-descent JSON parser for objects, arrays, strings, numbers, booleans, and null. It only needs to accept the documented schema; reject unknown top-level/job keys, wrong types, missing required fields, negative numbers, and trailing bytes. Write JSON escaping helpers for later event output.

- [ ] **Step 4: Add the C++ targets to `Package.swift`**

Add a library target `DiskMarkEngineCore` with `publicHeadersPath: "include"` and an executable target `DiskMarkEngine` depending on it. Ensure `swift build` builds both. Modify `Scripts/build-app.sh` to copy `DiskMarkEngine` into `Contents/MacOS` when it exists.

- [ ] **Step 5: Run tests to verify pass**

Run: `Scripts/test-engine.sh`
Expected: PASS.

Run: `swift build`
Expected: PASS; `DiskMarkEngine` exists in the build products.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/DiskMarkEngineCore Sources/DiskMarkEngine/main.cpp Tests/EngineCoreTests/main.cpp Scripts/test-engine.sh
git commit -m "feat: add strict engine config parser"
```

---

### Task 5: Test-file lifecycle and stale cleanup

**Files:**
- Create: `Sources/DiskMarkEngineCore/include/diskmark/test_file.h`
- Create: `Sources/DiskMarkEngineCore/test_file.cpp`
- Modify: `Tests/EngineCoreTests/main.cpp`

**Interfaces:**
- Produces: `diskmark::TestFile` with `TestFile(const Config&)`, `create()`, `fill()`, `fsyncForReads()`, `cleanup()`, `path()`, `size()`.
- Produces: `diskmark::cleanupStaleSessions(const std::string& target, int olderThanHours = 24)`.
- Produces: `diskmark::EngineError` with `code`, `message`.

- [ ] **Step 1: Write the failing tests**

Cover:

- `create()` makes `CrystalDiskMarkMac-XXXXXXXX/` with `.crystaldiskmark-mac-session` and `test.tmp`;
- `size()` equals `fileSizeBytes`;
- `cleanup()` removes both file and directory, and is idempotent;
- a target path that is a file throws `target_not_writable`;
- a request for `UINT64_MAX / 2` bytes throws `insufficient_space`;
- stale cleanup removes an old marked directory but leaves an unmarked directory and a recent marked directory.

Use a temp directory created with `mkdtemp`; set an old mtime with `utimensat`.

- [ ] **Step 2: Run tests to verify failure**

Run: `Scripts/test-engine.sh`
Expected: FAIL because `TestFile` does not exist.

- [ ] **Step 3: Implement the lifecycle**

Use `open(O_CREAT|O_EXCL|O_RDWR, 0600)`, `fcntl(F_NOCACHE)`, `ftruncate`, and a 1 MiB pseudo-random buffer for filling. Write the marker with a UUID and PID. Check `statvfs` before creating; use an overflow-safe comparison: `available >= fileSizeBytes && available - fileSizeBytes >= 512 MiB`. Cleanup removes only the current directory. Stale cleanup removes only directories whose marker file exists and whose mtime is older than the threshold.

- [ ] **Step 4: Run tests to verify pass**

Run: `Scripts/test-engine.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/DiskMarkEngineCore/include/diskmark/test_file.h Sources/DiskMarkEngineCore/test_file.cpp Tests/EngineCoreTests/main.cpp
git commit -m "feat: add benchmark test-file lifecycle"
```

---

### Task 6: Worker pool, POSIX I/O, and result math

**Files:**
- Create: `Sources/DiskMarkEngineCore/include/diskmark/engine.h`
- Create: `Sources/DiskMarkEngineCore/engine.cpp`
- Modify: `Tests/EngineCoreTests/main.cpp`

**Interfaces:**
- Produces: `using EventSink = std::function<void(const std::string&)>;` in `engine.h`.
- Produces: `diskmark::JobResult` with `testId`, `label`, `operation`, `run`, `warmup`, `bytes`, `seconds`, `mbps`, `iops`, `latencyUs`, `cancelled`.
- Produces: `diskmark::computeResult(uint64_t bytes, double seconds, uint64_t blockSize, const std::vector<double>& latencies) -> JobResult`.
- Produces: `diskmark::runJob(TestFile&, const Job&, std::atomic<bool>& cancel) -> JobResult`.
- Produces: `diskmark::effectiveWorkers(int queueDepth, int threads) -> int` capped at 128.

- [ ] **Step 1: Write the failing tests**

Cover:

- `computeResult(1_000_000, 1.0, 4096, {100.0, 200.0})` gives `mbps == 1.0`, `iops == 244.140625`, `latencyUs == 150.0` within `1e-9`;
- `effectiveWorkers(32, 16) == 128`, `effectiveWorkers(8, 1) == 8`;
- a 64 MiB test file with a 1 s sequential read Q1T1 returns positive `bytes`, `mbps`, `iops`, and non-negative latency;
- a random read Q4T1 returns positive results;
- a sequential write Q1T1 returns positive results;
- setting `cancel` after 100 ms returns `cancelled == true` within 2 s;
- the offset generator never returns an offset outside `[0, fileSize - blockSize]`; test it directly with a small file and many iterations.

- [ ] **Step 2: Run tests to verify failure**

Run: `Scripts/test-engine.sh`
Expected: FAIL because `runJob` does not exist.

- [ ] **Step 3: Implement the worker pool**

Use `std::thread`, `std::atomic`, `std::condition_variable`, and a barrier start. Each worker allocates a page-aligned block buffer with `posix_memalign`. Sequential mode uses a shared atomic block cursor; random mode uses a per-worker `std::mt19937_64` seeded from `std::random_device`. Use `pread`/`pwrite`; retry on `EINTR`; stop on `cancel`. Measure each syscall with `clock_gettime(CLOCK_MONOTONIC)`.

`computeResult` uses decimal MB/s, IOPS = MB/s × 1,000,000 / block size, and mean latency.

- [ ] **Step 4: Run tests to verify pass**

Run: `Scripts/test-engine.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/DiskMarkEngineCore/include/diskmark/engine.h Sources/DiskMarkEngineCore/engine.cpp Tests/EngineCoreTests/main.cpp
git commit -m "feat: add POSIX benchmark worker pool"
```

---

### Task 7: Engine session, NDJSON events, intervals, and CLI

**Files:**
- Create: `Sources/DiskMarkEngineCore/include/diskmark/events.h`
- Create: `Sources/DiskMarkEngineCore/events.cpp`
- Modify: `Sources/DiskMarkEngineCore/include/diskmark/engine.h` (add `runSession`)
- Modify: `Sources/DiskMarkEngineCore/engine.cpp`
- Modify: `Sources/DiskMarkEngine/main.cpp`
- Modify: `Tests/EngineCoreTests/main.cpp`

**Interfaces:**
- Consumes: `diskmark::EventSink` from `engine.h`.
- Produces: `diskmark::runSession(const Config&, EventSink) -> int`.
- Produces: `diskmark::eventJson(...)` helpers for `phase`, `run`, `progress`, `interval`, `result`, `done`, `error`.
- Produces CLI: `DiskMarkEngine --config <path>`; `--help`; exit `0` success, `2` invalid config, `3` engine failure.

- [ ] **Step 1: Write the failing tests**

Cover:

- a session with one 1 s read job emits `phase`, `run`, `progress`, `result`, and `done` in that order; the `result` object includes `test`, `operation`, `run`, `warmup`, `mbps`, `iops`, and `latencyUs`;
- `intervalAfterMs: 1000` emits at least one `interval` event and still ends with `done`;
- a cancelled session emits `{"event":"error","code":"cancelled","message":"Cancelled"}`, exits `130`, and leaves no test directory;
- an invalid config file exits `2` and emits an `error` event;
- JSON event strings parse as objects and contain the required keys.

- [ ] **Step 2: Run tests to verify failure**

Run: `Scripts/test-engine.sh`
Expected: FAIL because `runSession` does not exist.

- [ ] **Step 3: Implement the session loop**

`runSession` cleans stale sessions, creates the test file, fills it, fsyncs before the first read job, then iterates jobs. Emit `run`, start a progress reporter every 250 ms, run the job, emit `result`, then sleep the interval in one-second steps while emitting `interval`. On completion, clean up and emit `done`. On error, clean up and emit `error`.

Install `SIGINT`/`SIGTERM` handlers that set an atomic cancel flag. On cancellation, emit the `cancelled` error, clean up, and return exit code `130`. `main.cpp` parses `--config`, reads the file, calls `parseConfig`, and maps exceptions to exit code `2` or `3`.

- [ ] **Step 4: Run tests to verify pass**

Run: `Scripts/test-engine.sh`
Expected: PASS.

Run a manual smoke test:

```bash
.build/debug/DiskMarkEngine --config /tmp/cdm-smoke.json
```

Expected: NDJSON events, a created and removed test directory, exit `0`.

- [ ] **Step 5: Commit**

```bash
git add Sources/DiskMarkEngineCore/include/diskmark/events.h Sources/DiskMarkEngineCore/events.cpp Sources/DiskMarkEngineCore/include/diskmark/engine.h Sources/DiskMarkEngineCore/engine.cpp Sources/DiskMarkEngine/main.cpp Tests/EngineCoreTests/main.cpp
git commit -m "feat: add engine session and NDJSON events"
```

---

### Task 8: Swift engine event decoding and process runner

**Files:**
- Create: `Sources/CrystalDiskMarkMacCore/Services/EngineEvent.swift`
- Create: `Sources/CrystalDiskMarkMacCore/Services/EngineRunner.swift`
- Create: `Tests/CrystalDiskMarkMacCoreTests/EngineEventTests.swift`
- Create: `Tests/CrystalDiskMarkMacCoreTests/EngineRunnerTests.swift`

**Interfaces:**
- Produces: `EngineEvent` cases `phase`, `run`, `progress`, `interval`, `result`, `done`, `error`.
- Produces: `EngineEventDecoder.decode(_ line: String) throws -> EngineEvent`.
- Produces: `protocol EngineRunning: AnyObject` with `start(config:onEvent:onExit:) throws` and `cancel()`; `onExit` receives `(Int32, String)` where the string is the stderr tail.
- Produces: `EngineRunner` with `init(engineURL: URL)`, `static func defaultEngineURL() -> URL`.
- Produces: `LineBuffer` that appends `Data` and returns complete lines.

- [ ] **Step 1: Write the failing tests**

Cover:

- decoding each event type from a literal JSON line;
- malformed JSON, missing `event`, and unknown event names throw;
- `LineBuffer` handles partial lines across appends;
- `EngineRunner` runs a temporary executable shell script that prints two events and exits `0`, and the callbacks receive both events and the exit code;
- a fake engine that prints a malformed line causes a `.error` event and termination;
- a fake engine that writes to stderr and exits `1` delivers the stderr tail to `onExit`;
- a missing engine path throws;
- `cancel()` terminates a sleeping fake engine.

- [ ] **Step 2: Run tests to verify failure**

Run: `swift test --filter Engine`
Expected: FAIL because the event types and runner do not exist.

- [ ] **Step 3: Implement decoding and the process runner**

Use `JSONSerialization` to read the event dictionary and switch on `event`. `EngineRunner` writes the `EngineConfig` JSON to a temp file, launches `Process` with `--config`, reads stdout with `readabilityHandler` + `LineBuffer`, captures stderr into a bounded tail, dispatches events to the main queue, and dispatches `onExit(code, stderrTail)` from `terminationHandler`. A malformed line emits `.error(code: "malformed_event", ...)` and terminates the helper. `cancel()` sends `terminate()`, waits up to 2 seconds, then `kill(pid, SIGKILL)`.

`defaultEngineURL()` checks `DISKMARK_ENGINE_PATH` first, then `Bundle.main.url(forAuxiliaryExecutable: "DiskMarkEngine")`, then `Contents/MacOS/DiskMarkEngine`.

- [ ] **Step 4: Run tests to verify pass**

Run: `swift test --filter Engine`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CrystalDiskMarkMacCore/Services/EngineEvent.swift Sources/CrystalDiskMarkMacCore/Services/EngineRunner.swift Tests/CrystalDiskMarkMacCoreTests/EngineEventTests.swift Tests/CrystalDiskMarkMacCoreTests/EngineRunnerTests.swift
git commit -m "feat: add Swift engine process runner"
```

---

### Task 9: Result aggregation and benchmark view model

**Files:**
- Create: `Sources/CrystalDiskMarkMacCore/Models/BenchmarkResult.swift`
- Create: `Sources/CrystalDiskMarkMacCore/Services/ResultAggregator.swift`
- Create: `Sources/CrystalDiskMarkMacCore/ViewModels/BenchmarkViewModel.swift`
- Create: `Tests/CrystalDiskMarkMacCoreTests/BenchmarkViewModelTests.swift`

**Interfaces:**
- Produces: `BenchmarkResult` with `testID`, `operation`, `mbps`, `iops`, `latencyUs`, `isStale`, computed `id`.
- Produces: `ResultAggregator` with `ingest(_ event:)`, `markStale()`, `results`.
- Produces: `BenchmarkState` `.idle`, `.preparing`, `.running`, `.interval`, `.finished`, `.failed(String)`.
- Produces: `BenchmarkViewModel` `@MainActor` with published `settings`, `results`, `state`, `statusText`, `progress`, `selectedVolume`, `showSettings`, `showAbout`, `errorMessage`; methods `runAll()`, `run(testIndex:)`, `stop()`, `saveSettings(_:)`.
- Produces: `static var preview: BenchmarkViewModel` with default settings and sample results for render tests.
- Consumes: `BenchmarkJobBuilder`, `EngineRunning`, `VolumeCatalog`, `SettingsStore`.

- [ ] **Step 1: Write the failing tests**

Use a `MockEngineRunner` that stores `onEvent`/`onExit` callbacks and records the last config. Cover:

- warm-up results are ignored; measured results 100, 120, 110 MB/s keep 120 and the minimum latency;
- `.phase` sets `.preparing`; `.run` sets `.running`; `.interval` sets `.interval`; `.done` sets `.finished`;
- `.error` sets `.failed` and exposes the message;
- `stop()` calls `cancel`, sets `.idle`, and marks existing results stale;
- `runAll()` builds a config with 32 jobs and the selected target;
- `run(testIndex: 2)` builds a config with 8 jobs for `RND4K Q32T1`.

- [ ] **Step 2: Run tests to verify failure**

Run: `swift test --filter BenchmarkViewModelTests`
Expected: FAIL because the view model and aggregator do not exist.

- [ ] **Step 3: Implement aggregation and the state machine**

`ResultAggregator.ingest` ignores `result` events with `warmup == true`. For measured results, keep the maximum `mbps`/`iops` and the minimum `latencyUs` per `testID + operation`. `markStale()` sets `isStale` on all results.

`BenchmarkViewModel` resolves the target with `VolumeCatalog.resolveTarget(for:)` or `settings.targetPath`; inserts stale cleanup? The engine owns stale cleanup. Build the config, call `engineRunner.start`, and handle events on the main actor. On non-zero exit without a prior `.done`, set `.failed`. Ignore engine events received after `stop()` so a cancelled helper cannot flip the state back to `.failed`. Observe `NSApplication.willTerminateNotification` and call `stop()`.

- [ ] **Step 4: Run tests to verify pass**

Run: `swift test --filter BenchmarkViewModelTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CrystalDiskMarkMacCore/Models/BenchmarkResult.swift Sources/CrystalDiskMarkMacCore/Services/ResultAggregator.swift Sources/CrystalDiskMarkMacCore/ViewModels/BenchmarkViewModel.swift Tests/CrystalDiskMarkMacCoreTests/BenchmarkViewModelTests.swift
git commit -m "feat: add benchmark state machine"
```

---

### Task 10: Main window, result rows, meters, and menus

**Files:**
- Modify: `Sources/CrystalDiskMarkMacCore/Views/MainView.swift`
- Create: `Sources/CrystalDiskMarkMacCore/Views/ResultRowView.swift`
- Create: `Sources/CrystalDiskMarkMacCore/Views/MeterView.swift`
- Modify: `Sources/CrystalDiskMarkMacCore/Theme.swift`
- Modify: `Sources/CrystalDiskMarkMac/CrystalDiskMarkMacApp.swift`
- Modify: `Tests/CrystalDiskMarkMacCoreTests/ViewRenderTests.swift`

**Interfaces:**
- Produces: `MainView(model: BenchmarkViewModel)` fixed at 480 × 300.
- Produces: `ResultRowView(test:read:write:unit:action:)`.
- Produces: `MeterView(value:unitLabel:ratio:accent:)`.
- Produces: `AppCommands(model:)` with File, Settings, Profile, Test Mode, Benchmark, Theme, Language, Help menus.

- [ ] **Step 1: Write the failing render test**

```swift
@MainActor
func testMainViewRendersAtExpectedSize() {
    let model = BenchmarkViewModel.preview
    let renderer = ImageRenderer(content: MainView(model: model).frame(width: 480, height: 300))
    renderer.proposedSize = .init(width: 480, height: 300)
    let image = renderer.nsImage
    XCTAssertNotNil(image)
    XCTAssertEqual(image?.size, CGSize(width: 480, height: 300))
    XCTAssertFalse(image?.tiffRepresentation?.isEmpty ?? true)
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `swift test --filter ViewRenderTests`
Expected: FAIL because the real `MainView` and preview model do not exist.

- [ ] **Step 3: Implement the static UI**

Build the 480 × 300 layout:

- top row: test count, test size, volume, unit pickers;
- four `ResultRowView`s with labels, read panel, write panel, and 32 pt monospaced numbers;
- bottom status text, progress bar, and Stop button;
- dark palette and logarithmic meters from the spec;
- `.help(...)` tooltips with MB/s, GB/s, IOPS, µs, block size, queue, threads.

Use the native macOS menu bar via `Commands`. Profile/Theme/Language items are disabled in v1. Settings and About set `model.showSettings`/`model.showAbout`.

- [ ] **Step 4: Run test to verify pass**

Run: `swift test --filter ViewRenderTests`
Expected: PASS.

Launch the app and take a screenshot:

```bash
Scripts/build-app.sh
open build/CrystalDiskMarkMac.app
screencapture -x /tmp/cdm-main.png
```

Expected: four rows, read/write columns, dark theme, 480 × 300 content.

- [ ] **Step 5: Commit**

```bash
git add Sources/CrystalDiskMarkMacCore/Views Sources/CrystalDiskMarkMacCore/Theme.swift Sources/CrystalDiskMarkMac/CrystalDiskMarkMacApp.swift Tests/CrystalDiskMarkMacCoreTests/ViewRenderTests.swift
git commit -m "feat: add CDM-style main window"
```

---

### Task 11: Volume picker, settings sheet, and validation UI

**Files:**
- Create: `Sources/CrystalDiskMarkMacCore/Services/VolumeCatalog.swift`
- Create: `Sources/CrystalDiskMarkMacCore/Views/SettingsView.swift`
- Modify: `Sources/CrystalDiskMarkMacCore/Views/MainView.swift`
- Modify: `Sources/CrystalDiskMarkMacCore/ViewModels/BenchmarkViewModel.swift`
- Create: `Tests/CrystalDiskMarkMacCoreTests/VolumeCatalogTests.swift`
- Modify: `Tests/CrystalDiskMarkMacCoreTests/AppSettingsTests.swift`

**Interfaces:**
- Produces: `VolumeInfo` with `url`, `name`, `freeBytes`, `totalBytes`, `isBoot`; `Identifiable`.
- Produces: `VolumeCatalog` with `mountedVolumes()`, `resolveTarget(for:)`, `freeBytes(at:)`, `chooseFolder()`.
- Produces: `VolumeError` cases `notWritable(URL)`, `notEnoughSpace(required: UInt64, available: UInt64)`.
- Produces: `SettingsView(settings:onSave:onCancel:)`.

- [ ] **Step 1: Write the failing tests**

Cover:

- a fake boot volume resolves to the injected caches directory `/CrystalDiskMarkMac`;
- a writable temp directory resolves to `<temp>/CrystalDiskMarkMac`;
- a read-only temp directory throws `notWritable`;
- `freeBytes` returns a positive value for a temp directory;
- a settings request with `testSizeBytes + 512 MiB > freeBytes` throws `notEnoughSpace`;
- `AppSettings.flashMemory` uses 1 s measure and 30 s interval;
- `AppSettings.defaults` and `flashMemory` validate; `nvme` is defined but marked unavailable.

- [ ] **Step 2: Run tests to verify failure**

Run: `swift test --filter Volume`
Expected: FAIL because `VolumeCatalog` does not exist.

- [ ] **Step 3: Implement the catalog and settings UI**

`mountedVolumes()` uses `FileManager.mountedVolumeURLs` with `.volumeNameKey`, `.volumeTotalCapacityKey`, `.volumeAvailableCapacityForImportantUsageKey`, filters to local volumes, and marks the root filesystem as boot.

`resolveTarget` maps boot to `cachesDirectory/CrystalDiskMarkMac`; external volumes to `<volume>/CrystalDiskMarkMac`; creates the directory; checks `isWritableFile`; throws otherwise. It checks `freeBytes` and throws `notEnoughSpace` when required space is unavailable.

`SettingsView` is a sheet with four test rows (Type, Block Size, Queues, Threads), Measure Time, Interval Time, Data Pattern, presets Default/Flash Memory, OK/Cancel, and inline validation errors.

- [ ] **Step 4: Run tests to verify pass**

Run: `swift test --filter Volume`
Expected: PASS.

Manual check: open Settings, change a value, save, relaunch, confirm it persists. Select the external Intel SSD and confirm the target is `<volume>/CrystalDiskMarkMac`.

- [ ] **Step 5: Commit**

```bash
git add Sources/CrystalDiskMarkMacCore/Services/VolumeCatalog.swift Sources/CrystalDiskMarkMacCore/Views/SettingsView.swift Sources/CrystalDiskMarkMacCore/Views/MainView.swift Sources/CrystalDiskMarkMacCore/ViewModels/BenchmarkViewModel.swift Tests/CrystalDiskMarkMacCoreTests/VolumeCatalogTests.swift Tests/CrystalDiskMarkMacCoreTests/AppSettingsTests.swift
git commit -m "feat: add volume picker and settings sheet"
```

---

### Task 12: Wire the engine, progress, results, and Stop

**Files:**
- Modify: `Sources/CrystalDiskMarkMacCore/ViewModels/BenchmarkViewModel.swift`
- Modify: `Sources/CrystalDiskMarkMacCore/Views/MainView.swift`
- Modify: `Sources/CrystalDiskMarkMac/CrystalDiskMarkMacApp.swift`
- Create: `Tests/CrystalDiskMarkMacCoreTests/BenchmarkIntegrationTests.swift`

**Interfaces:**
- Consumes: `BenchmarkJobBuilder`, `EngineRunner`, `ResultAggregator`, `VolumeCatalog`.
- Produces: working All and per-row buttons; Stop; live progress; stale-on-cancel behavior.

- [ ] **Step 1: Write the failing integration tests**

Use the fake engine from Task 8 or a `MockEngineRunner` that emits a scripted event sequence. Cover:

- All emits 32 jobs and four read + four write results;
- per-row test emits 8 jobs and updates only that row;
- Stop during a run cancels the engine and marks results stale;
- a helper exit without `done` sets `.failed`, includes the stderr tail in the message, and keeps completed results;
- a malformed event line sets `.failed` and does not crash.

- [ ] **Step 2: Run tests to verify failure**

Run: `swift test --filter BenchmarkIntegrationTests`
Expected: FAIL because the wiring is incomplete.

- [ ] **Step 3: Wire the view model and buttons**

`runAll()` and `run(testIndex:)` build the config, set `.preparing`, start the engine, and update state from events. The All button calls `runAll`; each row button calls `run(testIndex:)`. The Stop button calls `stop()`. Disable controls while running. Show the current test label and run number in the status line. Keep completed results when a later test fails.

- [ ] **Step 4: Run tests to verify pass**

Run: `swift test --filter BenchmarkIntegrationTests`
Expected: PASS.

Manual smoke test with a 16 MiB file and 1 s measure time on a temp folder. Expected: eight results and no leftover `CrystalDiskMarkMac-*` directory.

- [ ] **Step 5: Commit**

```bash
git add Sources/CrystalDiskMarkMacCore/ViewModels/BenchmarkViewModel.swift Sources/CrystalDiskMarkMacCore/Views/MainView.swift Sources/CrystalDiskMarkMac/CrystalDiskMarkMacApp.swift Tests/CrystalDiskMarkMacCoreTests/BenchmarkIntegrationTests.swift
git commit -m "feat: wire benchmark engine to the UI"
```

---

### Task 13: Result formatting, copy/save, image export, and About

**Files:**
- Create: `Sources/CrystalDiskMarkMacCore/Services/ResultFormatter.swift`
- Create: `Sources/CrystalDiskMarkMacCore/Services/ResultImageRenderer.swift`
- Create: `Sources/CrystalDiskMarkMacCore/Views/AboutView.swift`
- Modify: `Sources/CrystalDiskMarkMacCore/ViewModels/BenchmarkViewModel.swift`
- Modify: `Sources/CrystalDiskMarkMac/CrystalDiskMarkMacApp.swift`
- Create: `Tests/CrystalDiskMarkMacCoreTests/ResultFormatterTests.swift`

**Interfaces:**
- Produces: `ResultFormatter.valueString(result:unit:blockSizeBytes:)`.
- Produces: `ResultFormatter.meterRatio(result:unit:)`.
- Produces: `ResultFormatter.textBlock(settings:results:date:osVersion:volumeName:) -> String`.
- Produces: `ResultImageRenderer.render(model: BenchmarkViewModel) -> NSImage?`.
- Produces: `AboutView`.

- [ ] **Step 1: Write the failing tests**

Cover:

- MB/s formatting: `1_250_000` becomes `"1250000"`, `123.456` becomes `"123.46"`;
- GB/s: `1234.5` MB/s becomes `"1.235"`;
- IOPS: `1_500_000` becomes `"1500000"`, `244.140625` becomes `"244.14"`;
- µs: `0` becomes `"0.00"`, `1_500_000` becomes `"1500000"`, `42.7` becomes `"42.70"`;
- meter ratio clamps to `0...1`;
- the text block contains `[Read]`, `[Write]`, `SEQ1M Q8T1`, `Profile: Default`, `Test: 1 GiB (x3)`, `Mode: Read+Write`, `OS:`, `Volume:`, and the attribution line;
- `render(model:)` returns a non-empty `NSImage` at 960 × 600 pixels (2× of 480 × 300).

- [ ] **Step 2: Run tests to verify failure**

Run: `swift test --filter ResultFormatterTests`
Expected: FAIL because the formatter does not exist.

- [ ] **Step 3: Implement formatting and export**

Implement the exact format rules from `SetMeter` in the reference source:

- MB/s: integer at or above 1,000,000, otherwise `%.2f`;
- GB/s: `%.3f` of MB/s / 1000;
- IOPS: integer at or above 1,000,000, otherwise `%.2f`;
- µs: `0.00` when no score; integer at or above 1,000,000; otherwise `%.2f`;
- meter ratio: `1 - (1/6) * log10(latency)` for µs, otherwise `(1/6) * log10(mbps * 10)`, clamped `0...1`.

Build the fixed-width text block with product/version/attribution, `[Read]`, `[Write]`, `Profile:`, `Test:`, `Mode:`, `Time:`, `Date:`, `OS:`, `Volume:`. Do not include the target path.

`ResultImageRenderer` uses `ImageRenderer` on `MainView(model:)`, scale 2, and returns an `NSImage`.

Wire Copy, Save Text, Save Image, and About into the menu commands and the view model.

- [ ] **Step 4: Run tests to verify pass**

Run: `swift test --filter ResultFormatterTests`
Expected: PASS.

Manual check: Copy, Save Text, and Save Image produce the expected block/PNG.

- [ ] **Step 5: Commit**

```bash
git add Sources/CrystalDiskMarkMacCore/Services/ResultFormatter.swift Sources/CrystalDiskMarkMacCore/Services/ResultImageRenderer.swift Sources/CrystalDiskMarkMacCore/Views/AboutView.swift Sources/CrystalDiskMarkMacCore/ViewModels/BenchmarkViewModel.swift Sources/CrystalDiskMarkMac/CrystalDiskMarkMacApp.swift Tests/CrystalDiskMarkMacCoreTests/ResultFormatterTests.swift
git commit -m "feat: add result copy, text, image, and about"
```

---

### Task 14: Icon, README, final build, and QA

**Files:**
- Create: `Scripts/make-icon.swift`
- Create: `Resources/AppIcon.icns`
- Modify: `Scripts/build-app.sh`
- Create/Modify: `README.md`, `NOTICE`, `LICENSE`, `.gitignore`

**Interfaces:**
- Produces: a 1024 × 1024 app icon (dark rounded square, green read bar, blue write bar), converted with `iconutil`.
- Produces: a signed `build/CrystalDiskMarkMac.app`.
- Produces: README with build, run, test, limitations, and attribution.

- [ ] **Step 1: Generate the icon**

`Scripts/make-icon.swift` uses AppKit/CoreGraphics to draw the icon at 1024 × 1024, writes the required `AppIcon.iconset` PNG sizes, and runs `iconutil -c icns`. No CrystalDiskMark logo is copied.

Run:

```bash
swift Scripts/make-icon.swift
```

Expected: `Resources/AppIcon.icns` exists.

- [ ] **Step 2: Build and verify the app**

Run:

```bash
swift test
Scripts/test-engine.sh
Scripts/build-app.sh
codesign --verify --deep --strict --verbose=2 build/CrystalDiskMarkMac.app
```

Expected: all tests pass, the app builds, and code signing verifies.

- [ ] **Step 3: Run the full benchmark on this Mac**

Launch the app, select the boot volume (caches path), set 1 GiB / 3 runs / 5 s / 5 s, run All. Expected: four read + four write results, roughly 3 minutes 15 seconds, no leftover `CrystalDiskMarkMac-*` directory.

Repeat on the external Intel SSD with a writable target folder. Expected: the volume label and target path refer to the external SSD; no fallback to the internal disk.

- [ ] **Step 4: Verify cleanup and edge cases**

- Stop during warm-up, during a measured run, and during an interval; confirm no orphan test directory.
- Try an unwritable folder; confirm a clear error and no fallback.
- Try a test size larger than free space minus 512 MiB; confirm it aborts before creating a file.
- Quit the app during a run; confirm the helper terminates and cleanup is attempted.

- [ ] **Step 5: Write README/NOTICE and commit**

README includes build/run/test commands, the default profile, cache/thermal limitations, write-cache disclosure, and attribution. `NOTICE` lists CrystalDiskMark (MIT, hiyohiyo) and Microsoft DiskSpd (MIT, reference only).

```bash
git add Scripts/make-icon.swift Resources/AppIcon.icns Scripts/build-app.sh README.md NOTICE LICENSE .gitignore
git commit -m "chore: add icon, docs, and final QA"
```

---

## Self-Review Notes

- Spec coverage: default profile, CDM ordering, worker cap, boot/external target rules, free-space boundary, TCC prompt, result export, menus, settings, cleanup, licensing, and build are all mapped to tasks.
- Type consistency: `BenchmarkJob`/`EngineConfig` match the C++ `diskmark::Job`/`Config` fields; `BenchmarkResult` is produced by `ResultAggregator` and consumed by `ResultFormatter`/views.
- Review Focus tests are placed in Tasks 2, 4, 5, 6, 8, 9, 11, 12, and 14.
- Deferred by design: Peak/Real/Demo, MIX, themes, language packs, NVMe Q32T16 preset, universal/Intel builds, App Store, notarization.
