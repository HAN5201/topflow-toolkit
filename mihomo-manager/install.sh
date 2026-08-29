#!/bin/sh

set -eu

HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
MIHOMO_NETNS="$(CDPATH='' cd -- "$HERE/../mihomo-netns" && pwd)"
ADB_BIN="${ADB_BIN:-adb}"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mu5252-mihomo-manager.XXXXXX")"

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT INT TERM

device_shell() {
    "$ADB_BIN" shell "$@"
}

device_push() {
    "$ADB_BIN" push "$1" "$2" >/dev/null
}

"$ADB_BIN" get-state >/dev/null
[ "$(device_shell 'id -u' | tr -d '\r')" = 0 ] || {
    echo "ADB shell is not root" >&2
    exit 1
}

for file in \
    "$MIHOMO_NETNS/mihomo-netns.sh" \
    "$MIHOMO_NETNS/mihomo-netns-autostart.sh" \
    "$MIHOMO_NETNS/mihomo-netns.init"; do
    [ -f "$file" ] || { echo "missing dependency: $file" >&2; exit 1; }
done

if device_shell '/etc/init.d/mihomo-netns enabled' >/dev/null 2>&1; then
    SERVICE_WAS_ENABLED=1
else
    SERVICE_WAS_ENABLED=0
fi

device_shell '[ ! -x /etc/init.d/mihomo-manager-web ] || /etc/init.d/mihomo-manager-web stop' >/dev/null
"$ADB_BIN" pull /usr/zte_web/web/index.html "$TEMP_DIR/index.html" >/dev/null
"$ADB_BIN" pull /usr/zte_web/web/js/config/ufi/U60Pro/menu.js "$TEMP_DIR/menu.js" >/dev/null
node "$HERE/patch-webui.mjs" \
    "$TEMP_DIR/index.html" "$TEMP_DIR/menu.js" \
    "$TEMP_DIR/index.patched.html" "$TEMP_DIR/menu.patched.js"

device_shell 'mkdir -p /data/mihomo-manager/rpcd /data/mihomo-manager/acl.d /data/mihomo-manager/web/js-auth-adm /data/mihomo-manager/web/tmpl-auth-adm /data/mihomo-manager/web-root /data/mihomo/state /data/mihomo'
device_push "$HERE/mihomo-manager.sh" /data/mihomo-manager/mihomo-manager.sh
device_push "$HERE/rpcd-mihomo.api" /data/mihomo-manager/rpcd/mihomo.api
device_push "$HERE/mihomo-acl.json" /data/mihomo-manager/acl.d/mihomo.json
device_push "$HERE/web/mihomo_manager.js" /data/mihomo-manager/web/js-auth-adm/mihomo_manager.js
device_push "$HERE/web/mihomo_manager.html" /data/mihomo-manager/web/tmpl-auth-adm/mihomo_manager.html
device_push "$TEMP_DIR/index.patched.html" /data/mihomo-manager/web-root/index.html
device_push "$TEMP_DIR/menu.patched.js" /data/mihomo-manager/web-root/menu.js
device_push "$HERE/mihomo-manager-web.init" /etc/init.d/mihomo-manager-web
device_push "$HERE/install-boot-hook.sh" /data/mihomo-manager/install-boot-hook.sh
device_push "$HERE/remove-boot-hook.sh" /data/mihomo-manager/remove-boot-hook.sh
device_push "$MIHOMO_NETNS/mihomo-netns.sh" /data/mihomo/mihomo-netns.sh
device_push "$MIHOMO_NETNS/mihomo-netns-autostart.sh" /data/mihomo/mihomo-netns-autostart.sh
device_push "$MIHOMO_NETNS/mihomo-netns.init" /etc/init.d/mihomo-netns

device_shell 'chmod 0700 /data/mihomo-manager/mihomo-manager.sh; chmod 0755 /data/mihomo-manager/rpcd/mihomo.api /data/mihomo-manager/install-boot-hook.sh /data/mihomo-manager/remove-boot-hook.sh /etc/init.d/mihomo-manager-web /etc/init.d/mihomo-netns /data/mihomo/mihomo-netns.sh /data/mihomo/mihomo-netns-autostart.sh; chmod 0644 /data/mihomo-manager/acl.d/mihomo.json /data/mihomo-manager/web/js-auth-adm/mihomo_manager.js /data/mihomo-manager/web/tmpl-auth-adm/mihomo_manager.html /data/mihomo-manager/web-root/index.html /data/mihomo-manager/web-root/menu.js'
device_shell '/etc/init.d/mihomo-manager-web enable; /data/mihomo-manager/install-boot-hook.sh; /etc/init.d/mihomo-manager-web start; /etc/init.d/rpcd restart'

if [ "$SERVICE_WAS_ENABLED" -eq 1 ]; then
    device_shell '/etc/init.d/mihomo-netns enable; /etc/init.d/mihomo-netns restart'
else
    device_shell '/etc/init.d/mihomo-netns disable; /etc/init.d/mihomo-netns stop'
fi

device_shell 'ubus -v list mihomo.api >/dev/null; grep -q "#mihomo_manager" /usr/zte_web/web/index.html; grep -q "#mihomo_manager" /usr/zte_web/web/js/config/ufi/U60Pro/menu.js; sync'
echo "Mihomo WebUI manager installed: http://192.168.11.1/#mihomo_manager"
