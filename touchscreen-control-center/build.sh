#!/bin/sh

set -eu

HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
CC="${CC:-aarch64-linux-musl-gcc}"

command -v "$CC" >/dev/null 2>&1 || {
    echo "cross compiler not found: $CC" >&2
    echo "set CC to an AArch64 musl compiler" >&2
    exit 1
}

"$CC" -shared -fPIC -Os -Wall -Wextra -Werror \
    -Wl,-soname,touchui-hook.so \
    -o "$HERE/touchui-hook.so" "$HERE/touchui-hook.c" -ldl -pthread

file "$HERE/touchui-hook.so"
