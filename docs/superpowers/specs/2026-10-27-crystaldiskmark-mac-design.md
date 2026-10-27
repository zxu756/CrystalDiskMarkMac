# CrystalDiskMark Mac — Design

- Date: 2026-10-27
- Status: Draft for approval
- Source reference: `/Users/xu/Projects/CrystalDiskMark9_0_3Src` (CrystalDiskMark 9.0.3, MIT)
- Target project: `/Users/xu/Projects/CrystalDiskMarkMac`
- Working app name: **CrystalDiskMark Mac**

## 1. Intent

Build a native macOS app that reproduces the default CrystalDiskMark 9.0.3 experience: the same main-window layout, the same four default tests, the same result units, and a comparable benchmark workflow. This is a macOS reimplementation, not a Windows binary port.

The source is MIT-licensed. The Windows UI is MFC/Win32 and the benchmark engine is Microsoft DiskSpd invoked as a child process. Neither can be compiled on macOS as-is, so the app keeps the observable behavior and replaces the implementation.

Primary use is local/personal. The first version is a local `.app`, not an App Store submission.

## 2. What the source tells us

### 2.1 Architecture

- `CrystalDiskMark/DiskMarkDlg.cpp` (3,792 lines) is an MFC/Win32 dialog UI.
- `CrystalDiskMark/DiskBench.cpp` creates a test file, then launches a bundled `diskspd*.exe` for each test.
- `diskspd22/` and `diskspd2_0_15a/` are Microsoft DiskSpd sources/binaries (MIT).
- Default UI size: `SIZE_X = 480`, `SIZE_Y = 300` (client pixels at 100% zoom).
- Dialog resource: `IDD_DISKMARK_DIALOG`, 267 × 344 dialog units.
- Menus: File, Settings, Profile, Theme, Help, Language.

### 2.2 Default profile (the v1 target)

| Row | Type | Block size | Queues | Threads | Label |
|---|---|---|---|---|---|
| 0 | Sequential | 1 MiB | 8 | 1 | `SEQ1M Q8T1` |
| 1 | Sequential | 1 MiB | 1 | 1 | `SEQ1M Q1T1` |
| 2 | Random | 4 KiB | 32 | 1 | `RND4K Q32T1` |
| 3 | Random | 4 KiB | 1 | 1 | `RND4K Q1T1` |

Defaults:

- Test file size: 1 GiB (index 6 in a 16 MiB … 64 GiB list).
- Test count: 3 measured runs (index 2 in a 1…9 list).
- Measure time: 5 seconds per run.
- Interval time: 5 seconds between tests.
- Result unit: MB/s.
- Test data: random.
- Benchmark mode: read + write.
- CDM runs one full-duration warm-up pass per operation, then the configured number of measured runs; the best measured throughput and the lowest measured latency are retained.

Test-size list: 16 MiB, 32 MiB, 64 MiB, 128 MiB, 256 MiB, 512 MiB, 1 GiB, 2 GiB, 4 GiB, 8 GiB, 16 GiB, 32 GiB, 64 GiB.

Result units: MB/s, GB/s, IOPS, µs.

### 2.3 What is deliberately not copied

- MFC controls, Windows messages, registry/INI plumbing, admin elevation, drive letters.
- DiskSpd itself. The Mac engine is a small POSIX implementation with the same test parameters.
- Anime/theme packs, font rendering settings, and the full language catalog.

## 3. Goals, non-goals, anti-goals

### Goals

1. A native macOS `.app` that visually resembles the CDM 9 default window at 100% zoom.
2. The four default tests work end-to-end with read and write results.
3. Test count, test size, unit, measure time, interval, block size, queue, thread, and data pattern are configurable.
4. Results can be copied and saved as text; the window can be saved as an image.
5. The engine creates its test file only inside the user-selected folder/volume, and cleans it up on success, cancel, and normal quit.
6. The app runs without root, without network access, and without App Store sandbox restrictions.
7. The build works with the installed Command Line Tools only (no full Xcode required).

### Non-goals for v1

- Peak Performance, Real World Performance, Demonstration, and MIX profiles.
- Theme packs, custom fonts, zoom levels, and multi-language UI.
- Historical result database, charts over time, or cloud sync.
- Raw block-device access, TRIM commands, or destructive tests.
- App Store distribution, notarization, or automatic updates.
- Intel Macs, universal binaries, or macOS versions other than the current machine.
- Windows executable analysis inside the app. REA may be used during development, but it is not a runtime dependency.

