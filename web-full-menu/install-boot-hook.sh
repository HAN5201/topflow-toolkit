#!/bin/sh

set -eu

RC_LOCAL="${RC_LOCAL:-/etc/rc.local}"
TEMP=/tmp/rc.local.web-full-menu.$$
BEGIN_MARKER='# Start the TopFlow full WebUI menu.'
END_MARKER='# End the TopFlow full WebUI menu.'
LEGACY_BEGIN_MARKER='# Start the MU5252 full hidden-page WebUI menu.'
LEGACY_END_MARKER='# End the MU5252 full hidden-page WebUI menu.'

cleanup() {
    rm -f "$TEMP"
}
trap cleanup EXIT INT TERM

awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" \
    -v legacy_begin="$LEGACY_BEGIN_MARKER" -v legacy_end="$LEGACY_END_MARKER" '
    function emit_block() {
        print begin
        print "if [ -x /etc/init.d/web-full-menu ]; then"
        print "    /etc/init.d/web-full-menu start"
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
