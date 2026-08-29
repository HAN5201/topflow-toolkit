#!/bin/sh

set -u

BASE=/data/mihomo
NS=mihomo
HOST_IF=mh-host
NS_IF=mh-uplink
NS_ADDR=192.168.11.11/24
NS_IP=192.168.11.11
NS_MAC=02:52:52:00:02:54
GATEWAY=192.168.11.1
BRIDGE_MARK=0x5252
BRIDGE_COMMENT=mihomo-bridge-bypass
DHCP_GATEWAY_OPTION=3,192.168.11.11
DHCP_DNS_OPTION=6,192.168.11.11
STATE_DIR="$BASE/state"
DHCP_ENABLED_FILE="$STATE_DIR/dhcp-enabled"
MANUAL_STOP_FILE=/tmp/mihomo-netns-manual-stop
PIDFILE="$BASE/run/mihomo.pid"
LOGFILE=/tmp/mihomo-netns.log
CHECK_LOG=/tmp/mihomo-netns-check.log
MIN_VALID_EPOCH=1767225600

ns_exists() {
    ip netns list 2>/dev/null | awk '{print $1}' | grep -qx "$NS"
}

process_running() {
    [ -f "$PIDFILE" ] || return 1
    pid="$(cat "$PIDFILE" 2>/dev/null)"
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

remove_host_rules() {
    while iptables -t nat -C PREROUTING \
        -m mark --mark "$BRIDGE_MARK" \
        -m comment --comment "$BRIDGE_COMMENT" \
        -j ACCEPT 2>/dev/null; do
        iptables -t nat -D PREROUTING \
            -m mark --mark "$BRIDGE_MARK" \
            -m comment --comment "$BRIDGE_COMMENT" \
            -j ACCEPT 2>/dev/null || break
    done

    while ebtables -t broute -D BROUTING \
        -d "$NS_MAC" \
        -j mark --mark-set "$BRIDGE_MARK" --mark-target CONTINUE \
        2>/dev/null; do :; done
}

ensure_host_rules() {
    if ! ebtables -t broute -L BROUTING --Lc 2>/dev/null \
        | grep -Fq -- "-d $NS_MAC -j mark --mark-set $BRIDGE_MARK --mark-target CONTINUE"; then
        ebtables -t broute -I BROUTING 1 \
            -d "$NS_MAC" \
            -j mark --mark-set "$BRIDGE_MARK" --mark-target CONTINUE
    fi

    first_rule="$(iptables -t nat -S PREROUTING 2>/dev/null | sed -n '2p')"
    case "$first_rule" in
        *"--mark $BRIDGE_MARK"*"--comment $BRIDGE_COMMENT"*"-j ACCEPT")
            ;;
        *)
            while iptables -t nat -C PREROUTING \
                -m mark --mark "$BRIDGE_MARK" \
                -m comment --comment "$BRIDGE_COMMENT" \
                -j ACCEPT 2>/dev/null; do
                iptables -t nat -D PREROUTING \
                    -m mark --mark "$BRIDGE_MARK" \
                    -m comment --comment "$BRIDGE_COMMENT" \
                    -j ACCEPT 2>/dev/null || break
            done
            iptables -t nat -I PREROUTING 1 \
                -m mark --mark "$BRIDGE_MARK" \
                -m comment --comment "$BRIDGE_COMMENT" \
                -j ACCEPT
            ;;
    esac
}

ensure_dhcp_gateway() {
    dhcp_options=" $(uci -q get dhcp.lan.dhcp_option 2>/dev/null || true) "
    dhcp_complete=1
    case "$dhcp_options" in
        *" $DHCP_GATEWAY_OPTION "*) ;;
        *) dhcp_complete=0 ;;
    esac
    case "$dhcp_options" in
        *" $DHCP_DNS_OPTION "*) ;;
        *) dhcp_complete=0 ;;
    esac
    [ "${dhcp_complete:-1}" -eq 1 ] && return 0

    reconnect_macs="$(list_dhcp_wifi_clients)"
    uci -q del_list dhcp.lan.dhcp_option="$DHCP_GATEWAY_OPTION" 2>/dev/null || true
    uci -q del_list dhcp.lan.dhcp_option="$DHCP_DNS_OPTION" 2>/dev/null || true
    uci add_list dhcp.lan.dhcp_option="$DHCP_GATEWAY_OPTION"
    uci add_list dhcp.lan.dhcp_option="$DHCP_DNS_OPTION"
    uci commit dhcp
    if ! /etc/init.d/dnsmasq restart; then
        echo "重启 DHCP 服务失败" >&2
        return 1
    fi
    schedule_dhcp_wifi_reconnect "$reconnect_macs"
    echo "DHCP IPv4 gateway and DNS set to $NS_IP"
}

