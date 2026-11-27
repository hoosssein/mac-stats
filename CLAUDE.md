# Mac Stats

A macOS menu bar system monitor (CPU, memory, network, GPU, disk I/O, disk usage). Swift, AppKit + SwiftUI.

## Source of truth

`docs/kb/` is the knowledge base. Read `docs/kb/README.md` first.
Code must match `docs/kb/product-spec.md` and `docs/kb/configuration.md`.
When you change behavior or a default, update the KB page in the same change.

## Layout

| Path | Layer | Notes |
| --- | --- | --- |
| `Sources/StatsCore/` | model / domain | Foundation only. Must build and test on Linux too. No AppKit, IOKit or Darwin-only calls. |
| `Sources/StatsKit/` | data | Collectors, sampler, SQLite history. macOS only (`#if os(macOS)` around Darwin code). |
| `Sources/MacStats/` | UI | App entry, status items, panels, SwiftUI views, settings. |
| `Tests/StatsCoreTests/` | tests | XCTest. |
| `scripts/bundle.sh` | build | Wraps the release binary into `Mac Stats.app` and zips it. |
| `.github/workflows/` | CI | `ci.yml` (every push), `release.yml` (tags `v*`). |

## Commands

```bash
swift build                      # debug build (macOS: all targets; Linux: StatsCore + tests only)
swift test                       # runs StatsCoreTests
swift build -c release --arch arm64 --arch x86_64
scripts/bundle.sh 0.1.0          # creates build/Mac Stats.app and build/MacStats-0.1.0.zip (macOS only)
```

On Linux, build only the core: `swift build --target StatsCore` and `swift test`.

## Conventions

- Keep `StatsCore` pure: deterministic, testable, no I/O except `ConfigStore` file reads and writes.
- Collectors never throw to the UI. On failure they return `nil` and the UI shows "Not available on this Mac".
- Experimental sources (`nettop`, per-app GPU) run only while their panel is open.
- No App Sandbox. No network calls (Public IP is not implemented).
- Use base-1000 units unless the user setting says otherwise.
- Write user-facing text in short, plain sentences. Match the wording in the wireframe.

## Pitfalls

- `proc_pid_rusage` fails for processes owned by other users. Do not log every failure.
- `getifaddrs` byte counters are 32-bit and wrap; use `NET_RT_IFLIST2`.
- Swift Charts gets slow above a few hundred points; always downsample to ≤ 300.
- Menu bar images must be redrawn when the menu bar appearance changes.
- There is no Xcode project. Do not add one; use SwiftPM.
