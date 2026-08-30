#!/usr/bin/env bash
set -euo pipefail

# Host-side updater for zwrt-datad on the MU5252.
# It intentionally never performs unattended updates: use `check`, then
# explicitly run `update` after reviewing the release.

REPO="${ZWRT_DATAD_REPO:-33333s/zwrt-datad}"
ASSET_NAME="${ZWRT_DATAD_ASSET:-zwrt-datad-aarch64}"
REMOTE_DIR="${ZWRT_DATAD_DIR:-/data/zwrt-datad}"
REMOTE_BIN="$REMOTE_DIR/zwrt-datad"
REMOTE_SERVICE="$REMOTE_DIR/service.sh"
REMOTE_RELEASE="$REMOTE_DIR/installed-release"
REMOTE_RELEASE_PREV="$REMOTE_DIR/installed-release.prev"
REMOTE_RELEASE_FAILED="$REMOTE_DIR/installed-release.failed"
REMOTE_PREV="$REMOTE_DIR/zwrt-datad.prev"
REMOTE_FAILED="$REMOTE_DIR/zwrt-datad.failed"

ADB_BIN="${ADB_BIN:-$(command -v adb || true)}"
CURL_BIN="${CURL_BIN:-$(command -v curl || true)}"
PYTHON_BIN="${PYTHON_BIN:-$(command -v python3 || true)}"
SERIAL="${ADB_SERIAL:-}"
TMP_ROOT="${TMPDIR:-/tmp}"
TMP_DIR=""

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

log() {
    printf '%s\n' "$*"
}

cleanup() {
    if [ -n "$TMP_DIR" ]; then
        case "$TMP_DIR" in
            "$TMP_ROOT"/zwrt-datad-update.*)
                rm -rf -- "$TMP_DIR"
                ;;
        esac
    fi
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT TERM

require_tools() {
    [ -n "$ADB_BIN" ] && [ -x "$ADB_BIN" ] || die "adb not found"
    [ -n "$CURL_BIN" ] && [ -x "$CURL_BIN" ] || die "curl not found"
    [ -n "$PYTHON_BIN" ] && [ -x "$PYTHON_BIN" ] || die "python3 not found"
    command -v shasum >/dev/null 2>&1 || command -v sha256sum >/dev/null 2>&1 || \
        die "shasum or sha256sum not found"
}

select_device() {
    if [ -n "$SERIAL" ]; then
        state="$($ADB_BIN -s "$SERIAL" get-state 2>/dev/null || true)"
        [ "$state" = "device" ] || die "ADB_SERIAL is not an online device"
    else
        SERIAL="$($ADB_BIN devices | awk '$2 == "device" { print $1 }')"
        count="$(printf '%s\n' "$SERIAL" | sed '/^$/d' | wc -l | tr -d ' ')"
        [ "$count" = "1" ] || die "expected exactly one online ADB device; set ADB_SERIAL explicitly"
    fi

    identity="$($ADB_BIN -s "$SERIAL" shell id 2>/dev/null | tr -d '\r')"
    case "$identity" in
        *'uid=0(root)'*) ;;
        *) die "the selected device does not provide a root ADB shell" ;;
    esac
}

adb_shell() {
    "$ADB_BIN" -s "$SERIAL" shell "$@"
}

host_sha256() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        sha256sum "$1" | awk '{print $1}'
    fi
}

remote_sha256() {
    adb_shell "sha256sum '$1' 2>/dev/null" | tr -d '\r' | awk '{print $1}'
}

prepare_temp() {
    [ -n "$TMP_DIR" ] && return 0
    TMP_DIR="$(mktemp -d "$TMP_ROOT/zwrt-datad-update.XXXXXX")"
}

