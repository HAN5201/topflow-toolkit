#!/bin/sh

set -eu

ADB_BIN="${ADB_BIN:-adb}"
MODE="${1:-apply}"
REMOVE_PRIVATE_DATA="${REMOVE_PRIVATE_DATA:-0}"

[ "$MODE" = apply ] || [ "$MODE" = --check ] || {
    echo "usage: $0 [--check]" >&2
    exit 2
}

"$ADB_BIN" get-state >/dev/null
[ "$("$ADB_BIN" shell 'id -u' | tr -d '\r')" = 0 ] || {
    echo "ADB shell is not root" >&2
    exit 1
}

if [ "$MODE" = --check ]; then
    "$ADB_BIN" shell '
        echo "service=$(test -x /etc/init.d/mihomo-netns && echo present || echo absent)"
        echo "namespace=$(ip netns list 2>/dev/null | awk "{print \$1}" | grep -qx mihomo && echo present || echo absent)"
        echo "data=$(test -d /data/mihomo && echo present || echo absent)"
    '
    exit 0
fi

"$ADB_BIN" shell '
    set -eu
    [ ! -x /etc/init.d/mihomo-netns ] || /etc/init.d/mihomo-netns disable
    [ ! -x /etc/init.d/mihomo-netns ] || /etc/init.d/mihomo-netns stop
    [ ! -x /data/mihomo/remove-boot-hook.sh ] || /data/mihomo/remove-boot-hook.sh
    rm -f /etc/init.d/mihomo-netns /etc/rc.d/S99mihomo-netns /etc/rc.d/K10mihomo-netns
    rm -f /data/mihomo/mihomo /data/mihomo/mihomo.prev /data/mihomo/mihomo-netns.sh /data/mihomo/mihomo-netns-autostart.sh /data/mihomo/install-boot-hook.sh /data/mihomo/remove-boot-hook.sh
    rm -rf /data/mihomo/run /data/mihomo/state
    sync
'

if [ "$REMOVE_PRIVATE_DATA" = 1 ]; then
    "$ADB_BIN" shell 'rm -rf /data/mihomo'
else
    echo "Private configuration and provider data remain in /data/mihomo"
fi

echo "Mihomo transparent gateway removed"
