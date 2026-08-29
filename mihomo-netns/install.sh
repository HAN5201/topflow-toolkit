#!/bin/sh

set -eu

HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
ADB_BIN="${ADB_BIN:-adb}"
MIHOMO_BINARY="${MIHOMO_BINARY:-}"
MIHOMO_CONFIG="${MIHOMO_CONFIG:-}"
MIHOMO_RULES_DIR="${MIHOMO_RULES_DIR:-}"
MIHOMO_COUNTRY_MMDB="${MIHOMO_COUNTRY_MMDB:-}"

[ -f "$MIHOMO_BINARY" ] || {
    echo "MIHOMO_BINARY must point to a verified Linux arm64 Mihomo binary" >&2
    exit 2
}
[ -f "$MIHOMO_CONFIG" ] || {
    echo "MIHOMO_CONFIG must point to a private Mihomo configuration" >&2
    exit 2
}
[ -z "$MIHOMO_RULES_DIR" ] || [ -d "$MIHOMO_RULES_DIR" ] || {
    echo "MIHOMO_RULES_DIR is not a directory" >&2
    exit 2
}
[ -z "$MIHOMO_COUNTRY_MMDB" ] || [ -f "$MIHOMO_COUNTRY_MMDB" ] || {
    echo "MIHOMO_COUNTRY_MMDB is not a file" >&2
    exit 2
}

"$ADB_BIN" get-state >/dev/null
[ "$("$ADB_BIN" shell 'id -u' | tr -d '\r')" = 0 ] || {
    echo "ADB shell is not root" >&2
    exit 1
}

"$ADB_BIN" shell 'rm -rf /data/mihomo/.install; mkdir -p /data/mihomo/.install /data/mihomo/run /data/mihomo/state'
"$ADB_BIN" push "$MIHOMO_BINARY" /data/mihomo/.install/mihomo >/dev/null
"$ADB_BIN" push "$MIHOMO_CONFIG" /data/mihomo/.install/config.yaml >/dev/null
"$ADB_BIN" push "$HERE/resolv.conf" /data/mihomo/.install/resolv.conf >/dev/null
if [ -n "$MIHOMO_RULES_DIR" ]; then
    "$ADB_BIN" push "$MIHOMO_RULES_DIR" /data/mihomo/.install/rules >/dev/null
fi
if [ -n "$MIHOMO_COUNTRY_MMDB" ]; then
    "$ADB_BIN" push "$MIHOMO_COUNTRY_MMDB" /data/mihomo/.install/Country.mmdb >/dev/null
fi

"$ADB_BIN" shell 'chmod 0755 /data/mihomo/.install/mihomo; chmod 0600 /data/mihomo/.install/config.yaml; cd /data/mihomo/.install; ./mihomo -v; ./mihomo -t -d .'

if "$ADB_BIN" shell 'test -x /etc/init.d/mihomo-netns' >/dev/null 2>&1; then
    SERVICE_EXISTED=1
else
    SERVICE_EXISTED=0
fi
if [ "$SERVICE_EXISTED" -eq 1 ] &&
   "$ADB_BIN" shell '/etc/init.d/mihomo-netns enabled' >/dev/null 2>&1; then
    SERVICE_WAS_ENABLED=1
else
    SERVICE_WAS_ENABLED=0
fi

"$ADB_BIN" push "$HERE/mihomo-netns.sh" /data/mihomo/mihomo-netns.sh >/dev/null
"$ADB_BIN" push "$HERE/mihomo-netns-autostart.sh" /data/mihomo/mihomo-netns-autostart.sh >/dev/null
"$ADB_BIN" push "$HERE/mihomo-netns.init" /etc/init.d/mihomo-netns >/dev/null
"$ADB_BIN" push "$HERE/install-boot-hook.sh" /data/mihomo/install-boot-hook.sh >/dev/null
"$ADB_BIN" push "$HERE/remove-boot-hook.sh" /data/mihomo/remove-boot-hook.sh >/dev/null

"$ADB_BIN" shell '
    set -eu
    [ ! -x /etc/init.d/mihomo-netns ] || /etc/init.d/mihomo-netns stop
    [ ! -f /data/mihomo/mihomo ] || cp -p /data/mihomo/mihomo /data/mihomo/mihomo.prev
    [ ! -f /data/mihomo/config.yaml ] || cp -p /data/mihomo/config.yaml /data/mihomo/config.yaml.prev
    cp /data/mihomo/.install/mihomo /data/mihomo/mihomo
    cp /data/mihomo/.install/config.yaml /data/mihomo/config.yaml
    cp /data/mihomo/.install/resolv.conf /data/mihomo/resolv.conf
    [ ! -d /data/mihomo/.install/rules ] || { rm -rf /data/mihomo/rules; cp -a /data/mihomo/.install/rules /data/mihomo/rules; }
    [ ! -f /data/mihomo/.install/Country.mmdb ] || cp /data/mihomo/.install/Country.mmdb /data/mihomo/Country.mmdb
    chmod 0755 /data/mihomo/mihomo /data/mihomo/mihomo-netns.sh /data/mihomo/mihomo-netns-autostart.sh /data/mihomo/install-boot-hook.sh /data/mihomo/remove-boot-hook.sh /etc/init.d/mihomo-netns
    chmod 0600 /data/mihomo/config.yaml
    rm -rf /data/mihomo/.install
'

"$ADB_BIN" shell '/data/mihomo/install-boot-hook.sh'

if [ "$SERVICE_WAS_ENABLED" -eq 1 ]; then
    "$ADB_BIN" shell '/etc/init.d/mihomo-netns enable; /etc/init.d/mihomo-netns restart'
elif [ "$SERVICE_EXISTED" -eq 1 ]; then
    "$ADB_BIN" shell '/etc/init.d/mihomo-netns disable; /etc/init.d/mihomo-netns stop'
else
    "$ADB_BIN" shell '/etc/init.d/mihomo-netns enable; /etc/init.d/mihomo-netns start'
fi

if [ "$SERVICE_EXISTED" -eq 0 ] || [ "$SERVICE_WAS_ENABLED" -eq 1 ]; then
    "$ADB_BIN" shell '/data/mihomo/mihomo-netns.sh status'
fi
"$ADB_BIN" shell sync
echo "Mihomo transparent gateway installed"
