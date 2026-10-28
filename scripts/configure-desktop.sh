#!/usr/bin/env bash
#固化启动参数
set -euo pipefail

desktop="${1:-}"
backend="${2:-}"
autostart="${3:-}"
username="${4:-}"
rootfs="${ROOTFS_DIR:-}"
templates="${START_TEMPLATES_DIR:-/tmp/droidspaces-start}"
profile_dir="${DROIDSPACES_DESKTOP_PROFILE_DIR:-/usr/local/lib/droidspaces/desktops}"
config="$rootfs/etc/droidspaces-desktop.conf"

if [[ -r "$rootfs/etc/os-release" ]]; then
    source "$rootfs/etc/os-release"
fi

configure_anland_next_runtime() {
    local bashrc="$rootfs/home/$username/.bashrc"
    local kate_source="$rootfs/usr/share/applications/org.kde.kate.desktop"
    local kate_override="$rootfs/usr/local/share/applications/org.kde.kate.desktop"
    local kate_wrapper="$rootfs/usr/local/bin/kate"

    install -d -m 0755 "$(dirname "$bashrc")" "$(dirname "$kate_wrapper")"
    touch "$bashrc"

    sed -i '/^# BEGIN droidspaces-anland-next shell environment$/,/^# END droidspaces-anland-next shell environment$/d' "$bashrc"
    cat >> "$bashrc" <<'EOF'
# BEGIN droidspaces-anland-next shell environment
if [ -r "$HOME/.anlandx-env" ]; then
    while IFS= read -r droidspaces_anland_env; do
        case "$droidspaces_anland_env" in
            ''|'#'*) ;;
            *=*) export "$droidspaces_anland_env" ;;
        esac
    done < "$HOME/.anlandx-env"
fi
if [ -r "$HOME/.anlandx" ]; then
    droidspaces_anland_display=''
    IFS= read -r droidspaces_anland_display < "$HOME/.anlandx" || true
    case "$droidspaces_anland_display" in
        :[0-9]*) export DISPLAY="$droidspaces_anland_display" ;;
    esac
fi
unset droidspaces_anland_env droidspaces_anland_display
# END droidspaces-anland-next shell environment
EOF

    if [[ -f "$kate_source" ]]; then
        install -d -m 0755 "$(dirname "$kate_override")"
        if ! awk '
            /^\[Desktop Entry\]$/ { in_main_group = 1 }
            /^\[/ && $0 != "[Desktop Entry]" { in_main_group = 0 }
            in_main_group && /^Exec=/ && !replaced {
                print "Exec=kate -b %U"
                replaced = 1
                next
            }
            { print }
            END { exit replaced ? 0 : 1 }
        ' "$kate_source" > "$kate_override"; then
            cp "$kate_source" "$kate_override"
        fi
        chmod 0644 "$kate_override"
    fi

    cat > "$kate_wrapper" <<'EOF'
#!/bin/sh
for droidspaces_kate_arg in "$@"; do
    case "$droidspaces_kate_arg" in
        -b|--block) exec /usr/bin/kate "$@" ;;
    esac
done
exec /usr/bin/kate -b "$@"
EOF
    chmod 0755 "$kate_wrapper"
}

[[ "$desktop" =~ ^(none|[a-z][a-z0-9-]*)$ ]] || { echo "无效的桌面：$desktop" >&2; exit 1; }
case "$backend" in x11|anland-wayland) ;; *) echo "无效的显示后端：$backend" >&2; exit 1 ;; esac
case "$autostart" in true|false) ;; *) echo "无效的桌面自启动值：$autostart" >&2; exit 1 ;; esac
[[ -n "$username" ]] || { echo "必须指定桌面用户名" >&2; exit 1; }

if [[ "$desktop" == none && "$backend" != x11 ]]; then
    echo "不支持的桌面与显示后端组合：$desktop/$backend" >&2
    exit 1
fi
if [[ "$desktop" == kde && "$backend" == x11 && "$ID" =~ ^(arch|archarm|archlinux)$ ]]; then
    echo "Arch Linux 不支持 KDE X11；请使用 Anland Wayland。" >&2
    exit 1
fi
if [[ "$desktop" == kde-mobile && "$backend" != anland-wayland ]]; then
    echo "不支持的桌面与显示后端组合：$desktop/$backend" >&2
    exit 1
fi
if [[ "$desktop" == gnome && "$backend" != anland-wayland ]]; then
    echo "不支持的桌面与显示后端组合：$desktop/$backend" >&2
    exit 1
fi
if [[ "$desktop" == anland-next && "$backend" != anland-wayland ]]; then
    echo "不支持的桌面与显示后端组合：$desktop/$backend" >&2
    exit 1
fi
if [[ "$desktop" =~ ^(niri|hyprland|mango|denial)$ && "$backend" != anland-wayland ]]; then
    echo "不支持的桌面与显示后端组合：$desktop/$backend" >&2
    exit 1
fi

cat > "$config" <<EOF
DESKTOP=$desktop
DISPLAY_BACKEND=$backend
EOF
chmod 0644 "$config"

# 桌面专属环境必须在 Dockerfile 完成 /etc/environment 后配置。
if [[ "$desktop" != none ]]; then
    profile="$profile_dir/$desktop.sh"
    [[ -x "$profile" ]] || { echo "桌面配置脚本不存在或不可执行：$profile" >&2; exit 1; }
    ROOTFS_DIR="$rootfs" DROIDSPACES_DESKTOP="$desktop" "$profile" configure-environment "$backend"
