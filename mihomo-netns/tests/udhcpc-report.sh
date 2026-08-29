#!/bin/sh
# shellcheck disable=SC2154

# Minimal DHCP test hook. It reports the options supplied by the server and
# configures only the temporary test interface passed in by udhcpc.

case "${1:-}" in
    bound|renew)
        echo "dhcp_ip=${ip:-}"
        echo "dhcp_router=${router:-}"
        echo "dhcp_dns=${dns:-}"
        ip -4 addr flush dev "$interface"
        ip addr add "$ip/${subnet:-255.255.255.0}" dev "$interface"
        for gateway in ${router:-}; do
            ip route add default via "$gateway" dev "$interface"
            break
        done
        ;;
    deconfig)
        ip -4 addr flush dev "$interface"
        ;;
esac
