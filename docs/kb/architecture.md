# Architecture

Data moves one way: collectors read raw counters, the sampler runs them on a schedule, the history store
keeps the results, and the UI reads from the store.

```
StatsKit collectors ──► Sampler (actor) ──► StatsStore (@MainActor, @Observable) ──► UI
   (data layer)          (data layer)        holds latest snapshots + HistoryStore     (AppKit + SwiftUI)
                                                      │
                                                      └──► HistoryDatabase (SQLite, every 30 s)
```

## Modules (Swift packages targets)

| Target | Layer | Contents | Platform |
| --- | --- | --- | --- |
| `StatsCore` | model / domain | Config model and defaults, metric descriptors, snapshot types, ring buffers, tiered history and downsampling, formatting, scale math, time labels, CPU and counter delta math. Foundation only. | macOS and Linux (tested on both) |
| `StatsKit` | data | Collectors (Mach, sysctl, IOKit, libproc, `nettop`), process sampler, `Sampler` actor, SQLite history database, folder scanner. | macOS |
| `MacStats` | UI (executable) | App entry, status items and menu bar renderer, panel controller (3 levels), SwiftUI views (menus, overview, charts, breakdowns), settings window. | macOS |
| `StatsCoreTests` | tests | Unit tests for StatsCore. | macOS and Linux |

## Sampling schedule

- One loop in the `Sampler` actor ticks every second.
- Each item kind is sampled when `now − last ≥ interval`, where interval = the smallest **Sample every** of its items,
  or the **On battery** interval when on battery power.
- Process scans (CPU, memory, disk per process) run every 2 s, and only while a panel that shows them is open,
  or when per-app history is on (every 5 s, top 20 apps).
- `nettop` runs only while Network → Top apps is open. Per-app GPU only while GPU → Top apps is open.
- Disk usage: every 10 min, plus once when a menu opens.

## History

Each series (for example `cpu.usr`) is a `TieredSeries` with four tiers. Each bucket keeps min, average and max,
so short spikes survive downsampling.

| Tier | One point every | Kept for | Serves chart periods |
| --- | --- | --- | --- |
| Raw | 1 s | 1 hour | 1m · 5m · 15m · 1h |
| Tier 1 | 10 s | 24 hours | 6h · 24h |
| Tier 2 | 1 min | 7 days | 7d |
| Tier 3 | 5 min | Keep history for (7 / 30 / 90 days) | 30d |

- Charts request at most 300 points; the store merges buckets to fit.
- Tiers 1–3 are saved to SQLite every 30 s and loaded at launch, so history survives restarts.
  The raw tier lives only in memory.
- Per-app history (sparklines in lists) lives only in memory.

## Panels

- `PanelController` owns three borderless, non-activating `NSPanel`s (levels 0, 1, 2), each hosting SwiftUI.
- Rows report their screen frame; the controller places child panels (right, flip left, keep direction, overlap).
- A global mouse monitor closes everything on an outside click. Esc closes from the key panel.

## Performance budget

- CPU: under 1% on average with default settings.
- Points per chart: at most 300.
- History on disk: about 15–40 MB for 30 days.

## Logging

- The app logs through Apple's unified logging (`os.Logger`), subsystem `app.macstats.MacStats`,
  categories `app`, `menubar`, `panels`, `history`, `sampling` (`Sources/MacStats/Support/Log.swift`).
- Logged: launch (version, macOS, screens), menu bar items, clicks, panel show/place/close with sizes,
  history load counts, first sample, errors. Never process names, file paths or other personal data.
- Collect a log: `log show --last 30m --info --predicate 'subsystem == "app.macstats.MacStats"'`.

## UI smoke test

- `MACSTATS_SELFTEST=<report file>` runs `Sources/MacStats/SelfTest.swift`: it opens the CPU menu, the Network
  side menu and the Interfaces breakdown, then the overview (⌥-click), the same way a click does. Each panel must
  be visible, at least 100 × 100 points and on a screen. It writes the report and exits 0 (pass) or 1 (fail).
- CI runs it on macOS after bundling, takes two screenshots, and uploads the report and screenshots.
- During the test, CI also starts a second copy of the app and fails if it does not quit by itself (single instance).
