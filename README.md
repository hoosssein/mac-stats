# Mac Stats

A macOS menu bar monitor for CPU, memory, network, GPU, disk I/O and disk usage.
Each metric can show a number, a chart, or both, in the menu bar or only in the menu.

- Spec, defaults and design: [`docs/kb/`](docs/kb/README.md) (open `docs/kb/wireframe.html` in a browser).
- Requires macOS 14 Sonoma or later. Universal (Apple silicon and Intel).

## Install

Download `MacStats-<version>.zip` from the Releases page and move `Mac Stats.app` to Applications.
Builds are not notarized yet, so on first launch right-click the app and choose **Open**, or run:

```bash
xattr -dr com.apple.quarantine "/Applications/Mac Stats.app"
```

## Build

```bash
swift build
swift test
scripts/bundle.sh 0.1.0
```

See [`CLAUDE.md`](CLAUDE.md) for the project layout and conventions.