fi

if [[ "$desktop" == anland-next ]]; then
    configure_anland_next_runtime
fi

configure_kde_plasma_profile() {
    local user_home="$rootfs/home/$username"
    local config_dir="$user_home/.config"
    local autostart_dir="$config_dir/autostart"

    install -d -m 0755 "$config_dir" "$autostart_dir"

    # 1. KWin compositor & aesthetics: Hardware acceleration, Magic Lamp, Wobbly Windows, Blur, Translucency
    cat > "$config_dir/kwinrc" <<'EOF'
[Compositing]
AnimationSpeed=3
Backend=OpenGL
Enabled=true
GLCore=true
GLPreferBufferSwap=a
HiddenPreviews=5
MaxFPS=120
RefreshRate=120
WindowsBlockCompositing=false

[Plugins]
blurEnabled=true
contrastEnabled=false
fadedesktopEnabled=true
kwin4_effect_translucencyEnabled=true
magiclampEnabled=true
overviewEnabled=true
scaleEnabled=true
slideEnabled=true
slidingpopupsEnabled=true
windowgeometryEnabled=true
wobblywindowsEnabled=true

[Effect-Blur]
BlurStrength=4
NoiseStrength=0

[Effect-MagicLamp]
AnimationDuration=220

[Effect-WobblyWindows]
AdvancedMode=false
Drag=80
Friction=0.82
MoveFactor=15
SpringFactor=0.08
WobblyWindowsType=0

[Effect-Translucency]
ComboboxPopups=100
Dialogs=100
Inactive=92
Menus=100
MoveResize=85

[Windows]
FocusPolicy=ClickToFocus
GeometryTip=false
RollOverDesktops=true
TitlebarDoubleClickCommand=Maximize
EOF

    # 2. Breeze window decoration: smooth drop shadows, clean borders and rounded corners
    cat > "$config_dir/breezerc" <<'EOF'
[Common]
OutlineIntensity=OutlineMedium
ShadowOffset=ShadowOffsetCenter
ShadowSize=ShadowMedium
ShadowStrength=60

[Windeco]
ButtonSize=ButtonNormal
DrawBackgroundGradient=false
DrawBorderOnMaximizedWindows=false
DrawTitleBarSeparator=false
EOF

    # 3. System-wide aesthetics: Breeze Dark, fluid animation duration, sound events muted (prevents Android audio deadlock)
    cat > "$config_dir/kdeglobals" <<'EOF'
[KDE]
AnimationDurationFactor=1
ShowDeleteCommand=false
widgetStyle=Breeze

[Icons]
Theme=breeze-dark

[General]
ColorScheme=BreezeDark

[Sounds]
Enable=false
EOF

    # 4. Plasma Shell theme: Breeze Dark with translucent panels and widgets
    cat > "$config_dir/plasmarc" <<'EOF'
[Theme]
name=breeze-dark
EOF

    # 5. Resource optimization: Disable Baloo file indexer to eliminate background CPU, RAM and storage crawling
    cat > "$config_dir/baloofilerc" <<'EOF'
[Basic Settings]
Indexing-Enabled=false
EOF

    # 6. Optimize KRunner (desktop search without Baloo indexer overhead)
    cat > "$config_dir/krunnerrc" <<'EOF'
[Plugins]
baloosearchEnabled=false
EOF

    # 7. Unneeded KDED background daemon modules disabled (saves RAM and avoids wpad-detector / print errors)
    cat > "$config_dir/kded5rc" <<'EOF'
[Module-wpad-detector]
autoload=false
[Module-printmanager]
autoload=false
[Module-remotedirnotify]
autoload=false
EOF

    cat > "$config_dir/kded6rc" <<'EOF'
[Module-wpad-detector]
autoload=false
[Module-printmanager]
autoload=false
[Module-remotedirnotify]
autoload=false
EOF

    # 8. Disable background Discover update notifier
    cat > "$autostart_dir/org.kde.discover.notifier.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Discover Notifier
Exec=
Hidden=true
EOF

    chmod 0644 "$config_dir/kwinrc" "$config_dir/breezerc" "$config_dir/kdeglobals" \
               "$config_dir/plasmarc" "$config_dir/baloofilerc" "$config_dir/krunnerrc" \
               "$config_dir/kded5rc" "$config_dir/kded6rc" "$autostart_dir/org.kde.discover.notifier.desktop"
}

if [[ "$desktop" == kde || "$desktop" == kde-mobile || "$desktop" == kde-neon ]]; then
    configure_kde_plasma_profile
fi

if [[ -n "$rootfs" ]]; then
    chown -R "$username:$username" "$rootfs/home/$username" 2>/dev/null || true
else
    chown -R "$username:$username" "/home/$username" 2>/dev/null || true
fi

if [[ "$desktop" == none ]]; then
    [[ "$autostart" == false ]] || { echo "桌面为 none 时不能启用自动启动" >&2; exit 1; }
    exit 0
fi

if [[ "$autostart" == true ]]; then
    install -Dm0644 "$templates/desktop-session.service" \
        "$rootfs/etc/systemd/system/desktop-session.service"
    install -d -m 0755 "$rootfs/etc/systemd/system/multi-user.target.wants"
    ln -sfn /etc/systemd/system/desktop-session.service \
        "$rootfs/etc/systemd/system/multi-user.target.wants/desktop-session.service"
fi
