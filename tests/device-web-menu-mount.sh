#!/bin/sh
# Run on a rooted device with the full-menu init file as the sole argument.
set -eu
[ "$#" -eq 1 ]
# shellcheck disable=SC1090
. "$1"
WORK=/data/local/tmp/topflow-menu-mount.$$
TARGET=/tmp/topflow-menu-target.$$
mkdir "$WORK"
cleanup() {
    while mount_present "$TARGET"; do
        umount "$TARGET" || break
    done
    rm -f "$TARGET" "$WORK/menu" "$WORK/manager" "$WORK/other"
    rmdir "$WORK"
}
trap cleanup EXIT HUP INT TERM
: >"$TARGET"
: >"$WORK/menu"
: >"$WORK/manager"
: >"$WORK/other"

# Stock, repeated start, and stop.
mount_file "$WORK/menu" "$TARGET" "$WORK/manager"
mount_file "$WORK/menu" "$TARGET" "$WORK/manager"
[ "$(awk -v t="$TARGET" '$2 == t { n++ } END { print n+0 }' /proc/mounts)" -eq 1 ]
unmount_ours "$WORK/menu" "$TARGET"
! mount_present "$TARGET"

# Manager below menu, repeated start, and restoration of the Manager layer.
mount --bind "$WORK/manager" "$TARGET"
mount_file "$WORK/menu" "$TARGET" "$WORK/manager"
mount_file "$WORK/menu" "$TARGET" "$WORK/manager"
[ "$(awk -v t="$TARGET" '$2 == t { n++ } END { print n+0 }' /proc/mounts)" -eq 2 ]
unmount_ours "$WORK/menu" "$TARGET"
same_inode "$WORK/manager" "$TARGET"
umount "$TARGET"

# An unknown owner and a stacked Manager layer must both be rejected.
mount --bind "$WORK/other" "$TARGET"
! mount_file "$WORK/menu" "$TARGET" "$WORK/manager"
same_inode "$WORK/other" "$TARGET"
mount --bind "$WORK/manager" "$TARGET"
! mount_file "$WORK/menu" "$TARGET" "$WORK/manager"
same_inode "$WORK/manager" "$TARGET"
echo 'device-web-menu-mount: ok'
