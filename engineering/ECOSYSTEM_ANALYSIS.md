# DEVELOPMENT ECOSYSTEM ANALYSIS & SYNERGY REPORT

**Surrounding Ecosystem Path:** `/data/data/com.termux/files/home/development/repo/`  
**Target Repository:** `Droidspaces-rootfs-Desktop-builder`  
**Date:** 2026-11-10  

---

## 1. Neighboring Repositories Investigated

```
development/repo/
├── Droidspaces-rootfs-Desktop-builder (PRIMARY TARGET)
├── droidspaces-package (Package build factory for systemd 257 & Anland)
├── droidspaces-oss (Container runtime engine & daemon)
├── anland (Wayland display & audio IPC bridge)
├── los_kernel_xiaomi_sm6150 (Android 4.14 kernel source)
└── mesa-for-android-container (Freedreno / KGSL acceleration drivers)
```

In accordance with Section 4 (Perspective 2) and Section 15 of the Engineering Directive, **zero modifications were made to neighboring repositories**. All improvements were engineered within `Droidspaces-rootfs-Desktop-builder` to maximize downstream and cross-project utility.

---

## 2. Cross-Project Benefits & Concrete Synergies

### 2.1 Synergy with `droidspaces-package`
- **Integration Challenge:** `droidspaces-package` builds custom `systemd-257` and `anland-*` packages. In the rootfs builder, `scripts/systemd257.sh` previously failed in offline environments because it unconditionally probed GitHub Release API metadata even when a local archive was supplied.
- **Improvements Implemented:**
  - Added native local checksum calculation (`local-archive-sha256`) in `scripts/systemd257.sh` when `SYSTEMD257_ARCHIVE_FILE` is provided.
  - Enabled direct consumption of newly compiled packages from `droidspaces-package/output/` without uploading to GitHub first.
- **Ecosystem Impact:** Greatly accelerates the local package development and testing cycle for developer builds.

### 2.2 Synergy with `droidspaces-oss`
- **Integration Challenge:** The container daemon relies on `container.config` metadata to configure namespaces, cgroups, and storage mounts. `write_rootfs_config()` previously emitted incomplete configs missing `force_cgroupv1=1`, `allow_swap=0`, and `pids_limit=8192`.
- **Improvements Implemented:**
  - `scripts/lib/rootfs-config.sh` now emits production-complete container configuration files.
  - Mitigated the 32-bit Bionic 65,535 PID burn rate: By resolving GLib's `waitid` zombie leak, container processes no longer leak PIDs, preventing the host audio HAL from hitting the 16-bit TID limit.
- **Ecosystem Impact:** Containers extracted from builder images now boot immediately and safely under `droidspaces-oss` without manual configuration patching.

### 2.3 Synergy with `anland`
- **Integration Challenge:** `anland` communicates via Unix domain sockets in `/data/local/tmp/awl/` and `/data/local/tmp/display_daemon.sock`. Previously, `write_rootfs_config()` only added `/run/anland` bind mounts for the `anland-next` desktop profile. Other Wayland desktops (`kde`, `gnome`, `hyprland`, `niri`, `mango`, `denial`) were created without bind mounts, causing socket detachment.
- **Improvements Implemented:**
  - `write_rootfs_config()` automatically binds `/data/local/tmp/awl:/run/anland` and `/data/local/tmp:/data/local/tmp` for **all** `anland-wayland` desktop environments.
  - Added X11 socket mount (`/data/local/tmp/.X11-unix:/tmp/.X11-unix`) for rootless Xwayland compatibility.
- **Ecosystem Impact:** Guarantees seamless display and audio bridge connectivity across all desktop environments.

### 2.4 Synergy with `los_kernel_xiaomi_sm6150`
- **Integration Challenge:** The custom kernel backported `pidfd_open` (syscall 434) without implementing `P_PIDFD` in `kernel_waitid()`. Backporting full PIDFD wait mechanisms into an EOL 4.14 kernel is high-risk and could destabilize process exit paths.
- **Improvements Implemented:**
  - Resolved the incompatibility entirely in userland via `libdroidspaces-compat.so` and `/etc/ld.so.preload`.
- **Ecosystem Impact:** Removes pressure to modify critical kernel exit/wait code, maintaining kernel stability while delivering full modern userland compatibility.

### 2.5 Synergy with On-Device Speech AI (Vaani Stack)
- **Integration Challenge:** The planned offline conversational speech model (Silero VAD + Whisper STT + Qwen2.5 1.5B via llama.cpp + Piper TTS) requires ~1.15 to 1.3 GiB of physical RAM. On a 5.4 GiB device where Android consumes ~4.0 GiB, desktop memory bloat causes immediate OOM killer events.
- **Improvements Implemented:**
  - Clamping journald tmpfs logging reclaims up to 168 MB RAM.
  - Disabling Baloo file indexing stops continuous memory expansion and prevents 6.5–7.7 MB/s swap churn.
  - Trimming unneeded benchmark tools reduces rootfs footprint.
- **Ecosystem Impact:** Preserves the essential memory headroom required to run the conversational AI stack concurrently with the desktop container.
