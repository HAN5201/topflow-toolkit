#!/bin/sh

set -eu

ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/topflow-boot-hooks.XXXXXX")"

cleanup() {
    rm -rf "$WORK"
}
trap cleanup EXIT INT TERM

for component in timekeeper mwan3-tuning web-full-menu; do
    rc_local="$WORK/rc.local.$component"
    original="$WORK/original.$component"

    printf '%s\n' '#!/bin/sh' 'echo vendor-startup' 'exit 0' >"$rc_local"
    cp "$rc_local" "$original"

    RC_LOCAL="$rc_local" "$ROOT/$component/install-boot-hook.sh"
    if command -v sha256sum >/dev/null; then
        first_sha="$(sha256sum "$rc_local" | awk '{print $1}')"
    else
        first_sha="$(shasum -a 256 "$rc_local" | awk '{print $1}')"
    fi
    RC_LOCAL="$rc_local" "$ROOT/$component/install-boot-hook.sh"
    if command -v sha256sum >/dev/null; then
        second_sha="$(sha256sum "$rc_local" | awk '{print $1}')"
    else
        second_sha="$(shasum -a 256 "$rc_local" | awk '{print $1}')"
    fi
    [ "$first_sha" = "$second_sha" ]

    case "$component" in
        timekeeper) marker='TopFlow trusted-time persistence' ;;
        mwan3-tuning) marker='TopFlow mwan3 tuning' ;;
        web-full-menu) marker='TopFlow full WebUI menu' ;;
    esac
    [ "$(grep -c "$marker" "$rc_local")" -eq 2 ]

    RC_LOCAL="$rc_local" "$ROOT/$component/remove-boot-hook.sh"
    cmp "$rc_local" "$original"
done

echo 'boot-hooks: ok'
