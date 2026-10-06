#!/bin/zsh
# usage: goal-fixture-run.sh <se|17> <run-label>
# Variants of the synthetic fixture's app-state.json for the goal screen:
# (A) no goals, (B) goalNeedsReview with an unusable raw value, then the
# midnight run. The original bytes are restored and compared at the end.
set -u
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd /private/tmp/hp-iphone-ui
dev=$1; run=$2
U=$(cat udid-$dev.txt)
xcrun simctl boot $U 2>/dev/null; xcrun simctl bootstatus $U -b >/dev/null
C=$(xcrun simctl get_app_container $U com.devsom.ProteinTracker data)
F="$C/Library/Application Support/HelloProtein/app-state.json"
[ -n "$C" ] && [ -f "$F" ] || { echo "no container/store for $U; aborting without changes"; exit 2; }
B=/private/tmp/hp-iphone-ui/goal-state-backup-$dev.json
xcrun simctl terminate $U com.devsom.ProteinTracker 2>/dev/null
cp "$F" "$B"
echo "before: $(shasum -a 256 "$F" | cut -c1-16) $(wc -c < "$F") bytes, goals=$(python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))['goals']))" "$B")"
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
variant empty;  DD=${DD:-/private/tmp/hp-iphone-ui/build} ./run-test.sh $dev $run test23GoalEmpty
xcrun simctl terminate $U com.devsom.ProteinTracker 2>/dev/null
variant review; DD=${DD:-/private/tmp/hp-iphone-ui/build} ./run-test.sh $dev $run test24GoalNeedsReview
xcrun simctl terminate $U com.devsom.ProteinTracker 2>/dev/null
cp "$B" "$F"; DD=${DD:-/private/tmp/hp-iphone-ui/build} ./run-test.sh $dev $run test25GoalDateChanged
xcrun simctl terminate $U com.devsom.ProteinTracker 2>/dev/null
cp "$B" "$F"
cmp "$B" "$F" && echo "restored: $(shasum -a 256 "$F" | cut -c1-16) (identical to backup)"
