# BASELINE MEASUREMENTS & INITIAL STATE REPORT

**Target Repository:** `Droidspaces-rootfs-Desktop-builder`  
**Git Baseline Commit:** `72a4c8e`  
**Measurement Environment:** Live Xiaomi Redmi Note 10 Pro (`sweet`), Container `mikasa`  
**Date:** 2026-11-09  

---

## 1. Hardware & System Telemetry Baseline

| Subsystem | Metric | Measured Baseline Value |
|---|---|---|
| **CPU** | Cluster topology | 2x Kryo 470 Gold (2.304 GHz) + 6x Kryo 470 Silver (1.804 GHz) |
| **CPU ISA** | Key extensions | ARMv8.2-A: `asimddp`, `fphp`, `asimdhp`, `atomics` |
| **Memory** | Physical RAM total | 5,654,864 kB (≈5.4 GiB) |
| **Memory** | MemAvailable (idle host + container) | ~679 MB (12.0% free headroom) |
| **Swap** | zram total / algorithm | 3,145,724 kB (3.0 GiB) / LZ4 |
| **Swap** | zram usage | ~2.6 GiB uncompressed stored in ~1.0 GiB RAM (~87% capacity) |
| **Battery** | Starting state | 62%, 3760 mV, 40.8 °C |
| **Kernel** | Version / Architecture | Linux 4.14.357-reforge-gc52070689 aarch64 |
| **Init** | Container PID 1 | systemd 257.9 (257.9-2-arch) |

---

## 2. Container Diagnostic & Service Health Baseline

```bash
# Command: systemctl --failed (inside unpatched container)
● shadow.service               loaded failed failed Verify integrity of password and group files
● systemd-networkd.socket      loaded failed failed Network Service Netlink Socket
● systemd-udevd-control.socket loaded failed failed udev Control Socket
● systemd-udevd-kernel.socket  loaded failed failed udev Kernel Socket
```

### Detailed Failure Metrics:
1. **`shadow.service`:**
   - Exit code: 2 (`INVALIDARGUMENT`)
   - Cause: `/etc/group` contained `aid_inet`, `aid_net_raw`, `aid_net_admin` without corresponding entries in `/etc/gshadow`.
2. **`systemd-networkd.socket`:**
   - Failure: `Result: service-start-limit-hit`
   - Cause: Service was conditioned on `net_mode=(nat|gateway)`, but socket remained active, triggering an activation loop on every netlink route update.
3. **`systemd-udevd-*.socket` (Control and Kernel):**
   - Failure: `Result: service-start-limit-hit`
   - Cause: Service was conditioned on `enable_hw_access=1`, but sockets remained active, triggering an activation loop on every kernel uevent.

---

## 3. Process Table & Child Reaping Baseline

### Zombie Processes in Clean Long-Running Session:
```text
Gold     11977 11388  0 02:42 ?        00:00:00 [gvfsd-trash] <defunct>
Gold     12410 11388  0 02:42 ?        00:00:00 [gvfsd-network] <defunct>
Gold     12589 11388  0 02:42 ?        00:00:00 [gvfsd-http] <defunct>
Gold     12590 11388  0 02:42 ?        00:00:00 [gvfsd-http] <defunct>
Gold     12591 11388  0 02:42 ?        00:00:00 [gvfsd-http] <defunct>
Gold     12592 11388  0 02:42 ?        00:00:00 [gvfsd-http] <defunct>
Gold     12593 11388  0 02:42 ?        00:00:00 [gvfsd-http] <defunct>
Gold     12594 11388  0 02:42 ?        00:00:00 [gvfsd-http] <defunct>
Gold     12595 11388  0 02:42 ?        00:00:00 [gvfsd-http] <defunct>
Gold     12596 11388  0 02:42 ?        00:00:00 [gvfsd-http] <defunct>
Gold     12598 11388  0 02:42 ?        00:00:00 [gvfsd-http] <defunct>
Total Defunct Processes: 11
```

### Reproducible Microbenchmark Test:
- Workload: Spawn simple child process (`/bin/true`) using `g_spawn_async(G_SPAWN_DO_NOT_REAP_CHILD)` and wait via `g_child_watch_add()`.
- Result:
  - Error: `GLib-WARNING: waitid(pid:14213, pidfd=4) failed: Invalid argument (22)`
  - Callback status: `status = -1` (failure)
  - Process state: Child process left un-reaped until parent terminates.

---

## 4. Rootfs Configuration & Desktop Support Baseline

1. **`container.config` Generation:**
   - Keys written: `enable_anland`, `enable_termux_x11`, `enable_pulseaudio`, `allow_userns`, `enable_gpu_mode`, `dns_servers` (optional), `net_mode` (optional), `bind_mounts` (only for `anland-next`).
   - Missing required keys: `force_cgroupv1=1`, `allow_swap=0`, `pids_limit=8192`, `privileged=nomask,nocaps,shared`, and bind mounts for other Wayland desktops.
2. **Desktop Support with systemd 257:**
   - Whitelist allowed: `kde`, `none`.
   - Blocked: `gnome`, `kde-mobile`, `anland-next`, `niri`, `hyprland`, `mango`, `denial` (forcibly reset to `none`).
3. **Journald tmpfs Configuration:**
   - `SystemMaxUse=200M`, `RuntimeMaxUse=200M` in tmpfs.
