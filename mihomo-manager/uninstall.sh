#!/bin/sh

set -eu

ADB_BIN="${ADB_BIN:-adb}"
MODE="${1:-apply}"

[ "$MODE" = apply ] || [ "$MODE" = --check ] || {
    echo "usage: $0 [--check]" >&2
    exit 2
}

"$ADB_BIN" get-state >/dev/null
[ "$("$ADB_BIN" shell 'id -u' | tr -d '\r')" = 0 ] || {
    echo "ADB shell is not root" >&2
    exit 1
}
"$ADB_BIN" shell 'command -v stat >/dev/null'

if [ "$MODE" = --check ]; then
    "$ADB_BIN" shell '
        echo "service=$(test -x /etc/init.d/mihomo-manager-web && echo present || echo absent)"
        echo "data=$(test -d /data/mihomo-manager && echo present || echo absent)"
        echo "boot_hook=$(grep -q "^# Start the MU5252 Mihomo manager WebUI\.$" /etc/rc.local && echo present || echo absent)"
        echo "route=$(grep -q "#mihomo_manager" /usr/zte_web/web/js/config/ufi/U60Pro/menu.js && echo present || echo absent)"
        echo "full_menu=$([ -d /data/local/webui-full-menu ] || [ -x /etc/init.d/web-full-menu ] && echo present || echo absent)"
    '
    exit 0
fi

"$ADB_BIN" shell '[ ! -d /data/local/webui-full-menu ] && [ ! -x /etc/init.d/web-full-menu ]' || {
    echo "remove the full WebUI menu before uninstalling Mihomo Manager" >&2
    exit 1
}

"$ADB_BIN" shell '
    set -eu
    mount_present() {
        awk -v target="$1" '\''$2 == target { found=1 } END { exit !found }'\'' /proc/mounts
    }
    same_inode() {
        [ -e "$1" ] && [ -e "$2" ] || return 1
        source_inode=$(stat -c "%d:%i" "$1" 2>/dev/null) || return 1
        target_inode=$(stat -c "%d:%i" "$2" 2>/dev/null) || return 1
        [ "$source_inode" = "$target_inode" ]
    }
    unmount_ours() {
        while mount_present "$2" && same_inode "$1" "$2"; do
            umount "$2"
        done
    }

    unmount_ours /data/mihomo-manager/web-root/menu.js /usr/zte_web/web/js/config/ufi/U60Pro/menu.js
    unmount_ours /data/mihomo-manager/web-root/index.html /usr/zte_web/web/index.html
    unmount_ours /data/mihomo-manager/web/tmpl-auth-adm /usr/zte_web/web/tmpl/auth/adm
    unmount_ours /data/mihomo-manager/web/js-auth-adm /usr/zte_web/web/js/auth/adm
    unmount_ours /data/mihomo-manager/acl.d /usr/share/rpcd/acl.d
    unmount_ours /data/mihomo-manager/rpcd /usr/libexec/rpcd
    for target in \
        /usr/zte_web/web/js/config/ufi/U60Pro/menu.js \
        /usr/zte_web/web/index.html \
        /usr/zte_web/web/tmpl/auth/adm \
        /usr/zte_web/web/js/auth/adm \
        /usr/share/rpcd/acl.d \
        /usr/libexec/rpcd; do
        if mount_present "$target"; then
            echo "$target still has a mount; refusing to remove manager data" >&2
            exit 1
        fi
    done
    [ ! -x /data/mihomo-manager/remove-boot-hook.sh ] || /data/mihomo-manager/remove-boot-hook.sh
    rm -f /etc/init.d/mihomo-manager-web /etc/rc.d/S11mihomo-manager-web /etc/rc.d/K89mihomo-manager-web
    rm -rf /data/mihomo-manager
    /etc/init.d/rpcd restart
    sync
    [ ! -e /data/mihomo-manager ]
    ! ubus list mihomo.api >/dev/null 2>&1
'

echo "Mihomo WebUI manager removed; Mihomo and its network state were not changed"
