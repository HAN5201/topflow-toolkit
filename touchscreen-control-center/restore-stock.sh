#!/bin/sh

SUPERVISOR_PID_FILE=/tmp/touchscreen-control-center-supervisor.pid

stop_ui_cleanly() {
    ATTEMPTS=0
    killall zte_topsw_devui 2>/dev/null
    while [ -n "$(pidof zte_topsw_devui)" ] && [ "$ATTEMPTS" -lt 5 ]; do
        ATTEMPTS=$((ATTEMPTS + 1))
        sleep 1
    done
    if [ -n "$(pidof zte_topsw_devui)" ]; then
        killall -9 zte_topsw_devui 2>/dev/null
        sleep 2
    fi
    sleep 2
}

if [ -r "$SUPERVISOR_PID_FILE" ]; then
    SUPERVISOR_PID="$(cat "$SUPERVISOR_PID_FILE")"
    case "$SUPERVISOR_PID" in
        (*[!0-9]*|'') ;;
        (*) kill "$SUPERVISOR_PID" 2>/dev/null ;;
    esac
fi
rm -f "$SUPERVISOR_PID_FILE"

stop_ui_cleanly
/etc/init.d/zte_topsw_devui start
# This panel can need a watchdog-assisted LCD power cycle after the new UI
# first opens DRM. Do not report success while that recovery is still pending.
sleep 7

PID="$(pidof zte_topsw_devui)"
set -- $PID
if [ "$#" -eq 1 ] && ! grep -q '/data/touchscreen-control-center/touchui-hook.so' "/proc/$1/maps" 2>/dev/null; then
    echo "stock UI restored: $1"
    exit 0
fi

echo "stock UI restore failed"
exit 1