dhcp_gateway_desired() {
    [ -f "$DHCP_ENABLED_FILE" ]
}

disable_dhcp_gateway() {
    dhcp_options=" $(uci -q get dhcp.lan.dhcp_option 2>/dev/null || true) "
    if printf '%s' "$dhcp_options" | grep -Fq " $DHCP_GATEWAY_OPTION " \
        || printf '%s' "$dhcp_options" | grep -Fq " $DHCP_DNS_OPTION "; then
            reconnect_macs="$(list_dhcp_wifi_clients)"
            uci -q del_list dhcp.lan.dhcp_option="$DHCP_GATEWAY_OPTION" 2>/dev/null || true
            uci -q del_list dhcp.lan.dhcp_option="$DHCP_DNS_OPTION" 2>/dev/null || true
            uci commit dhcp
            if ! /etc/init.d/dnsmasq restart; then
                echo "重启 DHCP 服务失败" >&2
                return 1
            fi
            schedule_dhcp_wifi_reconnect "$reconnect_macs"
            echo "DHCP IPv4 gateway and DNS restored to device defaults"
    fi
}

list_dhcp_wifi_clients() {
    lease_macs="$(awk '{print tolower($2)}' /tmp/dhcp.leases 2>/dev/null)"
    [ -n "$lease_macs" ] || return 0
    wifi_macs="$(
        ubus call zwrt_router.api router_wireless_access_list \
            '{"start_id":1,"end_id":64}' 2>/dev/null \
            | jsonfilter -e '@.wireless_access_list_info[*].mac_address' 2>/dev/null
    )"
    for mac in $wifi_macs; do
        lower_mac="$(printf '%s' "$mac" | tr 'A-F' 'a-f')"
        printf '%s' "$lower_mac" | grep -Eq '^([0-9a-f]{2}:){5}[0-9a-f]{2}$' || continue
        printf '%s\n' "$lease_macs" | grep -qx "$lower_mac" && printf '%s\n' "$lower_mac"
    done
}

schedule_dhcp_wifi_reconnect() {
    reconnect_macs="$1"
    [ -n "$reconnect_macs" ] || return 0
    reconnect_count=0
    for mac in $reconnect_macs; do
        reconnect_count=$((reconnect_count + 1))
    done
    echo "将在 3 秒后让 $reconnect_count 个 DHCP Wi-Fi 客户端重新连接"
    (
        sleep 3
        kicked=0
        for mac in $reconnect_macs; do
            if ubus call zwrt_wlan kick_macs "{\"macs\":\"$mac\"}" >/dev/null 2>&1; then
                kicked=$((kicked + 1))
            fi
        done
        echo "已触发 $kicked 个 DHCP Wi-Fi 客户端重新连接"
    ) </dev/null >>/tmp/mihomo-netns.log 2>&1 &
}

stop_runtime() {
    remove_host_rules

    if ns_exists; then
        for pid in $(ip netns pids "$NS" 2>/dev/null); do
            kill "$pid" 2>/dev/null || true
        done
        sleep 1
        for pid in $(ip netns pids "$NS" 2>/dev/null); do
            kill -9 "$pid" 2>/dev/null || true
        done
        ip netns delete "$NS" 2>/dev/null || true
    fi

    ip link delete "$HOST_IF" 2>/dev/null || true
    ip neigh delete "$NS_IP" dev br-lan 2>/dev/null || true
    rm -f "$PIDFILE"
    rm -f "/etc/netns/$NS/resolv.conf"
    rmdir "/etc/netns/$NS" 2>/dev/null || true
}

stop_service() {
    mkdir -p "$STATE_DIR"
    : >"$MANUAL_STOP_FILE"
    stop_runtime
    disable_dhcp_gateway
}

