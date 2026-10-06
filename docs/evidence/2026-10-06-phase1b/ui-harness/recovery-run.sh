#!/bin/zsh
# usage: recovery-run.sh <se|17> <run-label>
# Drives the recovery screen with the real start gate by altering ONLY the
# synthetic fixture's app-state.json inside the simulator container. The
# original bytes are copied first and restored (and compared) at the end.
set -eu
set -o pipefail
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd /private/tmp/hp-iphone-ui
dev=$1; run=$2
U=$(cat udid-$dev.txt)
xcrun simctl boot "$U" 2>/dev/null || true
xcrun simctl bootstatus "$U" -b >/dev/null
C=$(xcrun simctl get_app_container $U com.devsom.ProteinTracker data)
[ -n "$C" ] && [ -f "$C/Library/Application Support/HelloProtein/app-state.json" ] || { echo "no container/store for $U; aborting without changes"; exit 2; }
F="$C/Library/Application Support/HelloProtein/app-state.json"
B=$(mktemp "/private/tmp/hp-iphone-ui/app-state-backup-$dev.XXXXXX")
xcrun simctl terminate "$U" com.devsom.ProteinTracker 2>/dev/null || true
cp "$F" "$B"
# Preserve the first test failure while still running the remaining checks.
test_result=0
run_tests() {
    local test_code=0
    DD=${DD:-/private/tmp/hp-iphone-ui/build} ./run-test.sh "$dev" "$run" "$@" || test_code=$?
    if (( test_result == 0 && test_code != 0 )); then
        test_result=$test_code
    fi
    return 0
}
restore_needed=1
restore_store() {
    xcrun simctl terminate "$U" com.devsom.ProteinTracker 2>/dev/null || true
    cp "$B" "$F" && cmp "$B" "$F"
}
cleanup() {
    local exit_code=$?
    trap - EXIT
    if (( restore_needed )); then
        if ! restore_store; then
            echo "restore failed; original backup retained at $B" >&2
            exit_code=1
        fi
    fi
    exit "$exit_code"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
echo "before: $(shasum -a 256 "$F" | cut -c1-16) $(wc -c < "$F") bytes"
ls -la "$C/Library/Application Support/HelloProtein/" "$C/Library/Application Support/HelloProtein/migration" 2>/dev/null | sed 's/^/  /' || true
# 1. truncated JSON → storeCorrupt, canRetry = true
printf '{"schemaVersion":1,"logs":[' > "$F"
run_tests test14RecoveryRetry test19RecoveryRetryKoreanLargeText
xcrun simctl terminate "$U" com.devsom.ProteinTracker 2>/dev/null || true
# 2. newer schema → storeUnsupportedSchema, canRetry = false
python3 - "$B" "$F" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
d['schemaVersion']=99
json.dump(d,open(sys.argv[2],'w'))
PY
run_tests test15RecoveryNoRetry test20RecoveryNoRetryKoreanLargeText
xcrun simctl terminate "$U" com.devsom.ProteinTracker 2>/dev/null || true
# 3. restore and verify bytes
restore_store
restore_needed=0
echo "restored: $(shasum -a 256 "$F" | cut -c1-16) (identical to backup)"
run_tests test16RecoveredHome
exit "$test_result"
