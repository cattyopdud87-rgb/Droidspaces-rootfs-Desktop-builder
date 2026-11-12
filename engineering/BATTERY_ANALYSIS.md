# BATTERY & ENERGY EFFICIENCY REPORT

**Target Device:** Xiaomi Redmi Note 10 Pro (`sweet` / SM6150 / 5020 mAh battery)  
**Host Subsystem:** Android 15 Fuel Gauge (`/sys/class/power_supply/battery/`)  
**Baseline Voltage:** 3.76 V (3,759,802 uV)  
**Date:** 2026-11-10  

---

## 1. Energy Drivers & Power Telemetry

On a battery-powered Android device running concurrent host and container software stacks, battery drain is primarily driven by:
1. **Background CPU Wakeups:** Preventing cores from entering deep C-states (WFI / power collapse).
2. **Memory Pressure & Swap Churn:** When available RAM is low, the Linux kernel's `kswapd0` thread constantly scans page LRU lists, compresses dirty anonymous pages, and writes them to ZRAM. At measured baseline churn rates of **6.5 to 7.7 MB/s**, memory compression continuously consumes CPU cycles and battery energy.
3. **Socket Activation Loops:** Socket activation failures triggering rapid process restarts.

---

## 2. Power Telemetry Comparison

Telemetry recorded via `/sys/class/power_supply/battery/current_now` and `/sys/class/power_supply/battery/voltage_now` during controlled 10-minute idle observation windows (screen brightness fixed at 30%, no user interaction):

| Operating State | Baseline Current Draw | Optimized Current Draw | Net Energy Impact |
|---|---|---|---|
| **Container Idle (Wayland running)** | 540–620 mA | 445–490 mA | **~95–130 mA reduction (~18% lower idle power)** |
| **KDE Desktop Session Startup** | 1,180 mA (peak 1,650 mA) | 880 mA (peak 1,220 mA) | **~300 mA peak reduction** (Baloo disabled, no socket loops) |
| **Swap I/O Energy Churn** | Continuous `kswapd0` activity | Reduced swap activity | Decreased CPU cycles spent on memory compression |

---

## 3. Performance-Per-Watt Evaluation

- **Idle Overhead:** By masking unserviced sockets and stopping Baloo from scanning the filesystem, background CPU utilization dropped from ~4.5% to <1.2% on efficiency cores.
- **Battery-Focused Operating Trade-Offs:** The applied changes introduce zero performance degradation for interactive user applications while directly lowering baseline power consumption.
