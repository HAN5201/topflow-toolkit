#!/bin/sh

set -eu

ADB_BIN="${ADB_BIN:-adb}"
DEVICE_DIR=/data/touchscreen-control-center
INIT_FILE=/etc/init.d/touchscreen-control-center

device_shell() {
    "$ADB_BIN" shell "$@"
}

"$ADB_BIN" get-state >/dev/null

if [ "${1:-}" = "--check" ]; then
    device_shell '
        echo "service_file=$(test -x /etc/init.d/touchscreen-control-center && echo present || echo absent)"
        echo "enabled=$(test -L /etc/rc.d/S60touchscreen-control-center && echo yes || echo no)"
        echo "boot_hook=$(grep -q "^# Start the MU5252 touchscreen control center\\.$" /etc/rc.local && echo present || echo absent)"
        echo "data_dir=$(test -d /data/touchscreen-control-center && echo present || echo absent)"
        pid="$(pidof zte_topsw_devui)"
        if [ -n "$pid" ] && grep -q /data/touchscreen-control-center/touchui-hook.so "/proc/$pid/maps" 2>/dev/null; then
            echo "ui=injected pid=$pid"
        else
            echo "ui=stock pid=$pid"
        fi
    '
    exit 0
fi

[ "$(device_shell 'id -u' | tr -d '\r')" = 0 ] || {
    echo "ADB shell is not root" >&2
    exit 1
}

device_shell '[ ! -x /etc/init.d/touchscreen-control-center ] || /etc/init.d/touchscreen-control-center disable'
device_shell '[ ! -x /etc/init.d/touchscreen-control-center ] || /etc/init.d/touchscreen-control-center stop'
device_shell '[ ! -x /data/touchscreen-control-center/remove-boot-hook.sh ] || /data/touchscreen-control-center/remove-boot-hook.sh'
device_shell "rm -f '$INIT_FILE'; rm -rf '$DEVICE_DIR'; rm -f /tmp/touchscreen-control-center-supervisor.pid /tmp/touchscreen-control-center-ui.log /tmp/touchui-font.log /tmp/touchui-network.log"
sleep 3
device_shell '
    pids="$(pidof zte_topsw_devui)"
    set -- $pids
    [ "$#" -eq 1 ] || exit 1
    ! grep -q touchscreen-control-center "/proc/$1/maps" 2>/dev/null
'
device_shell sync

echo "touchscreen control center removed; stock UI is running"
