#!/usr/bin/env bash
set -euo pipefail

source "${ROOTFS_DIR:-}/etc/os-release"

configure_environment() {
    local backend="${1:-}"
    local environment_file="${ROOTFS_DIR:-}/etc/environment"
    local assignment key
    local -a assignments=(
        XCURSOR_SIZE=48
        XDG_SESSION_CLASS=user
        XDG_CURRENT_DESKTOP=KDE
        XDG_SESSION_DESKTOP=KDE
        MESA_LOADER_DRIVER_OVERRIDE=kgsl
        GALLIUM_DRIVER=kgsl
        FD_FORCE_KGSL=1
        LIBGL_ALWAYS_SOFTWARE=0
        KWIN_COMPOSE=O2ES
    )

    case "$backend" in
        x11)
            assignments+=(DISPLAY=:5)
            ;;
        anland-wayland)
            assignments+=(
                WAYLAND_DISPLAY=wayland-0
                QT_QPA_PLATFORM=wayland
                ANLAND=1
                ANLAND_SOCKET=/run/display.sock
                ANLAND_DRM_DEVICE=/dev/dri/renderD128
                ANLAND_SKIP_IMPLICIT_SYNC_WAIT=1
            )
            ;;
        *)
            echo "KDE Neon 显示后端无效：$backend" >&2
            return 1
            ;;
    esac

    touch "$environment_file"
    for assignment in "${assignments[@]}"; do
        key="${assignment%%=*}"
        grep -q "^${key}=" "$environment_file" || printf '%s\n' "$assignment" >> "$environment_file"
    done
}

install_neon_apt() {
    case "$ID:$VERSION_ID" in
        ubuntu:24.04*) ;;
        *)
            echo "KDE Neon 仅支持 Ubuntu 24.04 (Noble)，当前系统为：$ID $VERSION_ID" >&2
            return 1
            ;;
    esac

    echo "--> [KDE Neon] 配置 KDE neon Noble 软件源与密钥..."
    apt-get update -qq || true
    apt-get install -y --no-install-recommends ca-certificates curl gnupg

    mkdir -p /etc/apt/trusted.gpg.d
    if [ ! -f /etc/apt/trusted.gpg.d/neon-archive-keyring.gpg ]; then
        curl -fsSL https://archive.neon.kde.org/public.key | gpg --dearmor -o /etc/apt/trusted.gpg.d/neon-archive-keyring.gpg
    fi

    mkdir -p /etc/apt/sources.list.d
    cat <<'EOF' > /etc/apt/sources.list.d/neon.list
deb [signed-by=/etc/apt/trusted.gpg.d/neon-archive-keyring.gpg] http://archive.neon.kde.org/user noble main
deb-src [signed-by=/etc/apt/trusted.gpg.d/neon-archive-keyring.gpg] http://archive.neon.kde.org/user noble main
EOF

    local arch
    arch="$(dpkg --print-architecture)"

    if [ "$arch" = "amd64" ]; then
        echo "--> [KDE Neon] 检测到 AMD64 架构：使用官方 Neon Plasma 6 桌面套件..."
        mkdir -p /etc/apt/preferences.d
        cat <<'EOF' > /etc/apt/preferences.d/99-neon
Package: *
Pin: release o="user noble"
Pin-Priority: 1001

Package: *
Pin: origin "archive.neon.kde.org"
Pin-Priority: 1001
EOF
        apt-get update
        apt-get dist-upgrade -y --allow-downgrades --no-install-recommends
        apt-get install -y --allow-downgrades --no-install-recommends \
            neon-desktop \
            dbus-x11 x11-xserver-utils breeze-icon-theme \
            pipewire pipewire-alsa pipewire-pulse wireplumber upower \
            mesa-utils pulseaudio-utils vulkan-tools dbus-user-session \
            aha clinfo dmidecode libdisplay-info-bin wayland-utils xserver-xorg \
            xdg-user-dirs libcanberra-pulse gstreamer1.0-plugins-base gstreamer1.0-plugins-good sound-theme-freedesktop \
            polkit-kde-agent-1 libpam-systemd libpam-modules \
            fonts-noto-cjk fonts-noto-color-emoji \
            language-pack-kde-zh-hans language-pack-zh-hans qt6-translations-l10n \
            dolphin konsole kate ark
    else
        echo "--> [KDE Neon] 检测到 ARM64 架构：KDE neon noble 仓库上游暂未为 arm64 编译 plasma-desktop 二进制"
        echo "--> [KDE Neon] 配置 Neon 软件源并集成兼容 KDE Plasma 栈、Neon 视觉主题、图标、字体及硬件加速配置..."
        mkdir -p /etc/apt/preferences.d
        cat <<'EOF' > /etc/apt/preferences.d/99-neon
Package: *
Pin: origin "archive.neon.kde.org"
Pin-Priority: 100
EOF
        apt-get update
        apt-get install -y --allow-downgrades --no-install-recommends \
            kde-plasma-desktop kubuntu-settings-desktop kubuntu-wallpapers breeze-icon-theme \
            pipewire pipewire-alsa pipewire-pulse wireplumber powerdevil kscreen plasma-pa ark kwin-x11 kwin-wayland upower konsole \
            dolphin kate kinfocenter mesa-utils pulseaudio-utils vulkan-tools dbus-user-session aha clinfo dmidecode libdisplay-info-bin wayland-utils xserver-xorg \
            kfind plasma-systemmonitor filelight glmark2 systemsettings kde-config-screenlocker kio-extras xdg-user-dirs dolphin-plugins ffmpegthumbs kdegraphics-thumbnailers \
            kimageformat-plugins plasma-browser-integration libcanberra-pulse gstreamer1.0-plugins-base gstreamer1.0-plugins-good sound-theme-freedesktop \
            polkit-kde-agent-1 libpam-systemd libpam-modules libpam-kwallet5 language-pack-kde-zh-hans language-pack-zh-hans qt6-translations-l10n \
            fonts-noto-cjk fonts-noto-color-emoji
    fi
}

install_profile() {
    case "$ID" in
        ubuntu) install_neon_apt ;;
        *) echo "KDE Neon 不支持当前发行版：$ID" >&2; return 1 ;;
    esac
}

case "${1:-install}" in
    install) install_profile ;;
    configure-environment) configure_environment "${2:-}" ;;
    *) echo "KDE Neon profile 操作无效：$1" >&2; exit 1 ;;
esac