### Anti-goals

- Showing invented or cached numbers when the engine fails.
- Writing outside the user-selected folder/volume.
- Requiring `sudo`, disabling SIP, or asking for Full Disk Access.
- Leaving orphan test files after a crash or cancel.
- Claiming macOS results are numerically identical to Windows CDM results.

## 4. Approaches considered

### A. SwiftUI app + C++ benchmark helper — chosen

- SwiftUI owns the window, menus, settings, progress, and result rendering.
- A small C++17 helper owns file creation and I/O. It uses `pread`/`pwrite`, `fcntl(F_NOCACHE)`, aligned buffers, and a fixed worker pool.
- The app launches the helper as a child process and reads NDJSON events from stdout.
- Why: matches CDM's GUI + engine split, gives precise queue/thread control, keeps the UI responsive, and makes the engine independently testable.

Trade-off: two build products and a process protocol.

### B. Pure SwiftUI + Swift engine

- One Swift package, `DispatchQueue`/`TaskGroup` workers, same POSIX calls.
- Simpler packaging, but queue-depth semantics and overhead are harder to control, and benchmark stability would be weaker.

### C. Tauri/Electron + native helper

- Web UI can be pixel-perfect, but the app is heavier, less native, and still needs a helper. Rejected for a Mac-only tool.

### D. Port DiskSpd to macOS

- DiskSpd depends on Windows overlapped I/O, `CreateFile`, and `DeviceIoControl`. Porting is much larger than writing a focused POSIX engine. Rejected.

## 5. Architecture

```
┌─────────────────────────────────────────────┐
│ CrystalDiskMarkMac.app                      │
│                                             │
│  SwiftUI UI                                 │
│   ├─ MainWindow / ResultRows                │
│   ├─ SettingsSheet                          │
│   ├─ VolumePicker                           │
│   ├─ ResultExporter (text / PNG)            │
│   └─ BenchmarkController                    │
│          │ Process + JSON config            │
│          │ stdout NDJSON events             │
│          ▼                                  │
│  DiskMarkEngine (bundled C++17 executable)  │
│   ├─ TestFile (create / fill / cleanup)     │
│   ├─ WorkerPool (queue × threads)           │
│   ├─ Sequential / random I/O                │
│   └─ Result math + latency                  │
└─────────────────────────────────────────────┘
```

### Build layout

```
CrystalDiskMarkMac/
├── Package.swift
├── Sources/
│   ├── CrystalDiskMarkMac/        # SwiftUI executable
│   │   ├── App.swift
│   │   ├── Models/
│   │   ├── Views/
│   │   ├── Services/
│   │   └── Resources/
│   └── DiskMarkEngine/            # C++17 executable
│       ├── main.cpp
│       ├── engine.cpp
│       ├── engine.h
│       └── json.hpp (minimal writer/parser)
├── Tests/
│   └── CrystalDiskMarkMacTests/
├── scripts/
│   ├── build-app.sh
│   └── make-icon.sh
├── docs/superpowers/specs/
├── LICENSE
├── NOTICE
└── README.md
```

- `swift build -c release --arch arm64` builds both executable products.
- `scripts/build-app.sh` assembles `CrystalDiskMarkMac.app`, writes `Info.plist`, copies the engine and icon, and ad-hoc signs with `codesign --sign -`. It exits if `uname -m` is not `arm64`.
- No `xcodebuild`, no Xcode project, no external build tool required.
- The app is non-sandboxed so it can write to a user-selected external volume. It is built for this Mac only; no universal binary.

## 6. Benchmark engine

### 6.1 CLI contract

The Swift app writes a JSON config file and launches:

```sh
DiskMarkEngine --config /path/to/session.json
```

The app owns CDM's ordering and interval semantics; the engine executes a flat, ordered job list. A job is one warm-up or measured run of one operation:

```json
{
  "target": "/Volumes/External/CrystalDiskMarkMac",
  "fileSizeBytes": 1073741824,
  "dataPattern": "random",
  "jobs": [
    {
      "id": "seq-1m-q8t1",
      "label": "SEQ1M Q8T1",
      "operation": "read",
      "run": 0,
      "warmup": true,
      "mode": "sequential",
      "blockSizeBytes": 1048576,
      "queueDepth": 8,
      "threads": 1,
      "durationSeconds": 5,
      "intervalAfterMs": 5000
    }
  ]
}
```

