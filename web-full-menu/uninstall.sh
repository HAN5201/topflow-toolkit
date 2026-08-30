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
    chmod 0755 /tmp/remove-web-full-menu-boot-hook.sh
    /tmp/remove-web-full-menu-boot-hook.sh
    rm -f /tmp/remove-web-full-menu-boot-hook.sh
    /etc/init.d/web-full-menu stop 2>/dev/null || true
    /etc/init.d/web-full-menu disable 2>/dev/null || true
    rm -f /etc/init.d/web-full-menu
    rm -rf '$BASE'
    sync
    ! grep -q 'TopFlow full WebUI menu' /etc/rc.local
"

echo "完整 WebUI 菜单已卸载，原有下层页面已恢复"
