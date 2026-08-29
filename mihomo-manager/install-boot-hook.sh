#!/bin/sh

set -eu

RC_LOCAL=/etc/rc.local
TEMP=/tmp/rc.local.mihomo-manager.$$
BEGIN_MARKER='# Start the MU5252 Mihomo manager WebUI.'
END_MARKER='# End the MU5252 Mihomo manager WebUI.'

awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
    function emit_block() {
        print begin
        print "if [ -x /etc/init.d/mihomo-manager-web ]; then"
        print "    /etc/init.d/mihomo-manager-web boot"
        print "fi"
        print end
    }
    $0 == begin { skipping=1; next }
    $0 == end { skipping=0; next }
    !skipping {
        if (!inserted && $0 == "exit 0") {
            emit_block()
            print ""
            inserted=1
        }
        print
    }
    END {
        if (!inserted) {
            print ""
            emit_block()
        }
    }
' "$RC_LOCAL" >"$TEMP"

cat "$TEMP" >"$RC_LOCAL"
chmod 0755 "$RC_LOCAL"
rm -f "$TEMP"
