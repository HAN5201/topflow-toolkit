#!/bin/sh

set -eu

RC_LOCAL=/etc/rc.local
TEMP=/tmp/rc.local.mihomo-netns.$$
BEGIN_MARKER='# Start the MU5252 Mihomo namespace service.'
END_MARKER='# End the MU5252 Mihomo namespace service.'

awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
    $0 == begin { skipping=1; next }
    $0 == end { skipping=0; next }
    !skipping { print }
    END { if (skipping) exit 42 }
' "$RC_LOCAL" >"$TEMP"

cat "$TEMP" >"$RC_LOCAL"
chmod 0755 "$RC_LOCAL"
rm -f "$TEMP"
