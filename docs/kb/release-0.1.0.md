# Release 0.1.0

## Included

- All six metrics with live totals, history and charts: CPU, memory, network, GPU, disk I/O, disk usage.
- Menu bar items with all five display modes, label, color, chart window, monochrome option, and the Mac Stats icon fallback.
- Items list: menu bar and menu switches, reorder, add (extra network interfaces and volumes), remove.
- Item menus with period chips, charts with in-plot scale numbers, detail rows, footer actions.
- Other metrics list (compact rows or mini charts) with side menus; up to three panel levels.
- Overview mode: cards, 1–3 columns, card content options, shared period, open beside or in place, ⌥-click.
- Breakdown panels for every › row in [product-spec.md](product-spec.md) section 5.
- Chart values on hover (off by default; ⌥ only; always).
- Appearance: match system, light, dark.
- Settings window with Items, Menu, General and History tabs; JSON config; reset to default; export and import.
- History tiers saved to SQLite; keep 7 / 30 / 90 days; delete all history.
- Open at login, battery sampling, pause drawing when locked, units.

## Not in 0.1.0

| Feature | Status |
| --- | --- |
| Temperature, clock, fans | Add-on later (private SMC / IOReport). The row explains this. |
| Public IP | Later; needs an outside service and an opt-in setting. The row explains this. |
| Compact group display mode | Later. |
| Sparkle auto-update | Later (deviation D3). |
| Developer ID signing and notarization | Later (deviation D4). The 0.1.0 build is ad-hoc signed. |
| Wi-Fi network name | Later; needs Location permission. |

## Build and ship

- `swift build -c release --arch arm64 --arch x86_64` builds a universal binary.
- `scripts/bundle.sh <version>` creates `build/Mac Stats.app` (Info.plist with `LSUIElement`, version, minimum macOS 14),
  ad-hoc signs it, and zips it to `build/MacStats-<version>.zip`.
- `.github/workflows/ci.yml` runs build, tests and bundle on every push, and uploads the zip as an artifact.
- `.github/workflows/release.yml` runs on tags `v*` (or manually with a version). It builds, tests, bundles and
  publishes a GitHub release with the zip.
