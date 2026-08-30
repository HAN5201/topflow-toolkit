#!/bin/sh

set -eu

RC_LOCAL="${RC_LOCAL:-/etc/rc.local}"
TEMP=/tmp/rc.local.mwan3-tuning.$$
BEGIN_MARKER='# Start the TopFlow mwan3 tuning.'
END_MARKER='# End the TopFlow mwan3 tuning.'
LEGACY_BEGIN_MARKER='# Start the MU5252 mwan3 HTTPS sticky rule fix.'
LEGACY_END_MARKER='# End the MU5252 mwan3 HTTPS sticky rule fix.'

cleanup() {
    rm -f "$TEMP"
}
trap cleanup EXIT INT TERM

awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" \
    -v legacy_begin="$LEGACY_BEGIN_MARKER" -v legacy_end="$LEGACY_END_MARKER" '
    $0 == begin || $0 == legacy_begin { skipping=1; next }
    $0 == end || $0 == legacy_end { skipping=0; drop_blank=1; next }
    drop_blank && $0 == "" { drop_blank=0; next }
    drop_blank { drop_blank=0 }
    !skipping { print }
    END { if (skipping) exit 42 }
' "$RC_LOCAL" >"$TEMP"

sh -n "$TEMP"
cat "$TEMP" >"$RC_LOCAL"
chmod 0755 "$RC_LOCAL"
