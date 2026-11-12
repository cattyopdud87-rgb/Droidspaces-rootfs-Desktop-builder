# ARCHITECTURE & SYSTEM AUDIT

**Target Repository:** `/data/data/com.termux/files/home/development/repo/Droidspaces-rootfs-Desktop-builder/`  
**Host Target Device:** Xiaomi Redmi Note 10 Pro (`sweet` / Qualcomm SM6150 / Snapdragon 732G)  
**Host Kernel:** Linux 4.14.357-reforge-gc52070689 (EOL 4.14 branch with custom Droidspaces patches)  
**Host Userland:** Android 15 (SDK 35), LineageOS "reforge"  

---

## 1. Repository Purpose & Architecture

`Droidspaces-rootfs-Desktop-builder` is the canonical container image and root filesystem generator for the Droidspaces container ecosystem on Android devices. It builds specialized, high-performance root filesystems for:
- **Arch Linux ARM** (`Arch.Dockerfile`)
- **Debian 13 (Trixie)** (`Debian-13.Dockerfile`)
- **Fedora 43 / 44** (`Fedora-43.Dockerfile`, `Fedora-44.Dockerfile`)
- **Ubuntu 24.04 / 25.10 / 26.04** (`Ubuntu-*.Dockerfile`)

### 1.1 Core Components & Execution Paths

```
Droidspaces-rootfs-Desktop-builder
├── build_rootfs-native.sh / build_rootfs-qemu-aarch64.sh (CLI Orchestrators)
│   ├── scripts/lib/desktop-config.sh (Normalization & desktop matrix)
│   ├── scripts/lib/anland-build.sh (Package release resolution)
│   └── scripts/lib/rootfs-config.sh (Writes container.config & tar packaging)
│
├── Dockerfiles (Arch.Dockerfile, Debian-13.Dockerfile, etc.)
│   ├── Package Bootstrap (base toolchains, network, systemd)
│   ├── Desktop Installation (/usr/local/sbin/install-desktop -> scripts/desktops/*.sh)
│   ├── Anland Integration (/usr/local/sbin/install-anland-desktop)
│   ├── Mesa Hardware Acceleration (/usr/local/sbin/install-mesa)
│   ├── systemd 257 Compatibility Freeze (/usr/local/sbin/systemd257)
│   └── Android Runtime Permissions & Systemd Compatibility Layers
│
└── Runtime Utilities (installed into guest rootfs)
    ├── /usr/local/bin/droidspaces-tui (Package & component manager)
    ├── /usr/local/bin/droidspaces-gpu (KGSL / Zink GPU driver switcher)
    └── /usr/local/bin/start-desktop-session (PAM login & desktop launcher)
```

---

## 2. Low-Level Target Hardware & Kernel Constraints

The target device operates under extreme physical and architectural constraints that directly affect how the rootfs must be constructed and configured:

1. **Kernel 4.14 Incomplete cgroup v2 Hierarchy:**
   - Android 4.14 kernels do not support unified cgroup v2 hierarchy correctly (e.g. SchedTune boosting groups and memory controllers fail under v2).
   - The container must enforce `force_cgroupv1=1` and `privileged=nomask,nocaps,shared`.
2. **Upstream systemd 258+ Incompatibility with Kernel 4.14:**
   - Upstream systemd versions >= 258 dropped cgroup v1 compatibility and enforce modern kernel syscall requirements (such as `clone3`, `pidfd`, `statx`, and unified hierarchy).
   - Arch Linux ARM is a rolling release whose official repositories push systemd 258/259+.
   - Booting rolling Arch Linux on Kernel 4.14 requires pinning the **systemd 257** package family (built by neighboring project `droidspaces-package`).
3. **The 32-bit Android Bionic 65,535 PID Limit:**
   - The Qualcomm vendor audio HAL (`audio.primary.sm6150.so`) is a 32-bit ELF whose `pthread_mutex_t` uses a 16-bit thread ID. Any TID > 65,535 triggers a fatal SIGABRT.
   - Any process leak, zombie accumulation, or excessive process churn inside the container accelerates the global PID counter toward this threshold.
4. **Physical Memory Density Constraint (5.4 GiB RAM + 3.0 GiB zram):**
   - Android 15 host services consume ~3.5 to 4.5 GiB of physical RAM.
   - Container workloads compete directly for the remaining ~1.0 GiB.
   - Any in-memory log buffer (e.g., systemd-journald tmpfs), background file indexer (e.g., KDE Baloo), or leaked process triggers `kswapd0` thrashing (6.5–7.7 MB/s swap churn) and Android LowMemoryKiller (LMK) kills.

---

