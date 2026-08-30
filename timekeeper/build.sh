#!/bin/sh

set -eu

HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-$HERE/build}"
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"

mkdir -p "$OUTPUT_DIR"

docker run --rm --platform linux/arm64 \
    -e HOST_UID="$HOST_UID" \
    -e HOST_GID="$HOST_GID" \
    -v "$HERE:/src:ro" \
    -v "$OUTPUT_DIR:/out" \
    -w /src \
    alpine:3.22 \
    sh -c '
        apk add --no-cache build-base >/dev/null
        cc -Os -Wall -Wextra -Werror -o /tmp/time-genoff time-genoff.c -ldl
        strip /tmp/time-genoff
        cp /tmp/time-genoff /out/time-genoff
        chown "$HOST_UID:$HOST_GID" /out/time-genoff
        chmod 0755 /out/time-genoff
    '

file "$OUTPUT_DIR/time-genoff" | grep -Eq 'ARM aarch64|ARM64'
sha256sum "$OUTPUT_DIR/time-genoff"
