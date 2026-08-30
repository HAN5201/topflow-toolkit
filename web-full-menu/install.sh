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
    [ ! -x /etc/init.d/web-full-menu ] || /etc/init.d/web-full-menu stop
    for target in \
        /usr/zte_web/web/tmpl/auth/network_lock.html \
        /usr/zte_web/web/js/router.js \
        /usr/zte_web/web/js/config/ufi/U60Pro/menu.js \
        /usr/zte_web/web/index.html; do
        source=\$(awk -v target=\"\$target\" '\$2 == target { source=\$1 } END { print source }' /proc/mounts)
        case \"\$source\" in
            '$BASE/'*) umount \"\$target\" ;;
        esac
    done
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
    sync
"

echo "完整 WebUI 菜单已安装；重新加载厂商后台即可查看"