fetch_latest_release() {
    prepare_temp
    release_json="$TMP_DIR/release.json"
    "$CURL_BIN" -fsSL \
        -H 'Accept: application/vnd.github+json' \
        -H 'X-GitHub-Api-Version: 2022-11-28' \
        "https://api.github.com/repos/$REPO/releases/latest" \
        -o "$release_json"

    release_lines="$($PYTHON_BIN - "$release_json" "$ASSET_NAME" <<'PY'
import json
import re
import sys

path, asset_name = sys.argv[1:]
with open(path, "r", encoding="utf-8") as fh:
    release = json.load(fh)

tag = release.get("tag_name", "")
if not re.fullmatch(r"[A-Za-z0-9._-]+", tag):
    raise SystemExit("invalid release tag")

asset = next((item for item in release.get("assets", []) if item.get("name") == asset_name), None)
if not asset:
    raise SystemExit(f"release asset not found: {asset_name}")

url = asset.get("browser_download_url", "")
expected_prefix = "https://github.com/"
if not url.startswith(expected_prefix):
    raise SystemExit("unexpected asset download host")

digest = asset.get("digest", "")
if not re.fullmatch(r"sha256:[0-9a-fA-F]{64}", digest):
    raise SystemExit("release asset has no usable GitHub SHA-256 digest")

print(tag)
print(url)
print(digest.split(":", 1)[1].lower())
PY
)"

    LATEST_TAG="$(printf '%s\n' "$release_lines" | sed -n '1p')"
    ASSET_URL="$(printf '%s\n' "$release_lines" | sed -n '2p')"
    EXPECTED_SHA="$(printf '%s\n' "$release_lines" | sed -n '3p')"
    [ -n "$LATEST_TAG" ] && [ -n "$ASSET_URL" ] && [ -n "$EXPECTED_SHA" ] || \
        die "failed to parse latest release metadata"
}

download_candidate() {
    candidate="$TMP_DIR/$ASSET_NAME"
    "$CURL_BIN" -fL --retry 3 --retry-delay 1 "$ASSET_URL" -o "$candidate"
    actual_sha="$(host_sha256 "$candidate")"
    [ "$actual_sha" = "$EXPECTED_SHA" ] || \
        die "downloaded SHA-256 does not match the GitHub release digest"
    chmod 755 "$candidate"
    CANDIDATE="$candidate"
}

health_ok() {
    attempt=0
    while [ "$attempt" -lt 10 ]; do
        response="$(adb_shell 'if command -v wget >/dev/null 2>&1; then wget -q -T 2 -O - http://127.0.0.1:9460/healthz 2>/dev/null; elif command -v curl >/dev/null 2>&1; then curl -fsS --max-time 2 http://127.0.0.1:9460/healthz 2>/dev/null; fi' | tr -d '\r' || true)"
        [ "$response" = "ok" ] && return 0
        sleep 1
        attempt=$((attempt + 1))
    done
    return 1
}

fix_permissions() {
    adb_shell "
        set -e
        chown 0:0 '$REMOTE_DIR'
        chmod 755 '$REMOTE_DIR'
        [ ! -e '$REMOTE_BIN' ] || { chown 0:0 '$REMOTE_BIN'; chmod 755 '$REMOTE_BIN'; }
        [ ! -e '$REMOTE_SERVICE' ] || { chown 0:0 '$REMOTE_SERVICE'; chmod 755 '$REMOTE_SERVICE'; }
        [ ! -e '$REMOTE_PREV' ] || { chown 0:0 '$REMOTE_PREV'; chmod 700 '$REMOTE_PREV'; }
        [ ! -e '$REMOTE_FAILED' ] || { chown 0:0 '$REMOTE_FAILED'; chmod 700 '$REMOTE_FAILED'; }
        [ ! -e '$REMOTE_DIR/auth.token' ] || { chown 0:0 '$REMOTE_DIR/auth.token'; chmod 600 '$REMOTE_DIR/auth.token'; }
        [ ! -e '$REMOTE_DIR/zwrt-datad.log' ] || { chown 0:0 '$REMOTE_DIR/zwrt-datad.log'; chmod 600 '$REMOTE_DIR/zwrt-datad.log'; }
        [ ! -e '$REMOTE_DIR/zwrt-datad.pid' ] || { chown 0:0 '$REMOTE_DIR/zwrt-datad.pid'; chmod 644 '$REMOTE_DIR/zwrt-datad.pid'; }
        [ ! -e '$REMOTE_DIR/cooling.conf' ] || { chown 0:0 '$REMOTE_DIR/cooling.conf'; chmod 600 '$REMOTE_DIR/cooling.conf'; }
        [ ! -e '$REMOTE_RELEASE' ] || { chown 0:0 '$REMOTE_RELEASE'; chmod 644 '$REMOTE_RELEASE'; }
        [ ! -e '$REMOTE_RELEASE_PREV' ] || { chown 0:0 '$REMOTE_RELEASE_PREV'; chmod 600 '$REMOTE_RELEASE_PREV'; }
        [ ! -e '$REMOTE_RELEASE_FAILED' ] || { chown 0:0 '$REMOTE_RELEASE_FAILED'; chmod 600 '$REMOTE_RELEASE_FAILED'; }
        [ ! -d '$REMOTE_DIR/.update' ] || { chown 0:0 '$REMOTE_DIR/.update'; chmod 700 '$REMOTE_DIR/.update'; }
    " >/dev/null
}

