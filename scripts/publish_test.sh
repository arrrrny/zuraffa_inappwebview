#!/usr/bin/env bash
# Regression tests for scripts/publish.sh — pub.dev new-package rate limit.
# Issue: https://github.com/arrrrny/zuraffa_inappwebview/issues/12
#
# pub.dev rate limits *new package creation* (4 in a few minutes). A first-time
# federated publish trips the limit on the last package; publish.sh used to
# treat that transient refusal as a hard failure and left the release half
# published. These tests run publish.sh against a hermetic fixture tree with
# stubbed `dart` and `curl` on PATH — no network, no Dart SDK needed:
#
#   bash scripts/publish_test.sh
set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." >/dev/null 2>&1; pwd -P)"
PUBLISH_SH="$REPO_ROOT/scripts/publish.sh"

PACKAGES_IN_ORDER=("zuraffa_inappwebview" "zuraffa_inappwebview_platform" "zuraffa_inappwebview_android" "zuraffa_inappwebview_ios" "zuraffa_inappwebview_macos")
VERSION="7.3.2"

PASS=0
FAIL=0

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

assert_eq() { # desc expected actual
    if [ "$2" = "$3" ]; then
        PASS=$((PASS + 1)); echo "  ok: $1"
    else
        FAIL=$((FAIL + 1)); echo "  FAIL: $1"; echo "    expected: $2"; echo "    actual:   $3"
    fi
}

assert_diff() { # desc not-expected actual
    if [ "$2" != "$3" ]; then
        PASS=$((PASS + 1)); echo "  ok: $1"
    else
        FAIL=$((FAIL + 1)); echo "  FAIL: $1 (both are: $3)"
    fi
}

assert_contains() { # desc needle haystack
    case "$3" in
    *"$2"*) PASS=$((PASS + 1)); echo "  ok: $1" ;;
    *) FAIL=$((FAIL + 1)); echo "  FAIL: $1 (substring not found: $2)" ;;
    esac
}

count_lines() { wc -l < "$1" 2>/dev/null | tr -d '[:space:]'; }

# build_fixture <state_dir>: a copy of publish.sh plus a fresh packages/ tree.
build_fixture() {
    local state="$1" pkg
    mkdir -p "$state/scripts" "$state/bin" "$state/packages"
    cp "$PUBLISH_SH" "$state/scripts/publish.sh"
    for pkg in "${PACKAGES_IN_ORDER[@]}"; do
        mkdir -p "$state/packages/$pkg"
        printf 'name: %s\nversion: %s\n' "$pkg" "$VERSION" > "$state/packages/$pkg/pubspec.yaml"
    done
    : > "$state/dart.log"
}

# write_stubs <state_dir>: fake `dart` and `curl`, backed by a state dir.
# Scenario knobs (read by the stubs at runtime):
#   FAKE_PUB_RATE_LIMIT=1  enforce the new-package creation limit
#   FAKE_PUB_WINDOW=N      creations allowed before blocking (default 4)
#   FAKE_PUB_STICKY=1      never clear the window (every retry blocks too)
#   FAKE_PUB_FAIL_ON=pkg   make `pub publish --force` fail for pkg with a
#                          NON-rate-limit server error (must stay fatal)
write_stubs() {
    local state="$1"

    cat > "$state/bin/dart" << 'EOF'
#!/usr/bin/env bash
# Test stub: simulates `dart pub publish` against a fake pub.dev. The package
# under publish is read from the pubspec.yaml in the current directory, the
# same place the real command reads it.
set -u
STATE="$FAKE_PUB_STATE"
LOG="$STATE/dart.log"
PKG="$(sed -n 's/^name: *//p' pubspec.yaml 2>/dev/null)"
VER="$(sed -n 's/^version: *//p' pubspec.yaml 2>/dev/null)"

log() { printf '%s\n' "$1" >> "$LOG"; }

[ "$1" = "pub" ] || { echo "stub dart: unexpected args: $*" >&2; exit 127; }
shift

case "${1:-} ${2:-}" in
"publish --dry-run")
    log "dry-run:$PKG"
    echo "Dry-run ok for $PKG $VER."
    exit 0
    ;;
"publish --force") ;;
*)
    echo "stub dart: unexpected args: $*" >&2
    exit 127
    ;;
esac

log "publish-attempt:$PKG"

# A non-rate-limit server error: must never be retried away by publish.sh.
if [ "${FAKE_PUB_FAIL_ON:-}" = "$PKG" ]; then
    log "failed:$PKG"
    echo "Message from server: internal error while uploading $PKG." >&2
    echo "Failed to upload the package." >&2
    exit 1
fi

created=0
[ -f "$STATE/registered" ] && created="$(wc -l < "$STATE/registered" | tr -d '[:space:]')"
if ! grep -qxF "$PKG" "$STATE/registered" 2>/dev/null; then
    # Unregistered package: creating it consumes the new-package rate limit.
    if [ "${FAKE_PUB_RATE_LIMIT:-0}" = "1" ] && [ "$created" -ge "${FAKE_PUB_WINDOW:-4}" ]; then
        if [ "${FAKE_PUB_STICKY:-0}" = "1" ] || [ ! -f "$STATE/blocked:$PKG" ]; then
            # First refusal records the block; on a non-sticky window the
            # retry (minutes later, with publish.sh's backoff) succeeds.
            : > "$STATE/blocked:$PKG"
            log "blocked:$PKG"
            echo 'Message from server: The "package-created" operation is blocked, as its rate limit has been reached (4 in the last few minutes). Please try again later.' >&2
            echo 'Please report the issue on https://github.com/dart-lang/pub-dev/issues/new if' >&2
            echo 'you think the limit should be increased to accommodate your use case.' >&2
            exit 65
        fi
    fi
    printf '%s\n' "$PKG" >> "$STATE/registered"
    log "created:$PKG"