The app generates the job list as: all read tests (warm-up + measured), an interval between each; one extra interval between the read and write groups; all write tests (warm-up + measured), an interval between each; no interval after the final run. This matches `ExecDiskBenchAll` in `DiskBench.cpp`.

Engine stdout is newline-delimited JSON:

```json
{"event":"phase","phase":"create","message":"Creating 1 GiB test file"}
{"event":"run","test":"seq-1m-q8t1","operation":"read","run":0,"warmup":true}
{"event":"progress","test":"seq-1m-q8t1","operation":"read","elapsedMs":1200,"bytes":734003200}
{"event":"result","test":"seq-1m-q8t1","operation":"read","mbps":3120.4,"iops":2977.1,"latencyUs":42.7}
{"event":"phase","phase":"cleanup","message":"Removing test file"}
{"event":"done","ok":true}
```

Errors use `{"event":"error","code":"...","message":"..."}` and a non-zero exit code.

### 6.2 Test-file lifecycle

1. Resolve the target folder; require an existing, writable directory.
2. Create a unique subfolder `CrystalDiskMarkMac-<8 hex>` containing a marker file `.crystaldiskmark-mac-session` with a UUID and PID.
3. Create `test.tmp` with `open(O_CREAT|O_EXCL|O_RDWR, 0600)`.
4. Set `fcntl(fd, F_NOCACHE, 1)`.
5. `ftruncate` to the requested size; fill with incompressible pseudo-random bytes (or zeros for 0Fill), then `fsync` once before the first read job. This setup fsync is outside the measured window.
6. Run warm-up and measured tests. Write tests are not fsynced after each operation, matching CDM's `-S` behavior.
7. `close`, delete the file, delete the subfolder, and emit `cleanup` / `done`.
8. On SIGINT/SIGTERM or app termination, attempt the same cleanup. Only remove stale `CrystalDiskMarkMac-*` folders that contain our marker file and are older than 24 hours; never delete an unmarked user folder.

### 6.3 Worker model

- Total requested concurrency = `queueDepth × threads`.
- Each worker issues one synchronous `pread`/`pwrite` at a time, so outstanding I/O ≈ worker count.
- v1 caps active workers at 128. The default profile's maximum is 32 (RND4K Q32T1), so it is represented exactly. The source's NVMe preset (Q32T16 = 512) is disabled in v1 and will require an async engine in a later version.
- Sequential mode: a shared atomic block cursor hands out consecutive block offsets.
- Random mode: each worker draws random aligned offsets in `[0, fileSize - blockSize]`.
- The start is synchronized with a barrier; the duration clock starts after all workers are ready.
- Cancellation sets an atomic flag; workers finish the current syscall and exit.
- Latency is measured with `clock_gettime(CLOCK_MONOTONIC)` around each syscall; the result reports the mean latency and the minimum mean across measured runs.

### 6.4 Result math

- `MB/s = totalBytes / 1_000_000 / elapsedSeconds`.
- `GB/s = MB/s / 1000`.
- `IOPS = MB/s × 1_000_000 / blockSizeBytes`.
- Latency is measured per operation and reported as the mean in microseconds; the result keeps the minimum observed run latency to match CDM's "best" behavior.
- Warm-up runs are not counted. Measured runs: throughput = maximum, latency = minimum.

### 6.5 Limitations to surface in the UI

- `F_NOCACHE` is best-effort; macOS and the drive controller may still cache.
- APFS copy-on-write, compression, and snapshots can affect writes.
- Thermal throttling and background load can change results.
- Results are comparable between runs on the same Mac, not guaranteed to match Windows CDM.
- Write results are not fsynced; they include the drive's volatile cache, matching CDM's default `-S` behavior. The About window and exported text state this.

## 7. UI

### 7.1 Main window

- Fixed content size: 480 × 300 points at 100%.
- Dark CDM-like palette:
  - window `#1B1B1B`
  - panel `#242424`
  - track `#333333`
  - read `#4CD964`
  - write `#32ADE6`
  - primary text `#F5F5F5`
  - secondary text `#9A9A9A`
- Top control row: test count, test size, target volume/folder, result unit.
- Four result rows. Each row:
  - Left: test button with two-line label (`SEQ1M` / `Q8T1`).
  - Middle: read panel with large number, unit label, and horizontal meter.
  - Right: write panel with large number, unit label, and horizontal meter.
  - Hover tooltip: MB/s, GB/s, IOPS, µs, block size, queue, threads.
