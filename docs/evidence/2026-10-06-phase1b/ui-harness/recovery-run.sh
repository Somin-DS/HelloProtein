#!/bin/zsh
# usage: recovery-run.sh <se|17> <run-label>
# Drives the recovery screen with the real start gate by altering ONLY the
# synthetic fixture's app-state.json inside the simulator container. The
# original bytes are copied first and restored (and compared) at the end.
set -u
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd /private/tmp/hp-iphone-ui
dev=$1; run=$2
U=$(cat udid-$dev.txt)
xcrun simctl boot $U 2>/dev/null; xcrun simctl bootstatus $U -b >/dev/null
C=$(xcrun simctl get_app_container $U com.devsom.ProteinTracker data)
[ -n "$C" ] && [ -f "$C/Library/Application Support/HelloProtein/app-state.json" ] || { echo "no container/store for $U; aborting without changes"; exit 2; }
F="$C/Library/Application Support/HelloProtein/app-state.json"
B=/private/tmp/hp-iphone-ui/app-state-backup-$dev.json
xcrun simctl terminate $U com.devsom.ProteinTracker 2>/dev/null
cp "$F" "$B"
echo "before: $(shasum -a 256 "$F" | cut -c1-16) $(wc -c < "$F") bytes"
ls -la "$C/Library/Application Support/HelloProtein/" "$C/Library/Application Support/HelloProtein/migration" 2>/dev/null | sed 's/^/  /'
# 1. truncated JSON → storeCorrupt, canRetry = true
printf '{"schemaVersion":1,"logs":[' > "$F"
DD=${DD:-/private/tmp/hp-iphone-ui/build} ./run-test.sh $dev $run test14RecoveryRetry test19RecoveryRetryKoreanLargeText
xcrun simctl terminate $U com.devsom.ProteinTracker 2>/dev/null
# 2. newer schema → storeUnsupportedSchema, canRetry = false
python3 - "$B" "$F" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
d['schemaVersion']=99
json.dump(d,open(sys.argv[2],'w'))
PY
DD=${DD:-/private/tmp/hp-iphone-ui/build} ./run-test.sh $dev $run test15RecoveryNoRetry test20RecoveryNoRetryKoreanLargeText
xcrun simctl terminate $U com.devsom.ProteinTracker 2>/dev/null
# 3. restore and verify bytes
cp "$B" "$F"
cmp "$B" "$F" && echo "restored: $(shasum -a 256 "$F" | cut -c1-16) (identical to backup)"
DD=${DD:-/private/tmp/hp-iphone-ui/build} ./run-test.sh $dev $run test16RecoveredHome
