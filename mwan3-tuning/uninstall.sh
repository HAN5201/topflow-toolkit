#!/bin/sh

set -eu

HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
ADB_BIN="${ADB_BIN:-adb}"
MODE="${1:-apply}"
BASE=/data/local/mwan3-tuning
TARGET=/sbin/sdx75_set_mwan3.sh
HOTPLUG_TARGET=/etc/hotplug.d/iface/90-mwan3-selective-conntrack

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
    "$ADB_BIN" shell "
        test -d '$BASE'
        test -x '$BASE/sdx75_set_mwan3.stock.sh'
        echo '可以卸载；若当前为 MULTIWAN，mwan3 会短暂重启'
    "
    exit
fi

"$ADB_BIN" push "$HERE/remove-boot-hook.sh" /tmp/remove-mwan3-tuning-boot-hook.sh >/dev/null
"$ADB_BIN" shell "
    set -eu
    chmod 0755 /tmp/remove-mwan3-tuning-boot-hook.sh
    /tmp/remove-mwan3-tuning-boot-hook.sh
    rm -f /tmp/remove-mwan3-tuning-boot-hook.sh

    source=\$(awk -v target='$TARGET' '\$2 == target { print \$1; exit }' /proc/mounts)
    if [ -n \"\$source\" ]; then
        [ \"\$source\" = '$BASE/sdx75-set-mwan3-wrapper.sh' ]
        umount '$TARGET'
    fi

    if [ -L '$HOTPLUG_TARGET' ] \
        && [ \"\$(readlink '$HOTPLUG_TARGET')\" = '$BASE/90-mwan3-selective-conntrack' ]; then
        rm -f '$HOTPLUG_TARGET'
    fi

    if [ -f '$BASE/original-targets' ]; then
        original=\$(cat '$BASE/original-targets')
        if [ -n \"\$original\" ]; then
            uci set zwrt_router.multiwan.targets=\"\$original\"
        else
            uci -q delete zwrt_router.multiwan.targets
        fi
        uci commit zwrt_router
    fi

    if [ \"\$(uci -q get zwrt_router.network.opms_wan_mode)\" = MULTIWAN ]; then
        '$BASE/sdx75_set_mwan3.stock.sh'
        /etc/init.d/mwan3 restart
    fi

    rm -rf '$BASE'
    rm -rf /tmp/run/mwan3-selective-conntrack
    rm -f /tmp/mwan3-tuning.lock
    sync

    ! grep -q 'TopFlow mwan3 tuning' /etc/rc.local
    ! awk -v target='$TARGET' '\$2 == target { found=1 } END { exit !found }' /proc/mounts
"

echo "mwan3 tuning 已卸载并恢复厂商生成路径"
