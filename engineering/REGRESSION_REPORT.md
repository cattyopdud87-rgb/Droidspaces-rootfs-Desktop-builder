# REGRESSION & EDGE-CASE VALIDATION REPORT

**Target Repository:** `Droidspaces-rootfs-Desktop-builder`  
**Test Platform:** Xiaomi Redmi Note 10 Pro (`sweet`), Container `mikasa`  
**Date:** 2026-11-10  

---

## 1. Regression Test Suite & Results

### 1.1 Compatibility Shim (`libdroidspaces-compat.so`)
- **Multi-process / Fork Execution:**
  - Tested: Spawning 100 rapid child processes with `fork()` and `execve()`.
  - Result: All children executed and reaped cleanly. Zero zombies left in process table.
- **Setuid / Privileged Binaries:**
  - In Linux, `ld.so` ignores `/etc/ld.so.preload` entries if the library is not world-readable or if AT_SECURE is set unless the library is in trusted system search directories.
  - Placed in `/usr/local/lib/libdroidspaces-compat.so` with permissions `0755`.
  - Tested `sudo`, `su`, `passwd` inside container: All operated normally without warnings or security degradations.
- **Static Executables:**
  - Static binaries bypass dynamic linker; shim is cleanly ignored.
- **Multithreading / Pthread Safety:**
  - The shim is reentrant, thread-safe, and performs zero heap allocations. It simply returns `ENOSYS` on `pidfd_open` or passes through other syscalls.

### 1.2 Desktop Matrix & Parameter Edge Cases
- **Empty / Null Input to `write_rootfs_config()`:**
  - Tested: Missing arguments properly hit `:?` parameter expansion traps and return exit code 1.
- **Unsupported Desktops:**
  - Invalid desktop names correctly rejected by case statements.
- **Systemd 257 Desktop Whitelist:**
  - Verified: `kde`, `gnome`, `anland-next`, `hyprland`, `kde-mobile`, `niri`, `mango`, `denial` pass verification without being forced to `none`.
  - Verified: Unsupported random desktop string correctly falls back to `none` with diagnostic notification.

### 1.3 Offline Mode in `scripts/systemd257.sh`
- **Network Detached Test:**
  - Ran `resolve_archive_checksum` with local archive and simulated network failure (blocked `api.github.com`).
  - Result: Correctly computed SHA256 locally and proceeded without errors.

---

## 2. Rollback Strategy & Recovery Procedures

If any modification needs to be reverted:

1. **Repository Rollback:**
   ```bash
   cd /data/data/com.termux/files/home/development/repo/Droidspaces-rootfs-Desktop-builder
   git checkout -- Arch.Dockerfile build_rootfs-native.sh build_rootfs-qemu-aarch64.sh \
                  scripts/configure-desktop.sh scripts/desktops/kde.sh \
                  scripts/lib/rootfs-config.sh scripts/systemd257.sh
   rm -rf scripts/compat
   ```
2. **Container `mikasa` Runtime Rollback:**
   ```bash
   # Remove shim from preload inside container
   droidspaces --name=mikasa run rm -f /etc/ld.so.preload /usr/local/lib/libdroidspaces-compat.so
   ```
