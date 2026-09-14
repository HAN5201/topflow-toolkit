#!/bin/sh

set -u

BASE=/data/timekeeper
HELPER="$BASE/time-genoff"
RTC_INIT=/etc/init.d/zte_ubus_bsp_rtc.init
RTC_PROCESS=zte_ubus_bsp_rtc
LOCK_DIR=/tmp/timekeeper.lock
LOG_FILE=/tmp/timekeeper.log
SYNC_MARKER=/tmp/timekeeper-synced
TZ_BACKUP="$BASE/timezone-original"
TZ_MANAGED="$BASE/timezone-managed"
MIN_TRUSTED_EPOCH=1767225600
MAX_TRUSTED_EPOCH=4102444800
RTC_RESTORE=0

log_message() {
    if [ -f "$LOG_FILE" ] && [ "$(wc -c <"$LOG_FILE")" -gt 65536 ]; then
        mv "$LOG_FILE" "$LOG_FILE.1"
    fi
    printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)" "$*" >>"$LOG_FILE"
}

# Vendor offsets use ISO signs; POSIX TZ uses the opposite sign. Do not guess
# DST rules or network-selected zones from a saved fixed offset.
configured_timezone() {
    [ "$(uci -q get zwrt_zte_sntp.settings.dst_enable)" = 0 ] || return 1
    [ "$(uci -q get zwrt_zte_sntp.settings.auto_tz_dst_switch)" = 0 ] || return 1
    uci -q get zwrt_zte_sntp.settings.timezone | awk '
        /^[+-]?[0-9]+([.][0-9]+)?$/ {
            hours = $0 + 0; minutes = hours * 60
            if (hours < -12 || hours > 14 || minutes != int(minutes)) exit 1
            if (minutes == 480) { print "CST-8"; found=1; exit }
            sign = minutes < 0 ? "+" : "-"
            if (minutes < 0) minutes = -minutes
            printf "UTC%s%d:%02d\n", sign, int(minutes / 60), minutes % 60
            found=1
        }
        END { if (!found) exit 1 }
    '
}

# TZif v2, one fixed local-time type, no transitions/leaps, POSIX footer.
# B20 musl reads /etc/localtime but does not use the vendor /etc/TZ text.
# Layout: https://man7.org/linux/man-pages/man5/tzfile.5.html
write_timezone_file() (
    tz="$1"
    seconds="$(printf '%s\n' "$tz" | awk '{
        sign=substr($0,4,1); split(substr($0,5), parts, ":")
        value=(parts[1]*60+parts[2])*60
        print sign == "-" ? value : -value
    }')"
    label="$(printf '%s' "$tz" | cut -c1-3)"
    for _block in 1 2; do
        printf 'TZif2'
        padding=0
        while [ "$padding" -lt 31 ]; do
            printf '\000'
            padding=$((padding + 1))
        done
        printf '\000\000\000\001\000\000\000\004'
        for shift in 24 16 8 0; do
            byte=$(((seconds >> shift) & 255))
            printf '%b' "\\0$(printf '%03o' "$byte")"
        done
        printf '\000\000%s\000' "$label"
    done
    printf '\n%s\n' "$tz"
)

apply_timezone() (
    if [ "$(uci -q get zwrt_zte_sntp.settings.dst_enable)" = 1 ] \
        || [ "$(uci -q get zwrt_zte_sntp.settings.auto_tz_dst_switch)" = 1 ]; then
        [ "$(readlink /etc/localtime)" != "$BASE/localtime" ] || restore_timezone
        return
    fi
    desired="$(configured_timezone)" || return 1
    [ "$(readlink /etc/TZ)" = /tmp/TZ ] || return 1
    localtime_link="$(readlink /etc/localtime)"
    [ "$localtime_link" = /tmp/localtime ] || [ "$localtime_link" = "$BASE/localtime" ] || return 1
    current="$(uci -q get system.@system[0].timezone || true)"
    zone="$(uci -q get system.@system[0].zonename || true)"
    if [ "$current" != "$desired" ] || [ -n "$zone" ]; then
        # Never commit unrelated pending UCI edits.
        [ -z "$(uci changes system)" ] || return 1
        if [ ! -d "$TZ_BACKUP" ]; then
            mkdir -m 0700 "$TZ_BACKUP.new" || return 1
            for key in timezone zonename; do
                if uci -q get "system.@system[0].$key" >"$TZ_BACKUP.new/$key"; then
                    touch "$TZ_BACKUP.new/$key.present"
                fi
            done
            mv "$TZ_BACKUP.new" "$TZ_BACKUP" || return 1
        fi
        uci set "system.@system[0].timezone=$desired" || return 1
        uci -q delete system.@system[0].zonename || true
        uci commit system || return 1
        printf '%s\n' "$desired" >"$TZ_MANAGED"
    fi
    if [ ! -f "$BASE/localtime" ] || [ "$(cat "$BASE/localtime-zone" 2>/dev/null)" != "$desired" ]; then
        write_timezone_file "$desired" >"$BASE/localtime.new" || return 1
        chmod 0644 "$BASE/localtime.new"
        mv "$BASE/localtime.new" "$BASE/localtime" || return 1
        printf '%s\n' "$desired" >"$BASE/localtime-zone"
    fi
    if [ "$localtime_link" != "$BASE/localtime" ]; then
        ln -sf "$BASE/localtime" /etc/localtime || return 1
        log_message "installed libc timezone file: $desired"
    fi
    if [ "$(cat /tmp/TZ 2>/dev/null)" != "$desired" ] || [ -e /tmp/localtime ] || [ -L /tmp/localtime ]; then
        printf '%s\n' "$desired" >/tmp/TZ.timekeeper
        mv /tmp/TZ.timekeeper /tmp/TZ || return 1
        rm -f /tmp/localtime
        log_message "applied saved vendor timezone: $desired"
    fi
)

