# Mac Stats knowledge base

This folder is the source of truth for what Mac Stats does and how it is configured.
Code must match it. When behavior changes, update the matching page in the same change.

| Page | What it holds |
| --- | --- |
| [product-spec.md](product-spec.md) | Features and exact UI behavior: menu bar items, menus, side panels, overview, charts, themes. |
| [configuration.md](configuration.md) | Every setting, its allowed values and its default. The default configuration. |
| [data-sources.md](data-sources.md) | Where each number comes from (macOS APIs), and which ones are experimental. |
| [architecture.md](architecture.md) | Modules, data flow, sampling schedule, history tiers, performance budget. |
| [stack.md](stack.md) | Technology choices and why. Known deviations for the current release. |
| [release-0.1.0.md](release-0.1.0.md) | What version 0.1.0 includes, what it leaves out, and how it is built and shipped. |
| [wireframe.html](wireframe.html) | The clickable wireframe (design draft v5). Open it in a browser. It is the visual reference. |

## Glossary

- **Item**: one metric shown by the app, such as CPU or one disk volume. An item can be in the menu bar, in the menu, or both.
- **Menu bar item**: an item's slot in the macOS menu bar (one `NSStatusItem`).
- **Item menu**: the panel that opens under a menu bar item. It shows one item's details.
- **Other metrics**: the list at the bottom of an item menu, one summary row per other item.
- **Side menu**: an item menu opened to the side of another panel (level 1).
- **Breakdown panel**: the panel opened from a row with › (per core, top processes, ...).
- **Overview**: a panel with one card per item. An alternative to the item menu.
- **Mac Stats icon**: one generic icon that opens all metrics. Shown when no item is in the menu bar, or when turned on.
