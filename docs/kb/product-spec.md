# Product spec

Mac Stats is a macOS menu bar app. It shows live system statistics for six metrics:
CPU, memory, network, GPU, disk I/O and disk usage. Each metric can show its current value,
a chart of a configurable period, or both. The app has no Dock icon (`LSUIElement`).

The clickable wireframe in [wireframe.html](wireframe.html) is the visual reference.
Defaults for everything below are in [configuration.md](configuration.md).

## 1. Items

- An **item** is one metric instance. Kinds: `cpu`, `memory`, `network`, `gpu`, `diskIO`, `diskUsage`.
- `network` and `diskUsage` items can be added more than once. Each copy has a target:
  a network interface (or all interfaces), or a volume.
- Each item has two independent switches:
  - **Menu bar**: the item has a slot in the menu bar.
  - **Menu**: the item appears in the Other metrics list and in the overview.
- An item with Menu bar off and Menu on is **menu only**. It has no slot, but it is one click away in every menu.
- **Remove** deletes an item from the list. **Add item** brings back removed items or adds a copy
  for another interface or volume. A newly added item starts as menu only.
- One shared order controls the menu bar (left to right), the Other metrics list and the overview cards.
  Reorder by dragging a row in Settings, or by focusing a row and pressing ⌥↑ / ⌥↓.

## 2. Menu bar

### 2.1 Display modes (per item)

| Mode | What it shows |
| --- | --- |
| Number | Only the current value. The narrowest option. |
| Chart | A tiny history chart. GPU uses bars, others use a line with a light fill. |
| Chart + number | The tiny chart followed by the value. |
| Gauge | A vertical fill bar plus the value. |
| Two values | Two small stacked lines, such as upload and download. |

- An optional short **label** (for example `CPU`) is drawn before the value.
- The tiny chart covers a configurable window: last 30 s, 1 min or 2 min.
- The tiny chart has no scale numbers (it is only 15 points tall).
- Menu bar charts can be **in color** or **one color, like the menu bar text** (template image).
- The **compact group** mode (several metrics in one item) is a design idea for later. It is not in 0.1.0.

### 2.2 Mac Stats icon

- A generic bars icon that opens all metrics.
- It shows when its switch is on, and **always when no other item is in the menu bar**, so the app never disappears.

### 2.3 Click behavior

- Click an item: opens what **Clicking a menu bar item opens** is set to: the item's own menu, or the overview.
- ⌥-click an item: opens the other one.
- Click the same item again, click outside, or press Esc: closes all panels.
- The Mac Stats icon opens the overview in overview mode. In item-menu mode it opens the **All metrics** list.

## 3. Item menu (level 0)

Top to bottom:

1. **Header**: item name and its big current value. A sub line with context
   (for example `10 cores · 6 performance, 4 efficiency`).
2. **Period chips**: `1m 5m 15m 1h 6h 24h 7d 30d`. Changes this item's chart period. Remembered per item.
3. **Chart** of the chosen period (see section 7).
4. **Legend** of the chart's series.
5. **Detail rows**. Rows ending in › open a breakdown panel to the side (section 5).
6. **Other metrics** (if turned on): a header with the count, then one summary row per other item with Menu on.
7. **Footer actions**: Open Activity Monitor · Item settings… (⌘,) · Hide from menu bar (or Show in menu bar for a menu-only item).

### 3.1 Other metrics list

- One row per item: name, then a summary that depends on the item's **Row in Other metrics** setting:
  Value + chart, Value only, or Two values.
- List style: **Compact rows** (one line, small chart) or **Mini charts** (taller rows, larger chart).
- Hover a row (or click it): that item's full menu opens to the side as a **side menu** (level 1).
  The side menu is the same as the item menu from the menu bar, but it leaves out its own Other metrics list.
- The side menu's rows with › open a breakdown panel (level 2).
- Setting **Open a metric's side menu**: On hover (default) or Only on click.

### 3.2 All metrics list (Mac Stats icon, item-menu mode)

- Header `All metrics` with `Hover a metric to open its menu.`
- One summary row per item with Menu on. Side menus as in 3.1.
- Footer: Settings… (⌘,) · Quit Mac Stats (⌘Q).

## 4. Overview (alternative to the item menu)

- Header `All items` and `N items · click one for its menu`.
- One set of period chips shared by all cards (default 15m).
- A grid of **cards**, one per item with Menu on, in the shared order. 1, 2 or 3 columns.
- Each card: name, big value, chevron; then (depending on **Each card shows**) a chart and a details line
  with two key values. Options: Value, chart and details · Value and chart · Value only.
- The card for the clicked menu bar item is outlined.
- Clicking a card **or its chart** opens that item's own menu:
  - **Beside the overview** (default): as a side menu. Click the card again to close it.
  - **In place**: the panel switches to the item menu with a `‹ All items` row at the top to go back.
- Footer: Settings… · Quit Mac Stats.

