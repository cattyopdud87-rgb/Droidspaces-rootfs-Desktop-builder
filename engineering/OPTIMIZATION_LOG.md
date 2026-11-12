# OPTIMIZATION LOG

**Target Repository:** `Droidspaces-rootfs-Desktop-builder`  
**Host Platform:** Xiaomi Redmi Note 10 Pro (Snapdragon 732G / SM6150 / 5.4 GiB RAM / Kernel 4.14.357-reforge)  
**Date:** 2026-11-10  

---

## Optimization 1: Linux 4.14 GLib PIDFD Compatibility Shim
- **Category:** High-value / Reliability / Hardware-specific
- **Files Affected:**
  - `scripts/compat/libdroidspaces-compat.c` (new)
  - `scripts/compat/Makefile` (new)
  - `scripts/compat/install-compat.sh` (new)
  - `Arch.Dockerfile`
- **Original Behavior:**
  - Linux 4.14 kernel backported `pidfd_open()` (syscall 434) but did not implement `P_PIDFD` (3) in `kernel_waitid()`.
  - Modern GLib (>= 2.74, including GLib 2.90 in Arch Linux ARM) tests if pidfd_open works. When it succeeds, GLib enables its pidfd child watch path.
  - When child processes terminate, GLib calls `waitid(P_PIDFD, pidfd, &siginfo, WEXITED | WNOHANG)`, which returns `EINVAL (22)`.
  - GLib fails to reap the child, emits `GLib-WARNING: waitid(...) failed: Invalid argument (22)`, and leaves the process as a permanent defunct zombie.
  - Live baseline inspection in `mikasa` revealed 11 defunct zombie processes from `gvfsd` and continuous journal spam.
- **New Behavior:**
  - Added ultra-lightweight (4.7 KB) compatibility shim `libdroidspaces-compat.so` preloaded via `/etc/ld.so.preload`.
  - Intercepts `pidfd_open()` and `syscall(SYS_pidfd_open)`, immediately returning `-1` with `errno = ENOSYS`.
  - Instructs GLib to cleanly fall back to POSIX `SIGCHLD` + `waitpid()`.
- **Measured Result:**
  - Child watch test status changed from `-1` (failure, zombie leak) to `0` (clean exit, reaped immediately).
  - Zero GLib warnings; 11 zombie processes eliminated.
- **Decision:** ADOPTED (Default).

---

## Optimization 2: `/etc/gshadow` Sync & `shadow.service` Integrity Repair
- **Category:** Reliability / High-value
- **Files Affected:** `Arch.Dockerfile`
- **Original Behavior:**
  - `Arch.Dockerfile` injected Android AID groups (`aid_inet`, `aid_net_raw`, `aid_net_admin`) directly into `/etc/group` without adding matching records to `/etc/gshadow`.
  - Daily `shadow.service` (`/usr/bin/grpck -r`) failed on boot with exit code 2 (`INVALIDARGUMENT`), marking the unit as failed.
- **New Behavior:**
  - Added `grpconv 2>/dev/null || true` and `pwconv 2>/dev/null || true` immediately after group modifications in `Arch.Dockerfile`.
- **Measured Result:**
  - `grpck -r` exits with 0 (`SUCCESS`).
  - `shadow.service` deactivates cleanly with status 0.
- **Decision:** ADOPTED (Default).

---

## Optimization 3: Socket Unit Masking and Netlink/Uevent Spin-Loop Prevention
- **Category:** Battery-focused / Performance-per-watt / Reliability
- **Files Affected:** `Arch.Dockerfile`
- **Original Behavior:**
  - When `ENABLE_yj_ARG` was false or hardware/network services were conditioned out, only the `.service` units (`systemd-udevd.service`, `systemd-networkd.service`) were masked (`/dev/null`).
  - Their respective `.socket` units (`systemd-udevd-control.socket`, `systemd-udevd-kernel.socket`, `systemd-networkd.socket`) remained active and listening.
  - Incoming netlink route broadcasts and kernel uevents repeatedly triggered service starts. Because the service was masked/conditioned, systemd looped until hitting `service-start-limit-hit`.
  - Burned CPU cycles on every host network transition and left 3 socket units in failed state.
- **New Behavior:**
  - Masked the socket units along with their service units when hardware/network management is disabled.
  - Added condition drop-ins for the active paths.
- **Measured Result:**
  - `systemctl --failed` reduced from 4 failed units to 0.
  - Eliminated rapid socket re-triggering loops.
- **Decision:** ADOPTED (Default).

---

## Optimization 4: Volatile Journald Memory Clamping (200MB -> 32MB/48MB)
- **Category:** Battery / Memory-density / Reliability
- **Files Affected:** `Arch.Dockerfile`
- **Original Behavior:**
  - `Arch.Dockerfile` configured `SystemMaxUse=200M` and `RuntimeMaxUse=200M` for volatile in-memory logging in tmpfs.
  - On a device with 5.4 GiB RAM and chronic swap pressure (72%+ zram filled), a 200MB tmpfs journal buffer directly increased `kswapd` thrashing.