fi

log "published:$PKG"
echo "Published $PKG $VER."
exit 0
EOF

    cat > "$state/bin/curl" << 'EOF'
#!/usr/bin/env bash
# Test stub: fake pub.dev API. Serves only the /api/packages/<name> lookups
# publish.sh makes; a registered package returns JSON containing its version,
# an unregistered one returns an empty body (grep finds no version).
set -u
STATE="$FAKE_PUB_STATE"
URL="${@: -1}"
case "$URL" in
*/api/packages/*)
    PKG="${URL##*/api/packages/}"
    if grep -qxF "$PKG" "$STATE/registered" 2>/dev/null; then
        VER="$(sed -n "s/^version: *//p" "$FAKE_PUB_FIXTURE/packages/$PKG/pubspec.yaml" 2>/dev/null)"
        printf '{"name":"%s","latest":{"version":"%s"},"versions":[{"version":"%s"}]}\n' "$PKG" "$VER" "$VER"
    fi
    exit 0
    ;;
*)
    echo "stub curl: unexpected URL: $URL" >&2
    exit 127
    ;;
esac
EOF

    chmod +x "$state/bin/dart" "$state/bin/curl"
}

# run_publish <state_dir>: run the copied publish.sh with stubs on PATH and
# the retry/spacing sleeps shrunk to 1s (override by exporting the knobs).
# Output is captured with stderr merged, like an operator would see it.
run_publish() {
    local state="$1"
    (
        cd "$state" || exit 99
        export PATH="$state/bin:/usr/bin:/bin" # hermetic: no real dart/curl
        export FAKE_PUB_STATE="$state" FAKE_PUB_FIXTURE="$state"
        export PUBLISH_RETRY_WAIT_SECS="${PUBLISH_RETRY_WAIT_SECS:-1}"
        export PUBLISH_NEW_PACKAGE_SPACING_SECS="${PUBLISH_NEW_PACKAGE_SPACING_SECS:-1}"
        bash "$state/scripts/publish.sh"
    ) 2>&1
}

echo "1. fresh family: rate limit trips on the last package — publish.sh retries and completes (issue #12 reproduction)"
state="$TMPROOT/t1"; build_fixture "$state"; write_stubs "$state"
export FAKE_PUB_RATE_LIMIT=1 FAKE_PUB_WINDOW=4
out="$(run_publish "$state")"; status=$?
assert_eq "exit code 0" "0" "$status"
assert_contains "rate-limit refusal surfaced in output" 'rate limit has been reached' "$out"
assert_contains "script reports completion" 'All packages published.' "$out"
assert_eq "all five packages registered on (fake) pub.dev" "5" "$(count_lines "$state/registered")"
assert_eq "macos publish attempted twice (one retry)" "2" "$(grep -c 'publish-attempt:zuraffa_inappwebview_macos' "$state/dart.log")"
assert_eq "publish order preserved" \
    "zuraffa_inappwebview zuraffa_inappwebview_platform zuraffa_inappwebview_android zuraffa_inappwebview_ios zuraffa_inappwebview_macos" \
    "$(grep '^created:' "$state/dart.log" | cut -d: -f2 | tr '\n' ' ' | sed 's/ $//')"
unset FAKE_PUB_RATE_LIMIT FAKE_PUB_WINDOW

echo "2. sticky rate limit: gives up after PUBLISH_MAX_ATTEMPTS with a non-zero exit"
state="$TMPROOT/t2"; build_fixture "$state"; write_stubs "$state"
export FAKE_PUB_RATE_LIMIT=1 FAKE_PUB_WINDOW=4 FAKE_PUB_STICKY=1 PUBLISH_MAX_ATTEMPTS=2
out="$(run_publish "$state")"; status=$?
unset FAKE_PUB_RATE_LIMIT FAKE_PUB_WINDOW FAKE_PUB_STICKY PUBLISH_MAX_ATTEMPTS
assert_diff "exit code non-zero" "0" "$status"
assert_eq "macos attempted exactly PUBLISH_MAX_ATTEMPTS times" "2" "$(grep -c 'publish-attempt:zuraffa_inappwebview_macos' "$state/dart.log")"
assert_contains "exhausted retries reported" 'still blocking' "$out"

echo "3. non-rate-limit server error: still fatal, never retried"
state="$TMPROOT/t3"; build_fixture "$state"; write_stubs "$state"
export FAKE_PUB_FAIL_ON=zuraffa_inappwebview_ios
out="$(run_publish "$state")"; status=$?
unset FAKE_PUB_FAIL_ON
assert_diff "exit code non-zero" "0" "$status"
assert_eq "ios attempted once (no retries)" "1" "$(grep -c 'publish-attempt:zuraffa_inappwebview_ios' "$state/dart.log")"
assert_eq "macos never attempted" "0" "$(grep -c 'publish-attempt:zuraffa_inappwebview_macos' "$state/dart.log")"
assert_contains "hard failure reported" 'Publish failed for zuraffa_inappwebview_ios' "$out"

echo "4. everything already on pub.dev: skips all packages, zero publish calls"
state="$TMPROOT/t4"; build_fixture "$state"; write_stubs "$state"
for pkg in "${PACKAGES_IN_ORDER[@]}"; do printf '%s\n' "$pkg" >> "$state/registered"; done
out="$(run_publish "$state")"; status=$?
assert_eq "exit code 0" "0" "$status"
assert_eq "zero publish calls" "0" "$(grep -c 'publish-attempt' "$state/dart.log")"
assert_eq "five skips reported" "5" "$(printf '%s\n' "$out" | grep -c 'already on pub.dev')"

echo
echo "publish_test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
