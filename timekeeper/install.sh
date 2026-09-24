#!/bin/sh

set -eu

HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
ADB_BIN="${ADB_BIN:-adb}"
DEVICE_DIR=/data/timekeeper
BINARY="${TIMEKEEPER_BINARY:-$HERE/build/time-genoff}"
STAGING="$DEVICE_DIR/.install"

for file in \
    "$BINARY" \
    "$HERE/build/clock-observer.so" \
    "$HERE/build/clock-event" \
    "$HERE/timekeeper.sh" \
    "$HERE/timekeeper.init" \
    "$HERE/install-boot-hook.sh" \
    "$HERE/patch-ntpclient.py" \
    "$HERE/patch-nwinfo.py" \
    "$HERE/ntp-boot-hook.sh" \
    "$HERE/nitz-boot-hook.sh"; do
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
    set -e
    test -f /usr/lib/libtime_genoff.so.1
    test -r /sbin/zte_ntp_cy.sh
    command -v sha256sum >/dev/null
    command -v nohup >/dev/null
    test -x /etc/init.d/zte_ubus_bsp_rtc.init
    command -v ubus >/dev/null
    command -v jsonfilter >/dev/null
    test -f /etc/rc.local
'

# Pull the device-owned executable privately; no vendor binary is distributed.
PATCH_TEMP="$(mktemp -d)"
trap 'rm -rf "$PATCH_TEMP"' EXIT INT TERM
"$ADB_BIN" shell '
    set -e
    [ "$(uci -q get zwrt_zte_sntp.settings.dst_enable)" = 0 ]
    [ "$(uci -q get zwrt_zte_sntp.settings.auto_tz_dst_switch)" = 0 ]
'
"$ADB_BIN" pull /usr/bin/ntpclient "$PATCH_TEMP/ntpclient" >/dev/null
python3 "$HERE/patch-ntpclient.py" "$PATCH_TEMP/ntpclient" "$PATCH_TEMP/ntpclient.utc"
"$ADB_BIN" pull /usr/bin/zte_topsw_nwinfo "$PATCH_TEMP/nwinfo" >/dev/null
python3 "$HERE/patch-nwinfo.py" "$PATCH_TEMP/nwinfo" "$PATCH_TEMP/nwinfo.utc"

offset_existed="$("$ADB_BIN" shell '[ -e /data/time/ats_12 ] && echo 1 || echo 0' | tr -d '\r')"
marker_existed="$("$ADB_BIN" shell '[ -e /data/timekeeper/remove-ats12-on-uninstall ] && echo 1 || echo 0' | tr -d '\r')"

"$ADB_BIN" shell "rm -rf '$STAGING'; mkdir -p '$STAGING'; chmod 0700 '$STAGING'"
"$ADB_BIN" push "$PATCH_TEMP/ntpclient.utc" "$STAGING/ntpclient.utc" >/dev/null
"$ADB_BIN" push "$PATCH_TEMP/nwinfo.utc" "$STAGING/nwinfo.utc" >/dev/null
"$ADB_BIN" push "$HERE/build/clock-observer.so" "$STAGING/clock-observer.so" >/dev/null
"$ADB_BIN" push "$HERE/build/clock-event" "$STAGING/clock-event" >/dev/null
"$ADB_BIN" push "$BINARY" "$STAGING/time-genoff" >/dev/null
"$ADB_BIN" push "$HERE/timekeeper.sh" "$STAGING/timekeeper.sh" >/dev/null
"$ADB_BIN" push "$HERE/timekeeper.init" "$STAGING/timekeeper.init" >/dev/null
"$ADB_BIN" push "$HERE/ntp-boot-hook.sh" "$STAGING/ntp-boot-hook.sh" >/dev/null
"$ADB_BIN" push "$HERE/nitz-boot-hook.sh" "$STAGING/nitz-boot-hook.sh" >/dev/null
"$ADB_BIN" push "$HERE/install-boot-hook.sh" "$STAGING/install-boot-hook.sh" >/dev/null

INSTALL_RESULT="$("$ADB_BIN" shell "
    set -e
    chmod 0755 \
        '$STAGING/ntpclient.utc' \
        '$STAGING/nwinfo.utc' \
        '$STAGING/clock-observer.so' \
        '$STAGING/clock-event' \
        '$STAGING/time-genoff' \
        '$STAGING/timekeeper.sh' \
        '$STAGING/timekeeper.init' \
        '$STAGING/install-boot-hook.sh'
    '$STAGING/time-genoff' 2>&1 | grep -q '^usage:' || [ $? -eq 2 ]
    [ ! -x /etc/init.d/timekeeper ] || /etc/init.d/timekeeper stop 2>/dev/null || true
    if cmp -s '$STAGING/ntpclient.utc' '$DEVICE_DIR/ntpclient.utc'; then
        rm -f '$STAGING/ntpclient.utc'
    else
        mv -f '$STAGING/ntpclient.utc' '$DEVICE_DIR/ntpclient.utc'
    fi
    if cmp -s '$STAGING/nwinfo.utc' '$DEVICE_DIR/nwinfo.utc'; then
        rm -f '$STAGING/nwinfo.utc'
    else
        mv -f '$STAGING/nwinfo.utc' '$DEVICE_DIR/nwinfo.utc'
    fi
    if cmp -s '$STAGING/clock-observer.so' '$DEVICE_DIR/clock-observer.so'; then
        rm -f '$STAGING/clock-observer.so'
    else
        mv -f '$STAGING/clock-observer.so' '$DEVICE_DIR/clock-observer.so'
    fi
    if cmp -s '$STAGING/clock-event' '$DEVICE_DIR/clock-event'; then
        rm -f '$STAGING/clock-event'
    else
        mv -f '$STAGING/clock-event' '$DEVICE_DIR/clock-event'
    fi
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
    sh '$STAGING/ntp-boot-hook.sh' install
    sh '$STAGING/nitz-boot-hook.sh' install
    /etc/init.d/timekeeper enable
    '$DEVICE_DIR/timekeeper.sh' prepare-clock
    '$DEVICE_DIR/timekeeper.sh' ensure-observer
    rm -rf '$STAGING'
    echo TIMEKEEPER_INSTALL_OK
")"
printf '%s\n' "$INSTALL_RESULT"
printf '%s\n' "$INSTALL_RESULT" | tr -d '\r' | grep -qx TIMEKEEPER_INSTALL_OK || exit 1

"$ADB_BIN" shell '/etc/init.d/timekeeper start'
"$ADB_BIN" shell "$DEVICE_DIR/timekeeper.sh status; sync"
echo "Timekeeper 已安装"
