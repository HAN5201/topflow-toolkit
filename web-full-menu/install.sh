#!/bin/sh

set -eu

HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
ADB_BIN="${ADB_BIN:-adb}"
BASE=/data/local/webui-full-menu
TEMP_ROOT="${TMPDIR:-/tmp}"
TEMP_DIR="$(mktemp -d "$TEMP_ROOT/topflow-full-menu.XXXXXX")"

cleanup() {
    case "$TEMP_DIR" in
        "$TEMP_ROOT"/topflow-full-menu.*) rm -rf "$TEMP_DIR" ;;
    esac
}
trap cleanup EXIT INT TERM

for file in \
    patch-webui.mjs \
    required-paths.txt \
    web-full-menu.init \
    install-boot-hook.sh; do
    [ -f "$HERE/$file" ] || {
        echo "缺少安装文件：$HERE/$file" >&2
        exit 1
    }
done
command -v node >/dev/null

"$ADB_BIN" get-state >/dev/null
[ "$("$ADB_BIN" shell 'id -u' | tr -d '\r')" = 0 ] || {
    echo "设备端 ADB 不是 root" >&2
    exit 1
}

"$ADB_BIN" shell '
    test -f /usr/zte_web/web/index.html
    test -f /usr/zte_web/web/js/config/ufi/U60Pro/menu.js
    test -f /usr/zte_web/web/js/router.js
    test -f /usr/zte_web/web/tmpl/auth/network_lock.html
    test -f /etc/rc.local
    command -v stat >/dev/null
'

while IFS= read -r path; do
    [ -n "$path" ] || continue
    "$ADB_BIN" shell "test -f '/usr/zte_web/web/tmpl/$path.html' && test -f '/usr/zte_web/web/js/$path.js'" || {
        echo "当前固件缺少完整页面资源：$path" >&2
        exit 1
    }
done <"$HERE/required-paths.txt"

# Unstack only this component's previous/private mounts so the patch input is
# the manager layer or stock Web root, never a stale inode from our own source.
"$ADB_BIN" shell "
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

    unmount_owned '$BASE/network_lock.html' /usr/zte_web/web/tmpl/auth/network_lock.html
    unmount_owned '$BASE/router.js' /usr/zte_web/web/js/router.js
    unmount_owned '$BASE/menu.js' /usr/zte_web/web/js/config/ufi/U60Pro/menu.js
    unmount_owned '$BASE/index.html' /usr/zte_web/web/index.html
    for target in \
        /usr/zte_web/web/tmpl/auth/network_lock.html \
        /usr/zte_web/web/js/router.js; do
        if mount_present \"\$target\"; then
            echo \"\$target already has an unrelated bind mount\" >&2
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
                echo \"\$target already has an unrelated or layered bind mount\" >&2
                exit 1
            }
        fi
    done
    [ ! -x /etc/init.d/mihomo-manager-web ] || /etc/init.d/mihomo-manager-web start
"

"$ADB_BIN" pull /usr/zte_web/web/index.html "$TEMP_DIR/index.html" >/dev/null
"$ADB_BIN" pull /usr/zte_web/web/js/config/ufi/U60Pro/menu.js "$TEMP_DIR/menu.js" >/dev/null
"$ADB_BIN" pull /usr/zte_web/web/js/router.js "$TEMP_DIR/router.js" >/dev/null
"$ADB_BIN" pull /usr/zte_web/web/tmpl/auth/network_lock.html "$TEMP_DIR/network_lock.html" >/dev/null

if "$ADB_BIN" shell '
    test -f /data/mihomo-manager/web/tmpl-auth-adm/mihomo_manager.html
    test -f /data/mihomo-manager/web/js-auth-adm/mihomo_manager.js
'; then
    MIHOMO_FLAG=--include-mihomo
else
    MIHOMO_FLAG=
fi

node "$HERE/patch-webui.mjs" \
    "$TEMP_DIR/index.html" \
    "$TEMP_DIR/menu.js" \
    "$TEMP_DIR/router.js" \
    "$TEMP_DIR/network_lock.html" \
    "$TEMP_DIR/output" \
    $MIHOMO_FLAG

"$ADB_BIN" shell "mkdir -p '$BASE/.install'; chmod 0700 '$BASE/.install'"
for file in index.html menu.js router.js network_lock.html; do
    "$ADB_BIN" push "$TEMP_DIR/output/$file" "$BASE/.install/$file" >/dev/null
done
"$ADB_BIN" push "$HERE/web-full-menu.init" /etc/init.d/web-full-menu >/dev/null
"$ADB_BIN" push "$HERE/install-boot-hook.sh" "$BASE/install-boot-hook.sh" >/dev/null

"$ADB_BIN" shell "
    set -e
    chmod 0755 /etc/init.d/web-full-menu '$BASE/install-boot-hook.sh'
    chmod 0644 '$BASE/.install/'*
    mv -f '$BASE/.install/index.html' '$BASE/index.html'
    mv -f '$BASE/.install/menu.js' '$BASE/menu.js'
    mv -f '$BASE/.install/router.js' '$BASE/router.js'
    mv -f '$BASE/.install/network_lock.html' '$BASE/network_lock.html'
    rmdir '$BASE/.install'
    /etc/init.d/web-full-menu enable
    '$BASE/install-boot-hook.sh'
    /etc/init.d/web-full-menu start
    grep -q 'Start TopFlow full menu' /usr/zte_web/web/index.html
    grep -q '#network_lock' /usr/zte_web/web/js/config/ufi/U60Pro/menu.js
    grep -q '运营商网络解锁' /usr/zte_web/web/tmpl/auth/network_lock.html
    test \"\$(stat -c '%d:%i' '$BASE/index.html')\" = \"\$(stat -c '%d:%i' /usr/zte_web/web/index.html)\"
    test \"\$(stat -c '%d:%i' '$BASE/menu.js')\" = \"\$(stat -c '%d:%i' /usr/zte_web/web/js/config/ufi/U60Pro/menu.js)\"
    test \"\$(stat -c '%d:%i' '$BASE/router.js')\" = \"\$(stat -c '%d:%i' /usr/zte_web/web/js/router.js)\"
    test \"\$(stat -c '%d:%i' '$BASE/network_lock.html')\" = \"\$(stat -c '%d:%i' /usr/zte_web/web/tmpl/auth/network_lock.html)\"
    sync
"

echo "完整 WebUI 菜单已安装；重新加载厂商后台即可查看"
