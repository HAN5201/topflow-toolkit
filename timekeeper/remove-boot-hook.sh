#!/bin/sh

set -eu

RC_LOCAL="${RC_LOCAL:-/etc/rc.local}"
TEMP=/tmp/rc.local.timekeeper.$$
BEGIN_MARKER='# Start the TopFlow trusted-time persistence service.'
END_MARKER='# End the TopFlow trusted-time persistence service.'

cleanup() {
    rm -f "$TEMP"
}
trap cleanup EXIT INT TERM

[ -f "$RC_LOCAL" ]

awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
    $0 == begin { skipping=1; next }
    $0 == end { skipping=0; drop_blank=1; next }
    drop_blank && $0 == "" { drop_blank=0; next }
    drop_blank { drop_blank=0 }
    !skipping { print }
    END { if (skipping) exit 42 }
' "$RC_LOCAL" >"$TEMP"

sh -n "$TEMP"
cat "$TEMP" >"$RC_LOCAL"
chmod 0755 "$RC_LOCAL"
