#!/bin/sh

set -eu

ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/topflow-boot-hooks.XXXXXX")"

cleanup() {
    rm -rf "$WORK"
}
trap cleanup EXIT INT TERM

sha256_file() {
    if command -v sha256sum >/dev/null; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

for component in timekeeper mwan3-tuning web-full-menu mihomo-manager; do
    rc_local="$WORK/rc.local.$component"
    original="$WORK/original.$component"

    printf '%s\n' '#!/bin/sh' 'echo vendor-startup' 'exit 0' >"$rc_local"
    cp "$rc_local" "$original"

    RC_LOCAL="$rc_local" "$ROOT/$component/install-boot-hook.sh"
    first_sha="$(sha256_file "$rc_local")"
    RC_LOCAL="$rc_local" "$ROOT/$component/install-boot-hook.sh"
    second_sha="$(sha256_file "$rc_local")"
    [ "$first_sha" = "$second_sha" ]

    case "$component" in
        timekeeper) marker='TopFlow trusted-time persistence' ;;
        mwan3-tuning) marker='TopFlow mwan3 tuning' ;;
        web-full-menu) marker='TopFlow full WebUI menu' ;;
        mihomo-manager) marker='MU5252 Mihomo manager WebUI' ;;
    esac
    [ "$(grep -c "$marker" "$rc_local")" -eq 2 ]

    RC_LOCAL="$rc_local" "$ROOT/$component/remove-boot-hook.sh"
    cmp "$rc_local" "$original"

    legacy_rc="$WORK/rc.local.legacy.$component"
    legacy_expected="$WORK/legacy-expected.$component"
    case "$component" in
        timekeeper)
            legacy_begin='# Start the MU5252 trusted-time persistence service.'
            legacy_end='# End the MU5252 trusted-time persistence service.'
            ;;
        mwan3-tuning)
            legacy_begin='# Start the MU5252 mwan3 HTTPS sticky rule fix.'
            legacy_end='# End the MU5252 mwan3 HTTPS sticky rule fix.'
            ;;
        web-full-menu)
            legacy_begin='# Start the MU5252 full hidden-page WebUI menu.'
            legacy_end='# End the MU5252 full hidden-page WebUI menu.'
            ;;
        mihomo-manager)
            legacy_begin='# Start the MU5252 Mihomo manager WebUI mounts.'
            legacy_end='# End the MU5252 Mihomo manager WebUI mounts.'
            ;;
    esac
    printf '%s\n' '#!/bin/sh' 'echo vendor-startup' "$legacy_begin" \
        'echo legacy-startup' "$legacy_end" '' 'exit 0' >"$legacy_rc"
    printf '%s\n' '#!/bin/sh' 'echo vendor-startup' 'exit 0' >"$legacy_expected"

    RC_LOCAL="$legacy_rc" "$ROOT/$component/install-boot-hook.sh"
    ! grep -Fq "$legacy_begin" "$legacy_rc"
    RC_LOCAL="$legacy_rc" "$ROOT/$component/remove-boot-hook.sh"
    cmp "$legacy_rc" "$legacy_expected"
done

echo 'boot-hooks: ok'