print_permissions() {
    adb_shell "
        for path in '$REMOTE_DIR' '$REMOTE_BIN' '$REMOTE_SERVICE' \
                    '$REMOTE_DIR/auth.token' '$REMOTE_DIR/zwrt-datad.log' \
                    '$REMOTE_DIR/zwrt-datad.pid' '$REMOTE_DIR/cooling.conf' \
                    '$REMOTE_RELEASE' '$REMOTE_RELEASE_PREV' \
                    '$REMOTE_RELEASE_FAILED' '$REMOTE_PREV' '$REMOTE_FAILED'; do
            [ -e \"\$path\" ] || continue
            stat -c '%a %U:%G %n' \"\$path\" 2>/dev/null || ls -ld \"\$path\"
        done
    " | tr -d '\r'
}

check_command() {
    fetch_latest_release
    installed_sha="$(remote_sha256 "$REMOTE_BIN")"
    installed_release="$(adb_shell "cat '$REMOTE_RELEASE' 2>/dev/null" | tr -d '\r\n' || true)"
    service_status="$(adb_shell "sh '$REMOTE_SERVICE' status 2>/dev/null" | tr -d '\r' || true)"
    running_pid="$(adb_shell 'pidof zwrt-datad 2>/dev/null' | tr -d '\r\n' || true)"
    service_running=0
    case "$running_pid" in
        ''|*[!0-9[:space:]]*) ;;
        *) service_running=1 ;;
    esac

    log "Latest release : $LATEST_TAG"
    log "Latest SHA-256: $EXPECTED_SHA"
    log "Installed tag  : ${installed_release:-untracked}"
    log "Installed SHA  : ${installed_sha:-missing}"
    log "Service        : ${service_status:-unknown}"
    if [ "$service_running" = "1" ]; then
        if health_ok; then
            log "Health         : ok"
        else
            log "Health         : failed"
        fi
    else
        log "Health         : skipped (service is not running)"
    fi

    if [ -n "$installed_sha" ] && [ "$installed_sha" = "$EXPECTED_SHA" ]; then
        log "Update status  : current binary matches latest release"
    else
        log "Update status  : update available or installed binary is untracked"
    fi
    log "Permissions:"
    print_permissions
}

restore_previous_after_failure() {
    log "New version failed health check; restoring previous binary..."
    adb_shell "
        sh '$REMOTE_SERVICE' stop >/dev/null 2>&1 || true
        if [ -f '$REMOTE_PREV' ]; then
            mv -f '$REMOTE_BIN' '$REMOTE_FAILED'
            mv -f '$REMOTE_PREV' '$REMOTE_BIN'
            [ ! -f '$REMOTE_RELEASE' ] || mv -f '$REMOTE_RELEASE' '$REMOTE_RELEASE_FAILED'
            if [ -f '$REMOTE_RELEASE_PREV' ]; then
                mv -f '$REMOTE_RELEASE_PREV' '$REMOTE_RELEASE'
            else
                printf 'untracked\n' > '$REMOTE_RELEASE'
            fi
            chmod 755 '$REMOTE_BIN'
            sh '$REMOTE_SERVICE' start
        else
            exit 2
        fi
    " >/dev/null || die "update failed and no automatic rollback was possible"
    fix_permissions
    health_ok || die "previous binary was restored but its health check also failed"
    die "update rolled back because the new service did not become healthy"
}