restore_timezone() (
    [ -z "$(uci changes system)" ] || return 1
    if [ -f "$TZ_MANAGED" ] && [ -d "$TZ_BACKUP" ] \
        && [ "$(uci -q get system.@system[0].timezone)" = "$(cat "$TZ_MANAGED")" ] \
        && [ -z "$(uci -q get system.@system[0].zonename)" ]; then
        for key in timezone zonename; do
            if [ -f "$TZ_BACKUP/$key.present" ]; then
                uci set "system.@system[0].$key=$(cat "$TZ_BACKUP/$key")" || return 1
            else
                uci -q delete "system.@system[0].$key" || true
            fi
        done
        uci commit system || return 1
    fi
    [ "$(readlink /etc/localtime)" = "$BASE/localtime" ] || return 0
    ln -sf /tmp/localtime /etc/localtime || return 1
    timezone="$(uci -q get system.@system[0].timezone || echo UTC)"
    zone="$(uci -q get system.@system[0].zonename || true)"
    printf '%s\n' "$timezone" >/tmp/TZ
    rm -f /tmp/localtime
    if [ -n "$zone" ] && [ -f "/usr/share/zoneinfo/$zone" ]; then
        ln -s "/usr/share/zoneinfo/$zone" /tmp/localtime
        rm -f /tmp/TZ
    fi
)

trusted_clock() {
    now="$(date +%s 2>/dev/null || echo 0)"
    case "$now" in
        ''|*[!0-9]*) return 1 ;;
    esac
    [ "$now" -ge "$MIN_TRUSTED_EPOCH" ] && [ "$now" -le "$MAX_TRUSTED_EPOCH" ]
}

sntp_synced() {
    ubus call zwrt_sntp get_sync_state '{}' 2>/dev/null \
        | jsonfilter -e '@.sntp_syn_done' 2>/dev/null \
        | grep -qx 1
}

rtc_service_running() {
    [ -n "$(pidof "$RTC_PROCESS" 2>/dev/null || true)" ]
}

restore_rtc_service() {
    if [ "$RTC_RESTORE" -eq 1 ] && ! rtc_service_running; then
        "$RTC_INIT" start >>"$LOG_FILE" 2>&1 || return 1
        attempts=0
        while ! rtc_service_running && [ "$attempts" -lt 10 ]; do
            attempts=$((attempts + 1))
            sleep 1
        done
        rtc_service_running || return 1
    fi
    RTC_RESTORE=0
}

cleanup_sync() {
    restore_rtc_service || log_message "failed to restore vendor RTC service"
    rmdir "$LOCK_DIR" 2>/dev/null || true
}

release_rtc_service() {
    RTC_RESTORE=0
    if rtc_service_running; then
        RTC_RESTORE=1
        "$RTC_INIT" stop >>"$LOG_FILE" 2>&1 || return 1
        attempts=0
        while rtc_service_running && [ "$attempts" -lt 10 ]; do
            attempts=$((attempts + 1))
            sleep 1
        done
        rtc_service_running && return 1
    fi
    return 0
}

