#!/bin/sh

set -eu

ADB_BIN="${ADB_BIN:-adb}"
MODE="${1:-apply}"

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
        echo "service=$(test -x /etc/init.d/mihomo-manager-web && echo present || echo absent)"
        echo "data=$(test -d /data/mihomo-manager && echo present || echo absent)"
        echo "boot_hook=$(grep -q "^# Start the MU5252 Mihomo manager WebUI\.$" /etc/rc.local && echo present || echo absent)"
        echo "route=$(grep -q "#mihomo_manager" /usr/zte_web/web/js/config/ufi/U60Pro/menu.js && echo present || echo absent)"
    '
    exit 0
fi

"$ADB_BIN" shell '
    set -eu
    [ ! -x /etc/init.d/mihomo-manager-web ] || /etc/init.d/mihomo-manager-web disable
    [ ! -x /etc/init.d/mihomo-manager-web ] || /etc/init.d/mihomo-manager-web stop
    [ ! -x /data/mihomo-manager/remove-boot-hook.sh ] || /data/mihomo-manager/remove-boot-hook.sh
    rm -f /etc/init.d/mihomo-manager-web /etc/rc.d/S11mihomo-manager-web /etc/rc.d/K89mihomo-manager-web
    rm -rf /data/mihomo-manager
    /etc/init.d/rpcd restart
    sync
    [ ! -e /data/mihomo-manager ]
    ! ubus list mihomo.api >/dev/null 2>&1
'

echo "Mihomo WebUI manager removed; Mihomo and its network state were not changed"
