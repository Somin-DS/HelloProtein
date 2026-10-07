#!/bin/zsh
# usage: goal-fixture-run.sh <se|17> <run-label>
# Variants of the synthetic fixture's app-state.json for the goal screen:
# (A) no goals, (B) goalNeedsReview with an unusable raw value, then the
# midnight run. The original bytes are restored and compared at the end.
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
B=$(mktemp "/private/tmp/hp-iphone-ui/goal-state-backup-$dev.XXXXXX")
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
variant() { python3 - "$B" "$F" "$1" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); mode=sys.argv[3]
d['goals']=[]
if mode=='review':
    d['settings']['goalNeedsReview']=True
    d['settings']['legacyTargetRaw']='120 grams'
else:
    d['settings']['goalNeedsReview']=False
json.dump(d,open(sys.argv[2],'w'))
PY
}
variant empty
run_tests test23GoalEmpty
xcrun simctl terminate "$U" com.devsom.ProteinTracker 2>/dev/null || true
variant review
run_tests test24GoalNeedsReview
restore_store
run_tests test25GoalDateChanged
restore_store
restore_needed=0
echo "restored: $(shasum -a 256 "$F" | cut -c1-16) (identical to backup)"
exit "$test_result"