- Big numbers use a monospaced-digit system font, 32–34 pt bold.
- Bottom: status message (`Preparing...`, `SEQ1M Q8T1 (1/3)`, `Interval Time 3/5 sec`), progress bar, stop button.
- Window title: `CrystalDiskMark Mac`.

### 7.2 Menu bar

Use the native macOS menu bar; the Windows in-window menu is not reproduced as a custom strip.

- **File**: Copy, Save (Text), Save (Image), Quit.
- **Settings**: Default, Flash Memory, Queues & Threads…; NVMe SSD is disabled in v1 (its Q32T16 preset exceeds the synchronous worker cap).
- **Profile**: Default (active); Peak / Real World / Demo disabled with “Coming later”.
- **Test Mode**: Default (Random), All 0x00 (0 Fill).
- **Benchmark**: Read & Write, Read, Write.
- **Theme**: disabled in v1 (single dark theme).
- **Language**: disabled in v1 (English UI).
- **Help**: About CrystalDiskMark Mac, Crystal Dew World link.

### 7.3 Settings sheet

- Four rows with Type (Sequential/Random), Block Size, Queues, Threads.
- Measure Time (1–60 s), Interval Time (0–600 s).
- Test data (Random / 0Fill).
- Presets: Default, NVMe SSD, Flash Memory.
- Validation: queue 1–32, threads 1–16, `queue × threads ≤ 128`, block size 512 B–8 MiB, test size + 512 MiB ≤ free space.
- Save to `UserDefaults` immediately on OK.

### 7.4 Volume picker

- Enumerate mounted local volumes with name, free space, and total capacity.
- Default: the boot volume, mapped to `~/Library/Caches/CrystalDiskMarkMac` because `/` is read-only on modern macOS.
- External volume: use `<volume>/CrystalDiskMarkMac` if the root is writable; otherwise show an error and require “Select Folder…”. Never silently benchmark a different disk and label it as the selected one.
- “Select Folder…” uses `NSOpenPanel` for an arbitrary writable folder.
- Store the chosen path. A security-scoped bookmark is only needed if the app is later sandboxed; v1 is non-sandboxed.
- Free-space checks use `testSize + 512 MiB` at selection time and before each test.

### 7.5 Result export

- Copy: fixed-width text block matching CDM’s `SaveText` structure, adapted to macOS:
  - product/version/copyright header with attribution;
  - `[Read]` and `[Write]` sections;
  - `Profile:`, `Test:`, `Mode:`, `Time:`, `Date:`, `OS:`, `Volume:` lines;
  - no target path, for privacy.
- Save Text: `.txt` with the same block.
- Save Image: render the main window to PNG at 2× scale.

## 8. Configuration model

Use `UserDefaults` keys mirroring the CDM INI names so behavior is easy to compare:

| Key | Default |
|---|---|
| `TestCount` | 3 |
| `TestSizeIndex` | 6 (1 GiB) |
| `TestUnitIndex` | 0 (MB/s) |
| `BenchType0…3` | 0, 0, 1, 1 |
| `BenchSize0…3` | 1024, 1024, 4, 4 (KiB) |
| `BenchQueues0…3` | 8, 1, 32, 1 |
| `BenchThreads0…3` | 1, 1, 1, 1 |
| `MeasureTime` | 5 |
| `IntervalTime` | 5 |
| `TestData` | random |
| `Benchmark` | read+write |
| `Profile` | default |
| `TargetPath` | `~/Library/Caches/CrystalDiskMarkMac` (boot volume) |

Out-of-range values fall back to defaults, matching the source’s validation style.

## 9. Error handling and edge cases

- **Insufficient space**: stop before creating the file; show required vs available.
- **Unwritable target**: offer folder selection; never attempt privilege escalation.
- **External volume unplugged**: abort, report the path, attempt cleanup, and keep the last valid results visible but marked stale.
- **Helper crash or missing**: show a clear error; do not fabricate results.
- **Cancel/Stop**: terminate the helper, wait up to 2 seconds, then SIGKILL; clean stale files on next launch.
- **App quit during a test**: terminate the helper, attempt cleanup, and leave a marker if cleanup cannot complete.
- **Partial test failure**: keep completed results; mark the failed test as an error.
- **Free space changes during a test**: re-check before each test; abort if below `testSize + 512 MiB`.
- **Removable-volume consent**: macOS may show a TCC prompt on first access. `Info.plist` includes `NSRemovableVolumesUsageDescription`; a denied prompt shows a recovery message and does not fall back to another disk.
- **Ad-hoc rebuilds**: macOS may re-prompt after a rebuild because the ad-hoc signature changes. This is accepted for this local-only app; no stable signing identity or distribution path is planned for v1.

