#!/bin/sh

set -eu

RC_LOCAL="${RC_LOCAL:-/etc/rc.local}"
TEMP=/tmp/rc.local.timekeeper.$$
BEGIN_MARKER='# Start the TopFlow trusted-time persistence service.'
END_MARKER='# End the TopFlow trusted-time persistence service.'
LEGACY_BEGIN_MARKER='# Start the MU5252 trusted-time persistence service.'
LEGACY_END_MARKER='# End the MU5252 trusted-time persistence service.'

cleanup() {
    rm -f "$TEMP"
}
trap cleanup EXIT INT TERM

[ -f "$RC_LOCAL" ]

awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" \
    -v legacy_begin="$LEGACY_BEGIN_MARKER" -v legacy_end="$LEGACY_END_MARKER" '
    function emit_block() {
        print begin
        print "if [ -x /etc/init.d/timekeeper ]; then"
        print "    /data/timekeeper/timekeeper.sh boot-snapshot"
        print "    /etc/init.d/timekeeper start"
        print "fi"
        print end
    }
    $0 == begin || $0 == legacy_begin { skipping=1; next }
    $0 == end || $0 == legacy_end { skipping=0; drop_blank=1; next }
    drop_blank && $0 == "" { drop_blank=0; next }
    drop_blank { drop_blank=0 }
    !skipping {
        if (!inserted && $0 == "exit 0") {
            emit_block()
            print ""
            inserted=1
        }
        print
    }
    END {
        if (skipping) exit 42
        if (!inserted) {
            print ""
            emit_block()
        }
    }
' "$RC_LOCAL" >"$TEMP"

sh -n "$TEMP"
cat "$TEMP" >"$RC_LOCAL"
chmod 0755 "$RC_LOCAL"
