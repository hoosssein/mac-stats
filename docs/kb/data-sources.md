# Data sources

Totals come from public macOS APIs. Some breakdown details do not. Tags:
**public** = documented API · **tool** = parses a system tool's output · **undocumented** = may break in a macOS update.
Experimental sources must fail quietly: the panel then shows "Not available on this Mac".

| Metric | Totals (menu bar and menu) | Breakdown details | Notes |
| --- | --- | --- | --- |
| CPU | `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` per-core user/system/idle/nice ticks; diff two samples. Load average: `getloadavg`. **public** | Per core: same call. Performance / efficiency groups: `sysctl hw.perflevel0.logicalcpu` and `hw.perflevel1.logicalcpu`. Per process: `proc_listallpids` + `proc_pid_rusage(RUSAGE_INFO_V4)` CPU-time delta. **public** | Processes owned by other users (root) refuse `proc_pid_rusage`. 0.1.0 shows the remainder as one line: **System and other users** = total CPU − measured processes. Temperature and clock need private SMC / IOReport: add-on, not in v1. Values are "% of one core", like Activity Monitor. |
| Memory | `host_statistics64(HOST_VM_INFO64)`: app = (internal − purgeable) pages, wired, compressed (compressor pages), cached files = external + purgeable pages; × `vm_kernel_page_size`. Total: `sysctl hw.memsize`. Pressure: `sysctl kern.memorystatus_vm_pressure_level` (1 normal, 2 warning, 4 critical). Swap: `sysctl vm.swapusage`. **public** | Per process: `proc_pid_rusage` → `ri_phys_footprint` (Activity Monitor's "Memory"). **public** | Activity Monitor's exact "App memory" formula is not documented; ours is close. |
| Network | `sysctl {CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0}` → `if_msghdr2.ifm_data` 64-bit byte counters per interface. Loopback excluded. **public** | Per interface: same data, IPv4 from `getifaddrs`, link speed from `ifi_baudrate`. Per app: `nettop -P -L 2 -s 1 -d -x -J bytes_in,bytes_out`, only while the panel is open. **tool** | "All interfaces" leaves out VPN tunnels (`utun`, `ipsec`, `ppp`): their traffic also crosses a physical interface, so it would count twice. `nettop` output can change between macOS versions. Wi-Fi network name needs Location permission (not used in 0.1.0). Public IP needs an outside service: off, not implemented in 0.1.0. |
| GPU | IOKit `IOAccelerator` → `PerformanceStatistics`: "Device Utilization %", "Renderer Utilization %", "Tiler Utilization %", "In use system memory", "Alloc system memory". **IORegistry** | Per app (Apple silicon): accelerator children of class `AGXDeviceUserClient`: `IOUserClientCreator` ("pid N, Name") and `AppUsage[].accumulatedGPUTime` (ns); share = delta / interval. **undocumented** | Keys differ on Intel/AMD. Hide per-app GPU when keys are missing. |
| Disk I/O | IOKit `IOBlockStorageDriver` → `Statistics`: "Bytes (Read)", "Bytes (Write)", "Operations (Read)", "Operations (Write)", "Total Time (Read)", "Total Time (Write)". **public** | Per disk: one driver per physical disk; name from the parent device's `Device Characteristics` → "Product Name". Per process: `proc_pid_rusage` → `ri_diskio_bytesread` / `ri_diskio_byteswritten`. **public** | Same root-process limit as CPU. |
| Disk usage | `URLResourceValues`: `volumeTotalCapacity`, `volumeAvailableCapacityForImportantUsage` (counts purgeable as free, like Finder), `volumeAvailableCapacity` (to compute purgeable). **public** | Volumes: `FileManager.mountedVolumeURLs(… .skipHiddenVolumes)`. Largest folders: background scan of the home folder's top-level folders and `/Applications`, only on request, cancellable. **public** | Sampled every 10 min. Scanning other apps' data needs Full Disk Access; folders we cannot read are skipped. |

## Units

- Rates use bytes per second, base 1000 by default (`KB/s`, `MB/s`), like Finder.
- Base 1024 uses `KiB/s`, `MiB/s`. "Bits for network" shows network rates in `Kb/s`, `Mb/s`.
- CPU per-process values are % of one core (can exceed 100%).
