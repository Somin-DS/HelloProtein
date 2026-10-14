#!/bin/zsh
# usage: promote.sh <udid> <label> [extra launch args...]
set -u
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
U=$1; L=$2; shift 2
OUT=/private/tmp/hp-quantity-sim/$L; mkdir -p $OUT
APP=/private/tmp/hp-quantity-app/Build/Products/Debug-iphonesimulator/ProteinTracker.app
xcrun simctl bootstatus $U -b >/dev/null 2>&1
C=$(xcrun simctl get_app_container $U com.devsom.ProteinTracker data)
D="$C/Library/Application Support/HelloProtein"
cp "$D/app-state.json" $OUT/before-app-state.json
ls -la "$D/migration" > $OUT/migration-dir-before.txt
xcrun simctl terminate $U com.devsom.ProteinTracker 2>/dev/null
xcrun simctl install $U $APP || exit 1
C=$(xcrun simctl get_app_container $U com.devsom.ProteinTracker data); D="$C/Library/Application Support/HelloProtein"
xcrun simctl launch $U com.devsom.ProteinTracker -HelloProteinRenewalFlow YES "$@" > $OUT/launch.txt 2>&1
echo "launch: $(cat $OUT/launch.txt)"
for i in {1..40}; do
  sleep 1
  if [ -f "$D/migration/schema-promotion.json" ] || [ -f "$D/migration/schema2-app-state.json" ]; then break; fi
done
sleep 4
echo "launched; store dir: $D"
