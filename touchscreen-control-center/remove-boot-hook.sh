#!/bin/sh

set -eu

RC_LOCAL=/etc/rc.local
TEMP=/tmp/rc.local.touchscreen-control-center.$$
BEGIN_MARKER='# Start the MU5252 touchscreen control center.'
END_MARKER='# End the MU5252 touchscreen control center.'
OLD_BEGIN_MARKER='# Start the MU5252 touchscreen Mihomo manager.'
OLD_END_MARKER='# End the MU5252 touchscreen Mihomo manager.'

awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" \
    -v old_begin="$OLD_BEGIN_MARKER" -v old_end="$OLD_END_MARKER" '
    $0 == begin || $0 == old_begin { skipping=1; next }
    $0 == end || $0 == old_end { skipping=0; next }
    !skipping { print }
' "$RC_LOCAL" >"$TEMP"

cat "$TEMP" >"$RC_LOCAL"
chmod 0755 "$RC_LOCAL"
rm -f "$TEMP"