start_service() {
    mkdir -p "$STATE_DIR"
    rm -f "$MANUAL_STOP_FILE"

    if process_running && ns_exists; then
        ensure_host_rules
        if dhcp_gateway_desired; then
            ensure_dhcp_gateway
        fi
        echo "mihomo netns is already running"
        return 0
    fi

    now_epoch="$(date +%s 2>/dev/null || echo 0)"
    if [ "$now_epoch" -lt "$MIN_VALID_EPOCH" ]; then
        echo "system clock is not trustworthy yet; wait for time recovery or network synchronization" >&2
        return 1
    fi

    stop_runtime
    mkdir -p "$BASE/run" "/etc/netns/$NS"
    cp "$BASE/resolv.conf" "/etc/netns/$NS/resolv.conf"
    ip neigh delete "$NS_IP" dev br-lan 2>/dev/null || true

    ip netns add "$NS"
    ip link add "$HOST_IF" type veth peer name "$NS_IF"
    ip link set "$HOST_IF" master br-lan
    ip link set "$HOST_IF" up
    ip link set "$NS_IF" netns "$NS"

    ip netns exec "$NS" ip link set lo up
    ip netns exec "$NS" ip link set "$NS_IF" address "$NS_MAC"
    ip netns exec "$NS" ip link set "$NS_IF" up
    ip netns exec "$NS" ip addr add "$NS_ADDR" dev "$NS_IF"
    ip netns exec "$NS" ip route add default via "$GATEWAY" dev "$NS_IF"
    ip netns exec "$NS" sysctl -qw net.ipv4.ip_forward=1
    ip netns exec "$NS" sysctl -qw net.ipv4.conf.all.rp_filter=0
    ip netns exec "$NS" sysctl -qw net.ipv4.conf.default.rp_filter=0
    ensure_host_rules

    if ! ip netns exec "$NS" ping -c 1 -W 2 "$GATEWAY" >/dev/null 2>&1; then
        echo "namespace cannot reach gateway $GATEWAY" >&2
        stop_runtime
        return 1
    fi

    if ! ip netns exec "$NS" "$BASE/mihomo" -t -d "$BASE" -f "$BASE/config.yaml" >"$CHECK_LOG" 2>&1; then
        echo "mihomo configuration check failed; see $CHECK_LOG" >&2
        stop_runtime
        return 1
    fi

    ip netns exec "$NS" sh -c "cd '$BASE' && nohup '$BASE/mihomo' -d '$BASE' -f '$BASE/config.yaml' >>'$LOGFILE' 2>&1 & echo \$! >'$PIDFILE'"
    sleep 2

    if ! process_running; then
        echo "mihomo failed to stay running; see $LOGFILE" >&2
        stop_runtime
        return 1
    fi

    if dhcp_gateway_desired; then
        ensure_dhcp_gateway
    fi

    echo "mihomo netns started at $NS_IP:7890"
}

status_service() {
    if ns_exists; then
        echo "namespace=present"
        ip netns exec "$NS" ip -brief addr show "$NS_IF" 2>/dev/null || true
        ip netns exec "$NS" ip -brief addr show mihomo0 2>/dev/null || true
        ip netns exec "$NS" ip route show 2>/dev/null || true
    else
        echo "namespace=absent"
    fi

    if process_running; then
        echo "process=running pid=$(cat "$PIDFILE")"
    else
        echo "process=stopped"
    fi

    if ns_exists; then
        ip netns exec "$NS" netstat -lnt 2>/dev/null | grep -E '(:7890|:9090|:7874)' || true
    fi
}

case "${1:-status}" in
    start)
        start_service
        ;;
    stop)
        stop_service
        echo "mihomo netns stopped"
        ;;
    restart)
        stop_runtime
        start_service
        ;;
    status)
        status_service
        ;;
    ensure-host-rules)
        if ns_exists && process_running; then
            ensure_host_rules
        else
            exit 1
        fi
        ;;
    ensure-dhcp-gateway)
        ensure_dhcp_gateway
        ;;
    enable-dhcp-gateway)
        mkdir -p "$STATE_DIR"
        : >"$DHCP_ENABLED_FILE"
        ensure_dhcp_gateway
        ;;
    disable-dhcp-gateway)
        rm -f "$DHCP_ENABLED_FILE"
        disable_dhcp_gateway
        ;;
    *)
        echo "usage: $0 {start|stop|restart|status|ensure-host-rules|ensure-dhcp-gateway|enable-dhcp-gateway|disable-dhcp-gateway}" >&2
        exit 2
        ;;
esac
