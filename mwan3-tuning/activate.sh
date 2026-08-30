#!/bin/sh

set -eu

BASE=/data/local/mwan3-tuning
WRAPPER="$BASE/sdx75-set-mwan3-wrapper.sh"
TARGET=/sbin/sdx75_set_mwan3.sh
HOTPLUG_SOURCE="$BASE/90-mwan3-selective-conntrack"
HOTPLUG_TARGET=/etc/hotplug.d/iface/90-mwan3-selective-conntrack

current_source="$(awk -v target="$TARGET" '$2 == target { print $1; exit }' /proc/mounts)"
if [ -n "$current_source" ] && [ "$current_source" != "$WRAPPER" ]; then
    echo "$TARGET already has an unrelated bind mount" >&2
    exit 1
fi

if [ "$current_source" != "$WRAPPER" ]; then
    mount --bind "$WRAPPER" "$TARGET"
fi

ln -sf "$HOTPLUG_SOURCE" "$HOTPLUG_TARGET"
"$BASE/apply-rules.sh"
