#!/bin/zsh
# usage: run-test.sh <se|17> <run-label> <testMethod> [more methods...]
set -u
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd /private/tmp/hp-iphone-ui
dev=$1; run=$2; shift 2
U=$(cat udid-$dev.txt)
echo "$run" > run.txt
T=$(date +%H%M%S)
only=()
for m in "$@"; do only+=("-only-testing:Smoke/Smoke/$m"); done
name="$run-$dev-$T"
xcodebuild -project Smoke.xcodeproj -scheme Smoke -destination "platform=iOS Simulator,id=$U" \
  -derivedDataPath /private/tmp/hp-iphone-ui/build -resultBundlePath "results/$name.xcresult" \
  "${only[@]}" test -quiet > "results/$name.log" 2>&1
code=$?
echo "## $name exit=$code"
xcrun xcresulttool get test-results summary --path "results/$name.xcresult" 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
print({k:d.get(k) for k in ['result','totalTestCount','passedTests','failedTests','skippedTests']})
for f in d.get('testFailures',[]): print('  -', f.get('testName'), '|', (f.get('failureText') or '')[:500])
"