update_command() {
    fetch_latest_release
    installed_sha="$(remote_sha256 "$REMOTE_BIN")"
    if [ -n "$installed_sha" ] && [ "$installed_sha" = "$EXPECTED_SHA" ]; then
        log "Already on $LATEST_TAG ($EXPECTED_SHA)."
        log "No binary replacement performed."
        return 0
    fi

    download_candidate
    log "Verified release $LATEST_TAG; staging candidate on device..."
    adb_shell "mkdir -p '$REMOTE_DIR/.update' && chmod 700 '$REMOTE_DIR/.update'"
    "$ADB_BIN" -s "$SERIAL" push "$CANDIDATE" "$REMOTE_DIR/.update/zwrt-datad.new" >/dev/null
    staged_sha="$(remote_sha256 "$REMOTE_DIR/.update/zwrt-datad.new")"
    [ "$staged_sha" = "$EXPECTED_SHA" ] || die "staged device binary failed SHA-256 verification"
    adb_shell "chmod 755 '$REMOTE_DIR/.update/zwrt-datad.new' && '$REMOTE_DIR/.update/zwrt-datad.new' --help >/dev/null 2>&1" || \
        die "staged binary could not execute on the device"

    printf '%s\n' "$LATEST_TAG" > "$TMP_DIR/installed-release"
    "$ADB_BIN" -s "$SERIAL" push "$TMP_DIR/installed-release" "$REMOTE_DIR/.update/installed-release.new" >/dev/null

    log "Stopping service and atomically replacing the binary..."
    adb_shell "
        set -e
        sh '$REMOTE_SERVICE' stop >/dev/null 2>&1 || true
        [ ! -f '$REMOTE_BIN' ] || cp -p '$REMOTE_BIN' '$REMOTE_PREV'
        if [ -f '$REMOTE_RELEASE' ]; then
            cp -p '$REMOTE_RELEASE' '$REMOTE_RELEASE_PREV'
        else
            printf 'untracked\n' > '$REMOTE_RELEASE_PREV'
        fi
        mv -f '$REMOTE_DIR/.update/zwrt-datad.new' '$REMOTE_BIN'
        mv -f '$REMOTE_DIR/.update/installed-release.new' '$REMOTE_RELEASE'
        chmod 755 '$REMOTE_BIN'
        sh '$REMOTE_SERVICE' start
    " >/dev/null
    fix_permissions

    health_ok || restore_previous_after_failure
    final_sha="$(remote_sha256 "$REMOTE_BIN")"
    [ "$final_sha" = "$EXPECTED_SHA" ] || restore_previous_after_failure
    log "Updated successfully to $LATEST_TAG."
    log "Installed SHA-256: $final_sha"
}

rollback_command() {
    adb_shell "[ -f '$REMOTE_PREV' ]" || die "no previous binary is available"
    log "Swapping the current and previous binaries..."
    adb_shell "
        set -e
        sh '$REMOTE_SERVICE' stop >/dev/null 2>&1 || true
        mv -f '$REMOTE_BIN' '$REMOTE_DIR/zwrt-datad.swap'
        mv -f '$REMOTE_PREV' '$REMOTE_BIN'
        mv -f '$REMOTE_DIR/zwrt-datad.swap' '$REMOTE_PREV'
        if [ -f '$REMOTE_RELEASE_PREV' ]; then
            if [ -f '$REMOTE_RELEASE' ]; then
                mv -f '$REMOTE_RELEASE' '$REMOTE_DIR/installed-release.swap'
            else
                printf 'untracked\n' > '$REMOTE_DIR/installed-release.swap'
            fi
            mv -f '$REMOTE_RELEASE_PREV' '$REMOTE_RELEASE'
            mv -f '$REMOTE_DIR/installed-release.swap' '$REMOTE_RELEASE_PREV'
        else
            if [ -f '$REMOTE_RELEASE' ]; then
                mv -f '$REMOTE_RELEASE' '$REMOTE_RELEASE_PREV'
            fi
            printf 'untracked\n' > '$REMOTE_RELEASE'
        fi
        chmod 755 '$REMOTE_BIN'
        sh '$REMOTE_SERVICE' start
    " >/dev/null
    fix_permissions
    health_ok || die "rollback binary started but failed its health check"
    log "Rollback completed. Current SHA-256: $(remote_sha256 "$REMOTE_BIN")"
}

usage() {
    cat <<'EOF'
Usage: update-zwrt-datad.sh {check|update|rollback|permissions}

  check        Compare the installed binary with GitHub's latest release.
  update       Download, verify, stage, replace, health-check, and auto-rollback.
  rollback     Swap the current binary with zwrt-datad.prev.
  permissions  Apply the documented root-owned permission policy only.

Set ADB_SERIAL when more than one ADB device is connected.
EOF
}

main() {
    command_name="${1:-check}"
    case "$command_name" in
        check|update|rollback|permissions) ;;
        -h|--help|help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac

    require_tools
    select_device

    case "$command_name" in
        check) check_command ;;
        update) update_command ;;
        rollback) rollback_command ;;
        permissions)
            fix_permissions
            log "Permissions applied:"
            print_permissions
            ;;
    esac
}

main "$@"
