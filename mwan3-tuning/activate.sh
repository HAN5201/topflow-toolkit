#!/bin/sh

set -eu

BASE=/data/local/mwan3-tuning
WRAPPER="$BASE/sdx75-set-mwan3-wrapper.sh"
TARGET=/sbin/sdx75_set_mwan3.sh
HOTPLUG_SOURCE="$BASE/90-mwan3-selective-conntrack"
HOTPLUG_TARGET=/etc/hotplug.d/iface/90-mwan3-selective-conntrack

mount_present() {
    awk -v target="$1" '$2 == target { found=1 } END { exit !found }' /proc/mounts
}

same_inode() {
    [ -e "$1" ] && [ -e "$2" ] || return 1
    source_inode="$(stat -c '%d:%i' "$1" 2>/dev/null)" || return 1
    target_inode="$(stat -c '%d:%i' "$2" 2>/dev/null)" || return 1
    [ "$source_inode" = "$target_inode" ]
}

if mount_present "$TARGET"; then
    same_inode "$WRAPPER" "$TARGET" || {
        echo "$TARGET already has an unrelated bind mount" >&2
        exit 1
    }
else
    mount --bind "$WRAPPER" "$TARGET"
fi

ln -sf "$HOTPLUG_SOURCE" "$HOTPLUG_TARGET"
"$BASE/apply-rules.sh"
