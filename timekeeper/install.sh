#!/bin/sh

set -eu

HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
ADB_BIN="${ADB_BIN:-adb}"
DEVICE_DIR=/data/timekeeper
BINARY="${TIMEKEEPER_BINARY:-$HERE/build/time-genoff}"
STAGING="$DEVICE_DIR/.install"

for file in \
    "$BINARY" \
    "$HERE/timekeeper.sh" \
    "$HERE/timekeeper.init" \
    "$HERE/install-boot-hook.sh"; do
    [ -f "$file" ] || {
        echo "缺少安装文件：$file" >&2
        exit 1
    }
done

"$ADB_BIN" get-state >/dev/null
[ "$("$ADB_BIN" shell 'id -u' | tr -d '\r')" = 0 ] || {
    echo "设备端 ADB 不是 root" >&2
    exit 1
}

"$ADB_BIN" shell '
    test -f /usr/lib/libtime_genoff.so.1
    test -x /etc/init.d/zte_ubus_bsp_rtc.init
    command -v ubus >/dev/null
    command -v jsonfilter >/dev/null
    test -f /etc/rc.local
'

offset_existed="$("$ADB_BIN" shell '[ -e /data/time/ats_12 ] && echo 1 || echo 0' | tr -d '\r')"
marker_existed="$("$ADB_BIN" shell '[ -e /data/timekeeper/remove-ats12-on-uninstall ] && echo 1 || echo 0' | tr -d '\r')"

"$ADB_BIN" shell "rm -rf '$STAGING'; mkdir -p '$STAGING'; chmod 0700 '$STAGING'"
"$ADB_BIN" push "$BINARY" "$STAGING/time-genoff" >/dev/null
"$ADB_BIN" push "$HERE/timekeeper.sh" "$STAGING/timekeeper.sh" >/dev/null
"$ADB_BIN" push "$HERE/timekeeper.init" "$STAGING/timekeeper.init" >/dev/null
"$ADB_BIN" push "$HERE/install-boot-hook.sh" "$STAGING/install-boot-hook.sh" >/dev/null

"$ADB_BIN" shell "
    set -e
    chmod 0755 \
        '$STAGING/time-genoff' \
        '$STAGING/timekeeper.sh' \
        '$STAGING/timekeeper.init' \
        '$STAGING/install-boot-hook.sh'
    '$STAGING/time-genoff' 2>&1 | grep -q '^usage:' || [ $? -eq 2 ]
    [ ! -x /etc/init.d/timekeeper ] || /etc/init.d/timekeeper stop 2>/dev/null || true
    mv -f '$STAGING/time-genoff' '$DEVICE_DIR/time-genoff'
    mv -f '$STAGING/timekeeper.sh' '$DEVICE_DIR/timekeeper.sh'
    mv -f '$STAGING/timekeeper.init' /etc/init.d/timekeeper
    chmod 0755 \
        '$DEVICE_DIR' \
        '$DEVICE_DIR/time-genoff' \
        '$DEVICE_DIR/timekeeper.sh' \
        /etc/init.d/timekeeper
    if [ '$marker_existed' = 1 ]; then
        : >'$DEVICE_DIR/remove-ats12-on-uninstall'
        chmod 0600 '$DEVICE_DIR/remove-ats12-on-uninstall'
        rm -f '$DEVICE_DIR/claim-ats12-on-first-write'
    elif [ '$offset_existed' = 0 ]; then
        rm -f '$DEVICE_DIR/remove-ats12-on-uninstall'
        : >'$DEVICE_DIR/claim-ats12-on-first-write'
        chmod 0600 '$DEVICE_DIR/claim-ats12-on-first-write'
    else
        rm -f \
            '$DEVICE_DIR/remove-ats12-on-uninstall' \
            '$DEVICE_DIR/claim-ats12-on-first-write'
    fi
    '$STAGING/install-boot-hook.sh'
    rm -rf '$STAGING'
"

if ! "$ADB_BIN" shell "$DEVICE_DIR/timekeeper.sh sync-now"; then
    "$ADB_BIN" shell '/etc/init.d/timekeeper start'
fi
"$ADB_BIN" shell "$DEVICE_DIR/timekeeper.sh status; sync"
echo "Timekeeper 已安装"
