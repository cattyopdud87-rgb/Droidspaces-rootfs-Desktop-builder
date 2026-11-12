#!/usr/bin/env bash
# install-compat.sh - Builds and installs libdroidspaces-compat into the rootfs
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${1:-/usr/local/lib}"
PRELOAD_FILE="${2:-/etc/ld.so.preload}"

echo "[droidspaces-compat] Compiling Linux 4.14 GLib compatibility shim..."
mkdir -p "$TARGET_DIR"
gcc -O2 -Wall -Wextra -fPIC "$SCRIPT_DIR/libdroidspaces-compat.c" -shared -ldl -Wl,-s \
    -o "$TARGET_DIR/libdroidspaces-compat.so"
chmod 0755 "$TARGET_DIR/libdroidspaces-compat.so"

echo "[droidspaces-compat] Registering shim in $PRELOAD_FILE..."
mkdir -p "$(dirname "$PRELOAD_FILE")"
touch "$PRELOAD_FILE"
if ! grep -qxF "$TARGET_DIR/libdroidspaces-compat.so" "$PRELOAD_FILE"; then
    echo "$TARGET_DIR/libdroidspaces-compat.so" >> "$PRELOAD_FILE"
fi
chmod 0644 "$PRELOAD_FILE"

echo "[droidspaces-compat] Installation complete: $TARGET_DIR/libdroidspaces-compat.so"
