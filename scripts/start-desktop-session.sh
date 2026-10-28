#!/usr/bin/env bash
set -euo pipefail

config="${DROIDSPACES_DESKTOP_CONFIG:-/etc/droidspaces-desktop.conf}"
[[ -r "$config" ]] || { echo "缺少桌面配置文件：$config" >&2; exit 1; }
source "$config"

# Ensure XDG_RUNTIME_DIR is properly initialized with secure 0700 permissions
current_uid="$(id -u)"
runtime_dir="/run/user/$current_uid"
install -d -m 0700 "$runtime_dir" 2>/dev/null || true
export XDG_RUNTIME_DIR="$runtime_dir"

# Clean up stale locks and display sockets from previous boots
rm -f "$runtime_dir/wayland-0*" "$runtime_dir/wayland-0.lock" 2>/dev/null || true

# For Anland Wayland, wait for the display bridge socket to become ready
if [[ "${DISPLAY_BACKEND:-}" == "anland-wayland" ]]; then
    for i in {1..20}; do
        if [[ -S /run/display.sock ]] || [[ -S /data/local/tmp/display_daemon.sock ]]; then
            break
        fi
        sleep 0.5
    done
fi

dbus_wrapper=""
if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]] && command -v dbus-run-session >/dev/null 2>&1; then
    dbus_wrapper="dbus-run-session "
fi

case "${DESKTOP:-}:${DISPLAY_BACKEND:-}" in
    none:x11) command_line='exit 0' ;;
    kde:x11|kde-neon:x11) command_line="export DISPLAY=\"\${DISPLAY:-:5}\"; exec ${dbus_wrapper}startplasma-x11" ;;
    kde:anland-wayland|kde-neon:anland-wayland) command_line="exec ${dbus_wrapper}startplasma-wayland" ;;
    kde-mobile:anland-wayland) command_line="exec ${dbus_wrapper}startplasmamobile" ;;
    gnome:anland-wayland) command_line="exec ${dbus_wrapper}gnome-session --session=gnome" ;;
    # Anland Next 的会话本体就是包内的 anland-session（会话 D-Bus + wayland
    # 链接 + rootless Xwayland + mini-wm），不经过任何桌面环境。用 /usr/bin 下
    # 的系统路径，不依赖用户家目录里的副本；XDG_RUNTIME_DIR 由脚本自己算，
    # systemd 用户管理器不可用时它只告警继续，所以不需要用户级单元先起来。
    anland-next:anland-wayland) command_line='exec /usr/bin/anland-session' ;;
    niri:anland-wayland) command_line='exec /usr/bin/niri-anland' ;;
    hyprland:anland-wayland) command_line='exec /usr/bin/hyprland-anland' ;;
    mango:anland-wayland) command_line='exec /usr/bin/mango-anland' ;;
    denial:anland-wayland) command_line='exec /usr/bin/denial-anland' ;;
    *)
        echo "不支持的桌面会话：${DESKTOP:-未设置}/${DISPLAY_BACKEND:-未设置}" >&2
        exit 1
        ;;
esac

if [[ "${DROIDSPACES_SESSION_DRY_RUN:-false}" == true ]]; then
    printf '%s\n' "$command_line"
    exit 0
fi

exec /bin/bash -lc "$command_line"