## 10. Security, privacy, and licensing

- No network calls, telemetry, analytics, or auto-update.
- No root, no raw device access, no SIP changes, no Full Disk Access.
- The engine only touches the selected target folder and its own test subfolder.
- The app is ad-hoc signed for local use; no Developer ID or notarization is planned. Nested `DiskMarkEngine` is signed before the outer app.
- `Info.plist` declares `NSRemovableVolumesUsageDescription`; macOS TCC may still prompt for removable-volume access. Re-prompting after a rebuild is accepted.
- Include the original MIT copyright notice and a `NOTICE` file:
  - CrystalDiskMark © 2007–2026 hiyohiyo, MIT.
  - Microsoft DiskSpd © 2014 Microsoft, MIT (reference only; no code copied).
  - This project is not affiliated with CrystalMark.
- Working title uses “CrystalDiskMark Mac” with attribution. Before public distribution, rename and use a new icon to avoid trademark confusion.

## 11. Testing and verification

### Unit tests

- Unit formatting: MB/s, GB/s, IOPS, µs; rounding and large values.
- Configuration validation and fallback.
- Test profile mapping and label generation.
- NDJSON event decoding.

### Engine tests

- 64 MiB temp file, 1-second runs, sequential and random, read and write.
- Assert positive throughput, bounded offsets, correct byte counts, and cleanup.
- Cancellation during a run; assert no orphan file.
- Insufficient-space and unwritable-folder failures.

### Integration tests

- Build the `.app` with `scripts/build-app.sh`.
- Launch, run all four default tests on a 1 GiB file, and verify four read + four write results.
- Compare sequential read/write with `dd` on the same file; expect the same order of magnitude.
- Run on the internal Apple SSD (via `~/Library/Caches/CrystalDiskMarkMac`) and the external Intel SSD.
- Verify the CDM ordering: all reads, extra interval, all writes; per-operation warm-up; 7 intervals total for the default read+write run.
- Verify Copy/Save Text against a golden CDM-style block.
- Verify the removable-volume consent path and the no-fallback error on an unwritable volume.
- Test only on this Mac: Mac mini M4, macOS 27.0.1, arm64. No Intel or older-macOS matrix.
- Take a screenshot and compare the layout against the source dialog proportions.

### Manual checks

- Copy and Save Text produce a readable result block.
- Save Image produces a valid PNG.
- Settings changes persist across relaunch.
- Stop during warm-up, during a measured run, and during the interval.
- Quit during a test leaves no `CrystalDiskMarkMac-*` folder.

## 12. Delivery milestones

1. **Scaffold**: arm64-only SwiftPM package, two executable targets, `build-app.sh`, blank 480×300 window, ad-hoc signing, `Info.plist` with removable-volume usage description.
2. **Engine**: test-file lifecycle with marker, worker pool capped at 128, sequential/random read/write, CDM ordering, NDJSON, cancellation, unit tests.
3. **Static UI**: four rows, top controls, status bar, menus, dark theme, mock results.
4. **Integration**: launch engine, progress events, live results, stop, interval countdown.
5. **Settings and export**: settings sheet, presets, volume picker, copy/save text/image, About/license.
6. **Polish and QA**: icon, error states, cleanup, internal/external SSD runs, screenshot check, README.

## 13. Decisions left to the builder

- Exact pixel spacing and font sizes within the 480×300 window; match the source proportions and adjust after the first screenshot.
- Minimal JSON parser/writer implementation in C++ (no external dependency) vs a header-only library; choose the smallest reliable option.
- Whether to use `NSOpenPanel` for the “Select Folder…” entry or a custom volume list with a folder fallback; the source uses a drive combo, so the volume list is primary.
- Icon design; use a new simple disk/speedometer mark, not the CrystalDiskMark logo.
- Whether to show a one-time disclaimer about cache/thermal effects; default to a compact footer note in About.
- Deployment target: macOS 27.0, arm64 only, ad-hoc signing; no universal build.

## 14. Resolved distribution decision

- Target: this Mac only (Mac mini M4, macOS 27.0.1, arm64).
- `Package.swift` platform: macOS 27.0; build with `--arch arm64`; no universal binary.
- Signing: ad-hoc; nested helper signed first; no Developer ID or notarization.
- TCC may re-prompt after a rebuild; accepted for this local-only app.
