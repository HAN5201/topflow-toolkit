#!/bin/sh

set -eu

ADB_BIN="${ADB_BIN:-adb}"
FFMPEG_BIN="${FFMPEG_BIN:-ffmpeg}"

die() {
    echo "capture-screen: $*" >&2
    exit 1
}

usage() {
    echo "usage: $0 [output.png]"
}

[ "$#" -le 1 ] || {
    usage >&2
    exit 2
}
requested_output="${1-}"

command -v "$ADB_BIN" >/dev/null 2>&1 || die "adb not found"
command -v "$FFMPEG_BIN" >/dev/null 2>&1 || die "ffmpeg not found"
"$ADB_BIN" get-state >/dev/null 2>&1 || die "ADB device is not ready"

uid="$("$ADB_BIN" shell 'id -u' | tr -d '\r')"
[ "$uid" = 0 ] || die "root ADB is required"

pid="$("$ADB_BIN" shell 'pidof zte_topsw_devui' | tr -d '\r')"
pid_count="$(printf '%s\n' "$pid" | awk '{ print NF }')"
[ "$pid_count" -eq 1 ] || die "expected one zte_topsw_devui process"
case "$pid" in
    ''|*[!0-9]*) die "invalid UI process id" ;;
esac

mode="$("$ADB_BIN" shell 'sed -n "1p" /sys/class/drm/card0-DIN-1/modes' |
    tr -d '\r')"
width="${mode%x*}"
height="${mode#*x}"
case "$width:$height" in
    *[!0-9:]*|:|*:|:*) die "invalid DRM mode: $mode" ;;
esac

framebuffers="$("$ADB_BIN" shell     'cat /sys/kernel/debug/dri/0/framebuffer' | tr -d '\r')"
printf '%s\n' "$framebuffers" | grep -q 'format=RG16 little-endian' ||
    die "unsupported DRM pixel format"

pitch="$(printf '%s\n' "$framebuffers" | awk '
    /^[[:space:]]*pitch\[0\]=/ {
        value = $0
        sub(/.*=/, "", value)
        print value
        exit
    }
')"
case "$pitch" in
    ''|*[!0-9]*) die "invalid DRM pitch" ;;
esac

buffer_size=$((pitch * height))
[ $((buffer_size % 4096)) -eq 0 ] ||
    die "DRM buffer is not page aligned"
page_count=$((buffer_size / 4096))

framebuffer_order="$(printf '%s\n' "$framebuffers" | awk '
    /^framebuffer\[[0-9][0-9]*\]:/ {
        id = $0
        sub(/^framebuffer\[/, "", id)
        sub(/\]:.*/, "", id)
    }
    /^[[:space:]]*start=/ {
        start = $0
        sub(/.*start=/, "", start)
        print id, start
    }
' | sort -k2,2)"
framebuffer_count="$(printf '%s\n' "$framebuffer_order" |
    awk 'NF { count++ } END { print count + 0 }')"
[ "$framebuffer_count" -eq 2 ] ||
    die "expected two DRM framebuffers"

map_lines="$("$ADB_BIN" shell     "grep 'rw-s.* /dev/dri/card0' /proc/$pid/maps" | tr -d '\r')"
map_order="$(printf '%s\n' "$map_lines" | awk '
    {
        range = $1
        sub(/-.*/, "", range)
        print range
    }
' | sort)"
map_count="$(printf '%s\n' "$map_order" |
    awk 'NF { count++ } END { print count + 0 }')"
[ "$map_count" -eq "$framebuffer_count" ] ||
    die "DRM mapping count does not match framebuffer count"

current_fb() {
    "$ADB_BIN" shell 'cat /sys/kernel/debug/dri/0/state' | tr -d '\r' |
        awk '
            /^plane\[/ { in_plane = 1 }
            in_plane && /^[[:space:]]*fb=/ {
                value = $0
                sub(/.*=/, "", value)
                print value
                exit
            }
        '
}

capture_fb() {
    capture_id="$1"
    capture_index="$(printf '%s\n' "$framebuffer_order" |
        awk -v id="$capture_id" '$1 == id { print NR; exit }')"
    case "$capture_index" in
        1|2) ;;
        *) die "active framebuffer is not mapped" ;;
    esac
    capture_start="$(printf '%s\n' "$map_order" |
        sed -n "${capture_index}p")"
    capture_page=$((0x$capture_start / 4096))
    "$ADB_BIN" exec-out         "dd if=/proc/$pid/mem bs=4096 skip=$capture_page count=$page_count 2>/dev/null"         > "$raw_file"
    captured_size="$(wc -c < "$raw_file" | tr -d ' ')"
    [ "$captured_size" -eq "$buffer_size" ] ||
        die "short DRM read: $captured_size of $buffer_size bytes"
}

if [ -n "$requested_output" ]; then
    output="$requested_output"
else
    output="mu5252-screen-$(date '+%Y%m%d-%H%M%S').png"
fi
case "$output" in
    /*) ;;
    *) output="$PWD/$output" ;;
esac
[ ! -e "$output" ] || die "output already exists: $output"
[ -d "$(dirname "$output")" ] ||
    die "output directory does not exist: $(dirname "$output")"

capture_tmp="$(mktemp -d "${TMPDIR:-/tmp}/mu5252-screen.XXXXXX")"
cleanup() {
    [ ! -d "$capture_tmp" ] || rm -r -- "$capture_tmp"
}
trap cleanup EXIT HUP INT TERM
raw_file="$capture_tmp/screen.rgb565"
png_file="$capture_tmp/screen.png"

stable_fb=
attempt=1
while [ "$attempt" -le 3 ]; do
    before_fb="$(current_fb)"
    case "$before_fb" in
        ''|*[!0-9]*) die "cannot determine active framebuffer" ;;
    esac
    capture_fb "$before_fb"
    after_fb="$(current_fb)"
    if [ "$before_fb" = "$after_fb" ]; then
        stable_fb="$before_fb"
        break
    fi
    attempt=$((attempt + 1))
done
[ -n "$stable_fb" ] ||
    die "display kept flipping during capture; try again"

"$FFMPEG_BIN" -loglevel error     -f rawvideo -pixel_format rgb565le -video_size "${width}x${height}"     -i "$raw_file" -frames:v 1 -y "$png_file"
mv -- "$png_file" "$output"

echo "captured framebuffer $stable_fb (${width}x${height} RGB565)"
echo "$output"
