#!/bin/sh

set -u

BASE=/data/timekeeper
HELPER="$BASE/time-genoff"
RTC_INIT=/etc/init.d/zte_ubus_bsp_rtc.init
RTC_PROCESS=zte_ubus_bsp_rtc
LOCK_DIR=/tmp/timekeeper.lock
LOG_FILE=/tmp/timekeeper.log
SYNC_MARKER=/tmp/timekeeper-synced
MIN_TRUSTED_EPOCH=1767225600
MAX_TRUSTED_EPOCH=4102444800
RTC_RESTORE=0

log_message() {
    printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)" "$*" >>"$LOG_FILE"
}

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
    printf '%s\n' "$readback" >"$SYNC_MARKER"
    log_message "saved trusted time through Qualcomm time_genoff: epoch=$readback"

    if ! restore_rtc_service; then
        log_message "trusted time was saved but the vendor RTC service did not recover"
        return 1
    fi
    rmdir "$LOCK_DIR" 2>/dev/null || true
    return 0
)

boot_snapshot() {
    boot_uptime="$(cut -d. -f1 /proc/uptime 2>/dev/null || echo unknown)"
    boot_epoch="$(date +%s 2>/dev/null || echo unknown)"
    boot_sntp="$(sntp_synced && echo yes || echo no)"
    boot_offset="$([ -f /data/time/ats_12 ] && echo present || echo absent)"
    log_message "boot snapshot: uptime=${boot_uptime}s system_epoch=$boot_epoch sntp_synced=$boot_sntp offset_file=$boot_offset"
}

watch_for_sync() {
    rm -f "$SYNC_MARKER"
    observed_unsynced=0
    attempts=0
    sleep 5
    while [ "$attempts" -lt 300 ]; do
        attempts=$((attempts + 1))
        if sntp_synced; then
            if [ "$observed_unsynced" -eq 1 ] || [ "$attempts" -ge 30 ]; then
                if sync_now; then
                    exit 0
                fi
            fi
        else
            observed_unsynced=1
        fi
        sleep 2
    done
    log_message "timed out waiting for a trustworthy SNTP completion"
    exit 1
}

status() {
    printf 'system_epoch=%s\n' "$(date +%s 2>/dev/null || echo unknown)"
    printf 'sntp_synced=%s\n' "$(sntp_synced && echo yes || echo no)"
    printf 'offset_file=%s\n' "$([ -f /data/time/ats_12 ] && echo present || echo absent)"
    printf 'sync_marker=%s\n' "$([ -f "$SYNC_MARKER" ] && echo present || echo absent)"
    printf 'vendor_rtc_service=%s\n' "$(rtc_service_running && echo running || echo stopped)"
}

case "${1:-status}" in
    sync-now) sync_now ;;
    watch) watch_for_sync ;;
    boot-snapshot) boot_snapshot ;;
    status) status ;;
    *)
        echo "usage: $0 {sync-now|watch|boot-snapshot|status}" >&2
        exit 2
        ;;
esac