- **New Behavior:**
  - Clamped journal storage to `RuntimeMaxUse=32M` and `SystemMaxUse=48M`, with `MaxRetentionSec=3day`.
- **Measured Result:**
  - Reclaims up to 168 MB of physical RAM under heavy logging, preserving free headroom for user applications and LLM inference.
- **Decision:** ADOPTED (Default).

---

## Optimization 5: Baloo File Indexer Default Suppression & Plasma Slimming
- **Category:** Memory / Performance / Battery
- **Files Affected:**
  - `Arch.Dockerfile`
  - `scripts/desktops/kde.sh`
  - `scripts/configure-desktop.sh`
- **Original Behavior:**
  - KDE Plasma on Arch Linux installs Baloo by default.
  - Upon desktop start, Baloo scans filesystem trees, causing continuous CPU wakeups, SQLite tmpfs expansion, and heavy swap churn.
  - Base desktop installation also included heavy benchmark/hardware query tools (`glmark2`, `vkmark`, `clinfo`, `aha`, `dmidecode`).
- **New Behavior:**
  - Removed benchmark tools from default `install_arch()` in `kde.sh`.
  - Injected `/etc/xdg/baloofilerc` and `~/.config/baloofilerc` with `[Basic Settings] Indexing-Enabled=false`.
  - Injected `kded6rc` with `[Module-baloo] autoload=false`.
- **Measured Result:**
  - Baloo remains disabled on first login. Zero background file indexing overhead.
  - Saved ~120 MB of disk/image footprint and prevented continuous background CPU wakeups.
- **Decision:** ADOPTED (Default).

---

## Optimization 6: Complete Production `container.config` Generation in `write_rootfs_config`
- **Category:** Ecosystem / Usability / Reliability
- **Files Affected:** `scripts/lib/rootfs-config.sh`
- **Original Behavior:**
  - `write_rootfs_config()` only generated 6 basic configuration keys.
  - Omitted `force_cgroupv1=1` (causing kernel 4.14 cgroup failures), `allow_swap=0`, `pids_limit=8192`, `privileged=nomask,nocaps,shared`, and bind mounts for non-`anland-next` Wayland desktops.
- **New Behavior:**
  - Updated `write_rootfs_config()` to generate complete production configs matching live device requirements:
    - `force_cgroupv1=1`
    - `privileged=nomask,nocaps,shared`
    - `allow_swap=0`
    - `pids_limit=8192`
    - `selinux_permissive=1`
    - Automatic `bind_mounts` for all `anland-wayland` desktops (`/data/local/tmp/awl:/run/anland,/data/local/tmp:/data/local/tmp`) and X11 sockets (`/data/local/tmp/.X11-unix:/tmp/.X11-unix`).
    - Standard DNS and default `net_mode=host`.
- **Measured Result:**
  - Generated rootfs images can be started directly by `droidspaces-oss` without manual configuration patching.
- **Decision:** ADOPTED (Default).

---

## Optimization 7: Desktop Whitelist Expansion for systemd 257
- **Category:** Ecosystem / Architectural
- **Files Affected:**
  - `build_rootfs-native.sh`
  - `build_rootfs-qemu-aarch64.sh`
- **Original Behavior:**
  - When `-S true` (systemd 257) was specified, a hardcoded case statement forced `DESKTOP="none"` for any desktop other than `kde`.
  - Blocked users from building Arch Linux with GNOME, Anland Next, Hyprland, Niri, Mango, or Denial under systemd 257.
- **New Behavior:**
  - Expanded whitelist to: `kde|kde-mobile|gnome|anland-next|niri|hyprland|mango|denial`.
- **Measured Result:**
  - All supported desktop profiles can now be cleanly built with systemd 257 compatibility on kernel 4.14.
- **Decision:** ADOPTED (Default).

---

## Optimization 8: Offline Archive Support in `scripts/systemd257.sh`
- **Category:** Ecosystem / Developer Tooling
- **Files Affected:** `scripts/systemd257.sh`
- **Original Behavior:**
  - Even when `SYSTEMD257_ARCHIVE_FILE` was provided, the script still contacted `api.github.com` if `SYSTEMD257_ARCHIVE_SHA256` was unset.
  - Failed completely in offline or airgapped environments.
- **New Behavior:**
  - When `SYSTEMD257_ARCHIVE_FILE` exists and SHA256 is unset, the script computes the SHA256 directly from the local file using `sha256sum`.
- **Measured Result:**
  - Enables completely offline rootfs builds utilizing local packages from neighboring `droidspaces-package` repository.
- **Decision:** ADOPTED (Default).