## 3. Discovered Architectural Flaws & Root-Cause Analysis

### Flaw 1: The Linux 4.14 GLib `waitid(P_PIDFD)` EINVAL Zombie Defect (P0)
* **Mechanism:**
  - The custom kernel backported `pidfd_open` (syscall 434), so `pidfd_open()` succeeds.
  - GLib >= 2.74 (Arch Linux ARM ships GLib 2.90) tests if pidfd is supported. Since `pidfd_open` returns an fd, GLib enables its pidfd child watch path.
  - When a child process terminates, GLib invokes `waitid(P_PIDFD, pidfd, &siginfo, WEXITED | WNOHANG)`.
  - In Linux 4.14 `kernel/exit.c:kernel_waitid()`, only `P_ALL`, `P_PID`, and `P_PGID` are recognized; `P_PIDFD` (value 3) hits `default: return -EINVAL;`.
  - GLib receives `EINVAL (22)`, fails to reap the child, logs `waitid(...) failed: Invalid argument (22)`, and leaves the process as a permanent defunct zombie.
* **Impact:** Long-running services (`gvfsd`, desktop daemons, shells) accumulate dozens of zombie processes, leaking PIDs and kernel process table entries.
* **Solution:** Provide a lightweight compatibility DSO (`libdroidspaces-compat.so`) in `/etc/ld.so.preload` or user session wrapper that forces `pidfd_open` to return `ENOSYS`. This triggers GLib's clean POSIX fallback to `waitpid()`/`SIGCHLD`, ensuring all child processes are immediately reaped with exit code 0.

### Flaw 2: `shadow.service` Integrity Verification Failure
* **Mechanism:**
  - `Arch.Dockerfile` injects Android AID groups (`aid_inet:x:3003:`, `aid_net_raw:x:3004:`, `aid_net_admin:x:3005:`) directly into `/etc/group` without updating `/etc/gshadow`.
  - The daily `shadow.service` executes `/usr/bin/grpck -r`, which reports unmatched entries in `/etc/gshadow` and exits with error code 2 (`INVALIDARGUMENT`).
* **Solution:** Execute `grpconv` and `pwconv` immediately after group modifications in `Arch.Dockerfile`.

### Flaw 3: Sockets Ingestion Infinite Retry Loop (`service-start-limit-hit`)
* **Mechanism:**
  - `Arch.Dockerfile` masks or places `ExecCondition` on service units (`systemd-networkd.service`, `systemd-udevd.service`).
  - However, their corresponding socket units (`systemd-networkd.socket`, `systemd-udevd-control.socket`, `systemd-udevd-kernel.socket`) remained active.
  - On incoming netlink packets or kernel uevents, the socket triggers the service. The service is skipped or masked, leaving the socket unserviced.
  - Systemd loops until hitting `service-start-limit-hit`, wasting CPU cycles and leaving failed socket units.
* **Solution:** Mask or condition the socket units along with their service units when network/hardware access is disabled.

### Flaw 4: Incomplete Container Configuration Generation in `rootfs-config.sh`
* **Mechanism:**
  - `write_rootfs_config()` only wrote a partial set of keys to `container.config`.
  - It omitted `force_cgroupv1=1`, `allow_swap=0`, `pids_limit=8192`, `privileged=nomask,nocaps,shared`, and bind mounts for other Wayland desktop environments.
* **Solution:** Update `write_rootfs_config()` to generate complete, production-ready configurations matching actual hardware requirements.

### Flaw 5: Volatile Journald and Desktop Memory Waste
* **Mechanism:**
  - `Arch.Dockerfile` configured `RuntimeMaxUse=200M` and `SystemMaxUse=200M` for volatile journald logging in tmpfs. On a 5.4 GiB RAM device with swap pressure, this is a significant memory penalty.
  - KDE desktop profile installed Baloo file indexer and benchmark tools (`glmark2`, `vkmark`, `clinfo`).
* **Solution:** Clamp journald storage limits to `RuntimeMaxUse=32M` / `SystemMaxUse=48M`. Disable Baloo indexing by default in `kde.sh` and `configure-desktop.sh`.

### Flaw 6: Unnecessary Desktop Whitelist Lock in `build_rootfs-*.sh`
* **Mechanism:**
  - Both build scripts contained:
    ```bash
    case "$ENABLE_systemd257" in
      true)
        case "$DESKTOP" in
          kde) ;;
          none) ;;
          *) DESKTOP="none" ;;
        esac
    ```
  - This artificially blocked building GNOME, Anland Next, Hyprland, Niri, Mango, and Denial with systemd 257.
* **Solution:** Remove the restriction so all supported desktops can benefit from systemd 257 on kernel 4.14.
