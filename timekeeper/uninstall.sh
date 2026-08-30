#!/bin/sh

set -eu

HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
ADB_BIN="${ADB_BIN:-adb}"
MODE="${1:-apply}"

if [ "$MODE" != apply ] && [ "$MODE" != --check ]; then
    echo "用法：$0 [--check]" >&2
    exit 2
fi

"$ADB_BIN" get-state >/dev/null
[ "$("$ADB_BIN" shell 'id -u' | tr -d '\r')" = 0 ] || {
    echo "设备端 ADB 不是 root" >&2
    exit 1
}

if [ "$MODE" = --check ]; then
    "$ADB_BIN" shell '
        [ -d /data/timekeeper ] || { echo "Timekeeper 未安装"; exit 1; }
        [ -f /etc/rc.local ] || { echo "缺少 /etc/rc.local"; exit 1; }
        echo "可以卸载；当前系统时间不会回拨"
    '
    exit
fi

"$ADB_BIN" push "$HERE/remove-boot-hook.sh" /tmp/remove-timekeeper-boot-hook.sh >/dev/null
"$ADB_BIN" shell '
    set -eu
    chmod 0755 /tmp/remove-timekeeper-boot-hook.sh
    [ ! -x /etc/init.d/timekeeper ] || /etc/init.d/timekeeper stop 2>/dev/null || true
    /tmp/remove-timekeeper-boot-hook.sh
    rm -f /tmp/remove-timekeeper-boot-hook.sh

    if [ -f /data/timekeeper/remove-ats12-on-uninstall ]; then
        rm -f /data/time/ats_12
    fi
    rm -f /etc/rc.d/S10timekeeper /etc/rc.d/K90timekeeper
    rm -f /etc/init.d/timekeeper
    rm -f /tmp/timekeeper.log /tmp/timekeeper-synced
    rmdir /tmp/timekeeper.lock 2>/dev/null || true
    rm -rf /data/timekeeper
    sync

    [ ! -e /data/timekeeper ]
    [ ! -e /etc/init.d/timekeeper ]
    ! grep -q "TopFlow trusted-time persistence" /etc/rc.local
'

echo "Timekeeper 已卸载；下次重启恢复原厂联网校时流程"
