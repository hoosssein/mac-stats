# Configuration

All settings live in one JSON document:
`~/Library/Application Support/Mac Stats/config.json`.
The Swift model is `AppConfig` in `Sources/StatsCore/Config/AppConfig.swift` (model layer).
Unknown or missing keys fall back to the defaults below, so old files keep working.

## 1. Default configuration

### 1.1 Items (default order = menu bar order, left to right)

| id | Kind | Name | Label | Menu bar | Menu | Show in menu bar as | Menu chart opens at | Color | Row in Other metrics | Value shown |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `cpu` | cpu | CPU | CPU | **on** | on | Chart + number | 5m | Blue | Value + chart | Total |
| `mem` | memory | Memory | MEM | **on** | on | Gauge | 1h | Blue | Value + chart | Used % |
| `net` | network (all interfaces) | Network | NET | **on** | on | Two values | 5m | Blue | Two values | Up and down |
| `gpu` | gpu | GPU | GPU | off | on | Chart | 15m | Violet | Value + chart | Device utilization |
| `dio` | diskIO | Disk I/O | I/O | off | on | Two values | 5m | Blue | Two values | Read and write |
| `du` | diskUsage (boot volume `/`) | Disk usage | SSD | off | on | Number | 7d | Blue | Value + chart | Free space |

Shared item defaults: Label shown · Menu bar chart covers **last 1 min** · Sample every **1 s** ·
Rows in breakdown panels **8**.

**Mac Stats icon**: off (it still shows automatically when no item is in the menu bar).

### 1.2 Menu

| Setting | Values | Default |
| --- | --- | --- |
| Clicking a menu bar item opens | The item's own menu · Overview of all items | **The item's own menu** |
| Under the details: show the other metrics | on · off | **on** |
| List style | Compact rows · Mini charts | **Compact rows** |
| Open a metric's side menu | On hover · Only on click | **On hover** |
| Clicking a card or its chart | Opens its menu beside the overview · Opens its menu in place | **Beside the overview** |
| Overview columns | 1 · 2 · 3 | **2** |
| Each card shows | Value, chart and details · Value and chart · Value only | **Value, chart and details** |
| Overview chart period | 1m … 30d (set with the overview's chips) | **15m** |

**Reset to default** (Menu tab) restores section 1.1 and 1.2: item list, order, switches and menu settings.
It does not change General or History settings.

### 1.3 General

| Setting | Values | Default |
| --- | --- | --- |
| Appearance | Match system · Light · Dark | **Match system** |
| Chart values on hover | Off · Only while holding ⌥ · Always | **Off** |
| Menu bar charts | In color · One color, like the menu bar text | **In color** |
| Open at login | on · off | **on** |
| On battery | Sample every 2 s · Same as on power · Sample every 5 s | **Sample every 2 s** |
| When the screen is locked | Pause menu bar drawing · Keep drawing | **Pause menu bar drawing** |
| Units | Bytes, base 1000 (like Finder) · Bytes, base 1024 · Bits for network | **Bytes, base 1000** |

### 1.4 History

| Setting | Values | Default |
| --- | --- | --- |
| Keep history for | 7 days · 30 days · 90 days | **30 days** |
| Per-app history | Last 15 min, top 20 apps · Off · Last 1 h, top 20 apps | **Last 15 min, top 20 apps** |

## 2. Per-item settings

| Setting | Values |
| --- | --- |
| Show in menu bar (switch) | on · off |
| Show in menu (switch) | on · off |
| Show in menu bar as | Number · Chart · Chart + number · Gauge · Two values |
| Row in Other metrics | Value + chart · Value only · Two values |
| Label | on · off (shows the item's short label before the value) |
| Value shown | Depends on kind (first option is the default): CPU: Total · User only · Busiest core. Memory: Used % · Used GB · Pressure. Network: Up and down · Download only · Upload only. GPU: Device utilization · Renderer · Memory in use. Disk I/O: Read and write · Total. Disk usage: Free space · Used % · Used / total. |
| Menu bar chart covers | Last 30 s · Last 1 min · Last 2 min |
| Menu chart opens at | 1m · 5m · 15m · 1h · 6h · 24h · 7d · 30d (the period chips change it too) |
| Sample every | 1 s · 2 s · 5 s |
| Rows in breakdown panels | 5 · 8 · 12 |
| Color | Blue · Orange · Violet · Green · Red |
| Target | Network: interface BSD name or all. Disk usage: volume path. |

## 3. JSON shape

```json
{
  "version": 1,
  "showStatsIcon": false,
  "items": [
    { "id": "cpu", "kind": "cpu", "showInMenuBar": true, "showInMenu": true,
      "displayMode": "chartAndNumber", "summaryStyle": "valueAndChart", "showLabel": true,
      "valueShown": 0, "menuBarChartSeconds": 60, "menuRange": "5m", "sampleSeconds": 1,
      "breakdownRows": 8, "color": "blue", "target": null }
  ],
  "menu": { "clickOpens": "itemMenu", "showOtherMetrics": true, "listStyle": "compactRows",
            "sideMenuOpens": "onHover", "cardOpens": "beside", "overviewColumns": 2,
            "overviewCard": "full", "overviewRange": "15m" },
  "general": { "appearance": "system", "chartValues": "off", "menuBarChartColor": "colored",
               "openAtLogin": true, "onBattery": "every2s", "whenLocked": "pauseDrawing", "units": "base1000" },
  "history": { "keepDays": 30, "perAppHistory": "last15min" }
}
```
