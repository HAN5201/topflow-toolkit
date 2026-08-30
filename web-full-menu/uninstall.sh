#!/bin/sh

set -eu

HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
ADB_BIN="${ADB_BIN:-adb}"
MODE="${1:-apply}"
BASE=/data/local/webui-full-menu

if [ "$MODE" != apply ] && [ "$MODE" != --check ]; then
    echo "用法：$0 [--check]" >&2
    exit 2
fi

"$ADB_BIN" get-state >/dev/null
[ "$("$ADB_BIN" shell 'id -u' | tr -d '\r')" = 0 ] || {
    echo "设备端 ADB 不是 root" >&2
    exit 1
}
"$ADB_BIN" shell 'command -v stat >/dev/null'

if [ "$MODE" = --check ]; then
    "$ADB_BIN" shell "
        test -d '$BASE'
        test -x /etc/init.d/web-full-menu
        echo '可以卸载；停止 bind mount 后会立即露出下层原厂或 Mihomo Manager 页面'
    "
    exit
fi

"$ADB_BIN" push "$HERE/remove-boot-hook.sh" /tmp/remove-web-full-menu-boot-hook.sh >/dev/null
"$ADB_BIN" shell "
    set -eu
    trap 'rm -f /tmp/remove-web-full-menu-boot-hook.sh' EXIT INT TERM
    mount_present() {
        awk -v target=\"\$1\" '\$2 == target { found=1 } END { exit !found }' /proc/mounts
    }
    same_inode() {
        [ -e \"\$1\" ] && [ -e \"\$2\" ] || return 1
        source_inode=\$(stat -c '%d:%i' \"\$1\" 2>/dev/null) || return 1
        target_inode=\$(stat -c '%d:%i' \"\$2\" 2>/dev/null) || return 1
        [ \"\$source_inode\" = \"\$target_inode\" ]
    }
    unmount_owned() {
        while mount_present \"\$2\" && same_inode \"\$1\" \"\$2\"; do
            umount \"\$2\"
        done
    }

    chmod 0755 /tmp/remove-web-full-menu-boot-hook.sh
    unmount_owned '$BASE/network_lock.html' /usr/zte_web/web/tmpl/auth/network_lock.html
    unmount_owned '$BASE/router.js' /usr/zte_web/web/js/router.js
    unmount_owned '$BASE/menu.js' /usr/zte_web/web/js/config/ufi/U60Pro/menu.js
    unmount_owned '$BASE/index.html' /usr/zte_web/web/index.html
    for target in \
        /usr/zte_web/web/tmpl/auth/network_lock.html \
        /usr/zte_web/web/js/router.js; do
        if mount_present \"\$target\"; then
            echo \"\$target still has an unrelated bind mount\" >&2
            exit 1
        fi
    done
    for pair in \
        '/data/mihomo-manager/web-root/menu.js:/usr/zte_web/web/js/config/ufi/U60Pro/menu.js' \
        '/data/mihomo-manager/web-root/index.html:/usr/zte_web/web/index.html'; do
        manager_source=\${pair%%:*}
        target=\${pair#*:}
        if mount_present \"\$target\"; then
            count=\$(awk -v target=\"\$target\" '\$2 == target { count++ } END { print count + 0 }' /proc/mounts)
            [ \"\$count\" -eq 1 ] && same_inode \"\$manager_source\" \"\$target\" || {
                echo \"\$target still has an unrelated or layered bind mount\" >&2
                exit 1
            }
        fi
    done
    [ ! -x /etc/init.d/mihomo-manager-web ] || /etc/init.d/mihomo-manager-web start
    /tmp/remove-web-full-menu-boot-hook.sh
    /etc/init.d/web-full-menu disable 2>/dev/null || true
    rm -f /etc/init.d/web-full-menu
    rm -rf '$BASE'
    sync
    ! grep -q 'TopFlow full WebUI menu' /etc/rc.local
"

echo "完整 WebUI 菜单已卸载，原有下层页面已恢复"
