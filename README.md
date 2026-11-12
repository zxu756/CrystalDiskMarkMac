# CrystalDiskMark Mac

> **Unofficial native macOS port** inspired by [CrystalDiskMark](https://crystalmark.info/) (MIT, hiyohiyo). Not affiliated with or endorsed by CrystalMark.

A native macOS replica of the CrystalDiskMark 9.0.3 default four-test profile. The base 480×300 layout is displayed at 150% (720×450) by the app shell.

- `SEQ1M Q8T1`
- `SEQ1M Q1T1`
- `RND4K Q32T1`
- `RND4K Q1T1`

The app uses SwiftUI for the UI and a bundled C++17 POSIX engine for
file-based benchmarking. Targets macOS 14 (Sonoma) or later on Apple Silicon (`arm64`), ad-hoc
signed. It is not an App Store app and does not use root or raw block devices.

## Download or build

### Prebuilt release

Download `CrystalDiskMarkMac-v0.1.0-macos-arm64.zip` from [Releases](https://github.com/zxu756/CrystalDiskMarkMac/releases), move `CrystalDiskMarkMac.app` to `/Applications`, and clear the quarantine attribute before first launch (ad-hoc signed, not notarized):

```sh
xattr -cr /Applications/CrystalDiskMarkMac.app
```

### Build from source

```sh
swift build
Scripts/build-app.sh
open build/CrystalDiskMarkMac.app
```

Only the Xcode Command Line Tools are required. There is no `.xcodeproj` and
no `xcodebuild` step.

## Test

```sh
swift test
Scripts/test-engine.sh
```

Regenerate the app icon:

```sh
swift Scripts/make-icon.swift
```

## Use

- Choose the test count, test size, target volume, and result unit in the top row.
- Click **All** or press `Cmd-R` to run the four default tests.
- Click **Stop** or press `Cmd-.` to cancel.
- Use **File → Copy / Save (Text) / Save (Image)** for results.
- The boot volume writes under `~/Library/Caches/CrystalDiskMarkMac`; an
  external volume writes under `<volume>/CrystalDiskMarkMac`.

## Defaults

- Test file: 1 GiB
- Measured runs: 3
- Measure time: 5 seconds
- Interval: 5 seconds
- Result unit: MB/s
- Order: all reads, extra interval, all writes; one warm-up per operation

## Limitations

- `F_NOCACHE` is best-effort; macOS and the drive may still cache.
- APFS copy-on-write and compression can affect writes.
- Write results are not fsynced and include the drive's volatile cache,
  matching CrystalDiskMark's default `-S` behavior.
- Thermal throttling and background load change results.
- Results are comparable between runs on this Mac, not guaranteed to match
  Windows CrystalDiskMark.

## License and attribution

MIT. See `LICENSE` and `NOTICE`.

CrystalDiskMark is Copyright (C) 2007-2026 hiyohiyo, MIT.
Microsoft DiskSpd is Copyright (c) 2014 Microsoft, MIT, used as a behavioral
reference only. This project is not affiliated with CrystalMark.
