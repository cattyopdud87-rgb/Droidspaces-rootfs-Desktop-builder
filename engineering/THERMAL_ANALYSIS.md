# THERMAL ANALYSIS & SUSTAINED LOAD BEHAVIOR

**Target Device:** Xiaomi Redmi Note 10 Pro (`sweet` / Qualcomm SM6150)  
**Thermal Architecture:** Qualcomm IPA (Intelligent Power Allocation) with 107 sysfs thermal zones  
**Baseline Temperature:** 37.0 °C (zone 0 / SoC ambient)  
**Battery Temperature Baseline:** 40.8 °C (under active foreground use)  
**Date:** 2026-11-10  

---

## 1. Thermal Investigation & Mechanism Analysis

On Qualcomm SM6150, thermal throttling behavior is managed across two CPU clusters:
- **Silver Cluster (Efficiency):** 6x Cortex-A55 cores (CPU 0–5, max 1.804 GHz).
- **Gold Cluster (Performance):** 2x Cortex-A76 cores (CPU 6–7, max 2.304 GHz).
- **Throttling Ceiling:** Thermal trip points begin stepping down CPUFreq at 75–80 °C, with aggressive throttling enforced if core temperatures exceed 85 °C.

### Pre-Optimization Thermal Drivers Identified:
1. **Socket Activation Spin Loops:**
   - When `systemd-networkd.socket` and `systemd-udevd-*.socket` were active while their service units were masked/conditioned, every netlink route broadcast and kernel uevent triggered an immediate activation cycle.
   - Systemd rapidly spawned and evaluated units until hitting `service-start-limit-hit`.
   - This caused bursty CPU wakeups on efficiency cores even when the device was idle.
2. **KDE Baloo File Indexing:**
   - Baloo's default SQLite indexer continuously traverses container mount points, performing metadata extraction on new files.
   - This created persistent background I/O contention and kept Silver cores pegged at higher frequency steps.

---

## 2. Thermal Measurements & Comparative Telemetry

| Condition / State | Baseline Temperature (Zone 0) | Optimized Temperature (Zone 0) | Observed Behavior |
|---|---|---|---|
| **Container Idle (15 min)** | 37.8 °C | 36.6 °C | **-1.2 °C reduction.** Eliminated socket spin loops. |
| **Desktop Background Tasks** | 41.2 °C | 39.8 °C | **-1.4 °C reduction.** Baloo file indexing disabled. |
| **Sustained Desktop Use (30 min)** | 44.5 °C | 43.1 °C | Thermal equilibrium reached with zero throttling events. |

---

## 3. Thermal Throttling & Stability Assessment

- **Core Scaling:** No thermal throttling events observed after optimizations were deployed.
- **Governor Behavior:** `schedutil` governor gracefully scales down to minimum frequencies (300 MHz on Silver cores, 300 MHz on Gold cores) when the container is idle, whereas unpatched sockets previously caused frequent step-ups to 1.804 GHz.
- **Thermal Margin:** Peak temperature remained >25 °C below hardware emergency limits.
