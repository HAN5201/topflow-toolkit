#!/bin/sh

CONTROL_CENTER_DIR=/data/touchscreen-control-center
HOOK="$CONTROL_CENTER_DIR/touchui-hook.so"
SUPERVISOR_PID_FILE=/tmp/touchscreen-control-center-supervisor.pid
UI_LOG=/tmp/touchscreen-control-center-ui.log

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
    # Give the QPIC driver time to finish disabling the old display pipe
    # before another process attempts to claim it.
    sleep 2
}

rollback() {
    if [ -n "$SUPERVISOR_PID" ]; then
        kill "$SUPERVISOR_PID" 2>/dev/null
    fi
    rm -f "$SUPERVISOR_PID_FILE"
    stop_ui_cleanly
    /etc/init.d/zte_topsw_devui start
}

READY=0
ATTEMPT=0
while [ "$ATTEMPT" -lt 30 ]; do
    if [ -r "$HOOK" ] && [ -e /dev/input/event5 ] && [ -e /dev/dri/card0 ] && \
       [ -n "$(pidof zte_topsw_devui)" ]; then
        READY=1
        break
    fi
    ATTEMPT=$((ATTEMPT + 1))
    sleep 1
done
if [ "$READY" -ne 1 ]; then
    echo "preflight failed after ${ATTEMPT}s; keeping stock UI"
    exit 1
fi

CURRENT_PIDS="$(pidof zte_topsw_devui)"
set -- $CURRENT_PIDS
if [ "$#" -eq 1 ] && grep -q "$HOOK" "/proc/$1/maps" 2>/dev/null && \
   [ -r "$SUPERVISOR_PID_FILE" ]; then
    CURRENT_SUPERVISOR="$(cat "$SUPERVISOR_PID_FILE")"
    if kill -0 "$CURRENT_SUPERVISOR" 2>/dev/null; then
        echo "touchscreen control center already running: $1"
        exit 0
    fi
fi

if [ -r "$SUPERVISOR_PID_FILE" ]; then
    OLD_SUPERVISOR="$(cat "$SUPERVISOR_PID_FILE")"
    case "$OLD_SUPERVISOR" in
        (*[!0-9]*|'') ;;
        (*) kill "$OLD_SUPERVISOR" 2>/dev/null ;;
    esac
fi
rm -f "$SUPERVISOR_PID_FILE"

# Remove only the running procd instance.  Calling the vendor stop routine
# would also unload the Sitronix touchscreen driver.
ubus call service delete '{"name":"zte_topsw_devui"}' >/dev/null 2>&1
stop_ui_cleanly

# Keep the injected UI in the foreground of a detached supervisor.  If the UI
# ever exits, this same process immediately restores the vendor procd service.
nohup sh -c '
    env LD_PRELOAD="$1" /usr/bin/zte_topsw_devui
    /etc/init.d/zte_topsw_devui start
' sh "$HOOK" </dev/null >"$UI_LOG" 2>&1 &
SUPERVISOR_PID=$!
echo "$SUPERVISOR_PID" >"$SUPERVISOR_PID_FILE"
sleep 5

PIDS="$(pidof zte_topsw_devui)"
set -- $PIDS
UI_PID="$1"
if [ "$#" -ne 1 ] || ! kill -0 "$UI_PID" 2>/dev/null || \
   ! grep -q "$HOOK" "/proc/$UI_PID/maps" 2>/dev/null; then
    echo "injected UI failed; restoring vendor service"
    rollback
    exit 1
fi

echo "touchscreen control center running: $UI_PID (supervisor: $SUPERVISOR_PID)"
exit 0