sync_now() (
    sntp_synced || {
        log_message "SNTP has not completed; persistent time was not changed"
        return 1
    }
    trusted_clock || {
        log_message "system clock is outside the trusted range"
        return 1
    }
    mkdir "$LOCK_DIR" 2>/dev/null || {
        log_message "another time persistence operation is running"
        return 1
    }
    trap cleanup_sync EXIT
    trap 'exit 1' HUP INT TERM

    if ! release_rtc_service; then
        log_message "could not release /dev/rtc0 from the vendor RTC service"
        return 1
    fi

    epoch="$(date +%s)"
    if ! "$HELPER" set "$epoch" >>"$LOG_FILE" 2>&1; then
        log_message "time_genoff SET failed"
        return 1
    fi
    readback="$($HELPER get 2>>"$LOG_FILE" \
        | sed -n 's/^base=12 epoch=//p' | tail -n 1)"
    case "$readback" in
        ''|*[!0-9]*)
            log_message "time_genoff readback was invalid"
            return 1
            ;;
    esac
    delta=$((readback - epoch))
    [ "$delta" -lt 0 ] && delta=$((-delta))
    if [ "$delta" -gt 5 ]; then
        log_message "time_genoff readback differed by ${delta}s"
        return 1
    fi

    sync
    if [ -f "$BASE/claim-ats12-on-first-write" ]; then
        : >"$BASE/remove-ats12-on-uninstall"
        chmod 0600 "$BASE/remove-ats12-on-uninstall"
        rm -f "$BASE/claim-ats12-on-first-write"
    fi
    if ! restore_rtc_service; then
        log_message "trusted time was saved but the vendor RTC service did not recover"
        return 1
    fi
    printf '%s\n' "$readback" >"$SYNC_MARKER"
    log_message "saved trusted time through Qualcomm time_genoff: epoch=$readback"
    rmdir "$LOCK_DIR" 2>/dev/null || true
    return 0
)

boot_snapshot() {
    apply_timezone || log_message "could not apply saved timezone"
    boot_uptime="$(cut -d. -f1 /proc/uptime 2>/dev/null || echo unknown)"
    boot_epoch="$(date +%s 2>/dev/null || echo unknown)"
    boot_sntp="$(sntp_synced && echo yes || echo no)"
    boot_offset="$([ -f /data/time/ats_12 ] && echo present || echo absent)"
    log_message "boot snapshot: uptime=${boot_uptime}s system_epoch=$boot_epoch sntp_synced=$boot_sntp offset_file=$boot_offset"
}

watch_for_sync() {
    observed_unsynced=0
    started="$(cut -d. -f1 /proc/uptime)"
    previous_state=""
    sleep 5
    while :; do
        apply_timezone || log_message "could not apply saved timezone"
        uptime_now="$(cut -d. -f1 /proc/uptime)"
        if sntp_synced; then
            state=sntp_synced
            if { [ ! -f "$SYNC_MARKER" ] || [ "$observed_unsynced" -eq 1 ]; } \
                && { [ "$observed_unsynced" -eq 1 ] || [ "$((uptime_now - started))" -ge 60 ]; }; then
                if sync_now; then
                    observed_unsynced=0
                fi
            fi
        else
            state=waiting_for_sntp
            observed_unsynced=1
        fi
        if [ "$state" != "$previous_state" ]; then
            log_message "$state"
            previous_state="$state"
        fi
        sleep 30
    done
}

status() {
    printf 'system_epoch=%s\n' "$(date +%s 2>/dev/null || echo unknown)"
    printf 'sntp_synced=%s\n' "$(sntp_synced && echo yes || echo no)"
    printf 'offset_file=%s\n' "$([ -f /data/time/ats_12 ] && echo present || echo absent)"
    printf 'sync_marker=%s\n' "$([ -f "$SYNC_MARKER" ] && echo present || echo absent)"
    printf 'vendor_rtc_service=%s\n' "$(rtc_service_running && echo running || echo stopped)"
    printf 'local_time=%s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z %z')"
    printf 'configured_timezone=%s\n' "$(configured_timezone || echo vendor_managed)"
    printf 'effective_timezone=%s\n' "$(cat /etc/TZ 2>/dev/null || echo zoneinfo)"
    printf 'libc_timezone_file=%s\n' "$(readlink /etc/localtime)"
    printf 'last_saved_epoch=%s\n' "$(cat "$SYNC_MARKER" 2>/dev/null || echo none_this_boot)"
}

case "${1:-status}" in
    sync-now) sync_now ;;
    watch) watch_for_sync ;;
    boot-snapshot) boot_snapshot ;;
    status) status ;;
    apply-timezone) apply_timezone ;;
    restore-timezone) restore_timezone ;;
    *)
        echo "usage: $0 {sync-now|watch|boot-snapshot|status|apply-timezone|restore-timezone}" >&2
        exit 2
        ;;
esac
