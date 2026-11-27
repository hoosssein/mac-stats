# Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | Swift 6 toolchain | Calls Mach, `sysctl`, libproc and IOKit directly. |
| Concurrency | `StatsCore` in Swift 6 language mode (strict). `StatsKit` and `MacStats` in Swift 5 mode with complete concurrency checking as warnings. | See deviation D1. |
| Menu bar items | AppKit `NSStatusItem`, one per item | Items are added, removed and reordered at runtime. |
| Item menu, side menus, breakdowns, overview | Custom borderless non-activating `NSPanel` + SwiftUI (`NSHostingView`) | Live charts, chips, hover panels and the overview need full control. |
| Charts in panels | Swift Charts | Built in. Hover uses a chart overlay with `ChartProxy` and a crosshair. |
| Menu bar sparklines | Core Graphics → `NSImage` | Redrawn once per second; much cheaper than SwiftUI in the status bar. |
| UI state | Observation (`@Observable`) on the main actor | Views redraw only when the values they read change. |
| Appearance | `appearance` on the app's panels and settings window = `nil` (system), `.aqua` or `.darkAqua` | Forces only the app's menus and windows; menu bar items keep following the menu bar. SwiftUI and Swift Charts follow it. Menu bar images redraw when the menu bar's `effectiveAppearance` changes. |
| History | In-memory tiered ring buffers + SQLite | Fast range reads; survives restarts. See deviation D2. |
| Settings | SwiftUI views in an `NSWindow` + one `Codable` config (`AppConfig`) | One JSON document. Easy to export, import and reset. |
| Open at login | `SMAppService.mainApp` | Built into macOS 13+. |
| Updates | Sparkle 2 | Planned. See deviation D3. |
| Distribution | Developer ID + notarization, no App Sandbox | Planned. See deviation D4. The sandbox would block per-app details. |
| Minimum macOS | macOS 14 Sonoma | Observation and a mature Swift Charts. |
| Build | Swift Package Manager; `scripts/bundle.sh` wraps the executable into `Mac Stats.app` | No Xcode project needed; builds the same on CI and locally. |
| Tests | XCTest for `StatsCore` (runs on macOS and Linux) | Delta math, counter wraparound, tiers and rollups, formatting, config defaults. |
| CI | GitHub Actions on `macos-latest` | Build, test, bundle on every push; release on `v*` tags. |

## Deviations for 0.1.0 (decided, with reasons)

- **D1 Concurrency mode.** Only `StatsCore` uses Swift 6 strict mode in 0.1.0. AppKit-heavy code moves to Swift 6 mode
  in a later release, once it is checked on a Mac with full diagnostics.
- **D2 SQLite library.** 0.1.0 uses the system SQLite C library directly (`import SQLite3`) instead of GRDB.swift.
  It needs no extra dependency, and the history schema is one small table. Moving to GRDB later is easy.
- **D3 Sparkle.** Sparkle needs a signing key pair and an appcast host. 0.1.0 has no auto-update;
  new versions are on the GitHub Releases page.
- **D4 Signing.** No Developer ID certificate is available yet. 0.1.0 is **ad-hoc signed and not notarized**.
  First launch: right-click the app → Open, or run `xattr -dr com.apple.quarantine "/Applications/Mac Stats.app"`.
