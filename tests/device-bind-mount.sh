#!/bin/sh

# Run on a rooted TopFlow device, not on the host. The test uses unique files
# under /data/local/tmp and /tmp and removes every temporary mount on exit.

set -eu

[ "$(id -u)" = 0 ]
[ -d /data/local/tmp ]
[ -r /proc/mounts ]
command -v stat >/dev/null

SOURCE=/data/local/tmp/topflow-bind-source.$$
OTHER=/data/local/tmp/topflow-bind-other.$$
TARGET=/tmp/topflow-bind-target.$$

mount_present() {
    awk -v target="$1" '$2 == target { found=1 } END { exit !found }' /proc/mounts
}

mount_count() {
    awk -v target="$1" '$2 == target { count++ } END { print count + 0 }' /proc/mounts
}

same_inode() {
    [ -e "$1" ] && [ -e "$2" ] || return 1
    source_inode="$(stat -c '%d:%i' "$1" 2>/dev/null)" || return 1
    target_inode="$(stat -c '%d:%i' "$2" 2>/dev/null)" || return 1
    [ "$source_inode" = "$target_inode" ]
}

mount_owned() {
    mount_present "$2" && same_inode "$1" "$2"
}

unmount_owned() {
    while mount_owned "$1" "$2"; do
        umount "$2"
    done
}

cleanup() {
    while mount_present "$TARGET"; do
        umount "$TARGET" 2>/dev/null || break
    done
    rm -f "$SOURCE" "$OTHER" "$TARGET"
}
trap cleanup EXIT HUP INT TERM

: >"$SOURCE"
: >"$OTHER"
: >"$TARGET"

mount --bind "$SOURCE" "$TARGET"
mount --bind "$SOURCE" "$TARGET"
[ "$(mount_count "$TARGET")" -eq 2 ]
mount_owned "$SOURCE" "$TARGET"
unmount_owned "$SOURCE" "$TARGET"
[ "$(mount_count "$TARGET")" -eq 0 ]

mount --bind "$OTHER" "$TARGET"
! mount_owned "$SOURCE" "$TARGET"
unmount_owned "$SOURCE" "$TARGET"
[ "$(mount_count "$TARGET")" -eq 1 ]
umount "$TARGET"

mount --bind "$OTHER" "$TARGET"
mount --bind "$SOURCE" "$TARGET"
mount_owned "$SOURCE" "$TARGET"
unmount_owned "$SOURCE" "$TARGET"
[ "$(mount_count "$TARGET")" -eq 1 ]
same_inode "$OTHER" "$TARGET"
umount "$TARGET"

mount --bind "$SOURCE" "$TARGET"
mount --bind "$OTHER" "$TARGET"
! mount_owned "$SOURCE" "$TARGET"
[ "$(mount_count "$TARGET")" -eq 2 ]

echo "device-bind-mount: ok"