## 5. Breakdown panels (› rows)

| Item | Rows (› = breakdown) |
| --- | --- |
| CPU | User · System · Idle · Per core › · Top processes › · Load average › · Temperature and clock › (add-on, explains it is not in v1) |
| Memory | App memory · Wired · Compressed · Cached files · Memory pressure › · Top processes › · Swap › |
| Network | Download · Upload · Interfaces › · Top apps › · Totals › · Public IP › (off; explains why) |
| GPU | Device · Renderer · Tiler · Top apps › · GPU memory › |
| Disk I/O | Read · Write · Per disk › · Top processes › · Operations › |
| Disk usage | Used · Available · Purgeable (counted as free) · Volumes › · Largest folders › · Trend › |

Breakdown panel types:

- **List**: icon, name, optional sub line, small sparkline, value. Shows up to **Rows in breakdown panels** (5, 8, 12),
  then `+ N more · change in item settings`.
- **Bars**: grouped horizontal bars (for example performance and efficiency cores, volumes). Bars over 65% are warning
  color, over 85% critical color.
- **Key-value**: a small chart with scale numbers (when it has history) and key-value lines.
- Optional note at the bottom (for example why data is experimental).

## 6. Panel behavior

- At most **three levels**: menu (0) → side menu or breakdown (1) → breakdown (2).
- Each level opens to the **right**. If it does not fit, it opens to the **left**. Deeper levels keep the parent's
  direction. If neither side fits, the panel overlaps, like a macOS menu.
- The side panel's top aligns with the hovered row.
- **Hover intent**: a row opens its side panel after 60 ms. When a side panel is already open, the delay is 160 ms,
  so a diagonal mouse move into the open panel does not switch rows.
- Moving the pointer into a child panel cancels pending switches in its parents.
- The highlighted row stays highlighted while its side panel is open.
- Panels never take focus away from the active app (non-activating), but they accept keyboard input for Esc.

## 7. Charts

- Chart types: **stacked** (CPU: system + user; memory: wired + app + compressed), **mirror** (network: download up,
  upload down; disk I/O: read up, write down), **area** (GPU device utilization; disk usage used space).
- **Scale numbers** sit **inside the plot** as an overlay (max, middle, zero), with a light outline for contrast.
  They never shrink the chart or move its edges. Overview cards show max and zero only.
- Below the item-menu chart: `−<period>` on the left and `now` on the right.
- Mirror charts label their halves inside the plot: `▲ download` / `▼ upload` (or read / write).
- A chart draws at most 300 points (downsampled with min / average / max buckets).
- **Chart values on hover** (setting): Off (default) · Only while holding ⌥ · Always.
  When shown: a dashed crosshair, a dot per series, and a tooltip with the item name, the time (`14:29:56`,
  `Thu 16:10` or `Tue 24 Nov · 09:00` depending on period), how long ago, each series value and, for stacked charts,
  the total. While values show, that chart stops updating so the value does not slide away.

## 8. Appearance

- **Match system** (default) follows macOS light and dark mode and switches live.
- **Light** or **Dark** forces the app's menus and windows only.
- Menu bar images are redrawn when the menu bar appearance changes.

## 9. Settings window

Tabs: **Items**, **Menu**, **General**, **History**. Opened by Item settings…, Settings…, or ⌘, while a panel is open.
It also opens without the menu bar: open the app again while it runs (double-click it in Finder, or open it from
Spotlight or Launchpad), or run `open macstats://settings` (`macstats://settings/<item id>` selects that item).

- **Items**: the list (Mac Stats icon row first, then items in order) with Menu bar and Menu switches, drag to reorder,
  `+ Add item`, `− Remove`. The detail pane for the selected item: preview, Show in menu bar as, Row in Other metrics,
  Label, Value shown, Menu bar chart covers, Menu chart opens at, Sample every, Rows in breakdown panels, Color.
- **Menu**: Clicking a menu bar item opens · Item menu (Under the details: show the other metrics; List style;
  Open a metric's side menu) · Overview (Clicking a card or its chart; Columns; Each card shows; Chart period hint) ·
  Both (which metrics and order hint; Reset to default).
- **General**: Appearance · Chart values on hover · Menu bar charts · Open at login · On battery ·
  When the screen is locked · Units · Configuration Export… / Import….
- **History**: Keep history for · Per-app history · Stored on disk (size and path) · Delete all history.

## 10. Refresh and sampling

- Totals update every second (or the item's **Sample every**: 1, 2 or 5 s).
- On battery, the **On battery** setting applies (default: every 2 s).
- Per-app lists refresh every 2–5 s, and **only while a panel that needs them is open**.
- `nettop` runs only while the Network → Top apps panel is open.
- Disk usage is sampled every 10 minutes (it changes slowly), and when a menu opens.
- When the screen is locked, menu bar drawing pauses (setting). Sampling for history continues.
- Menu-only items are still sampled, so their history is ready when a menu opens.
