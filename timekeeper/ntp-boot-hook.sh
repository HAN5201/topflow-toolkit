#!/bin/sh
# B20 does not provide the standard /etc/init.d/rcS. Make NTP's actual
# service entry point depend on clock preparation, independent of rc.d order.
set -eu
NTP_INIT="${NTP_INIT:-/etc/init.d/zte_topsw_ntp}"
MODE="${1:-install}"
[ "$MODE" = install ] || [ "$MODE" = remove ] || exit 2
[ -f "$NTP_INIT" ]
TEMP="$NTP_INIT.timekeeper.$$"
trap 'rm -f "$TEMP"' EXIT INT TERM
awk -v mode="$MODE" '
    $0 == "    # Begin TopFlow UTC NTP prerequisite." { skip=1; next }
    $0 == "    # End TopFlow UTC NTP prerequisite." { skip=0; next }
    !skip {
        print
        if ($0 ~ /^[ \t]*start_service\(\)[ \t]*\{[ \t]*$/) {
            found++
            if (mode == "install") {
                print "    # Begin TopFlow UTC NTP prerequisite."
                print "    /data/timekeeper/timekeeper.sh prepare-clock || return 1"
                print "    # End TopFlow UTC NTP prerequisite."
            }
        }
    }
    END { if (skip || found != 1) exit 42 }
' "$NTP_INIT" >"$TEMP"
sh -n "$TEMP"
chmod 0755 "$TEMP"
mv -f "$TEMP" "$NTP_INIT"
