#!/bin/sh

set -u

SERVICE=/data/mihomo/mihomo-netns.sh
PIDFILE=/data/mihomo/run/mihomo.pid
NAMESPACE=mihomo
RETRY_SECONDS=15
MANUAL_STOP_FILE=/tmp/mihomo-netns-manual-stop
DHCP_ENABLED_FILE=/data/mihomo/state/dhcp-enabled

healthy() {
    [ -f "$PIDFILE" ] || return 1
    pid="$(cat "$PIDFILE" 2>/dev/null)"
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null || return 1
    ip netns list 2>/dev/null | awk '{print $1}' | grep -qx "$NAMESPACE"
}

while :; do
    if [ -f "$MANUAL_STOP_FILE" ]; then
        :
    elif ! healthy; then
        if ! "$SERVICE" start; then
            echo "mihomo netns is not ready; retrying in ${RETRY_SECONDS}s" >&2
        fi
    else
        if [ -f "$DHCP_ENABLED_FILE" ]; then
            "$SERVICE" ensure-dhcp-gateway || true
        fi
        "$SERVICE" ensure-host-rules || true
    fi
    sleep "$RETRY_SECONDS" &
    wait $!
done
