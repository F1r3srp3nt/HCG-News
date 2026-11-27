#!/usr/bin/env bash
# HCG News — full release qualification on your own Mac (Apple silicon, Xcode 26).
# Does what .github/workflows/ios-qualification.yml does:
#   1. package tests (swift test, macOS)
#   2. build + run the whole scheme (unit + UI tests) on an iPhone and an iPad simulator,
#      including the Classic/Future × Light/Dark evidence screenshots, the Home Screen icon
#      and Apple's accessibility audit
#   3. unsigned Release archive + privacy / export-compliance audit
# Nothing is signed, uploaded or submitted. Results go to ~/HCGNews-qualification-<timestamp>/.
#
# Usage (from the repository root):   bash "iOS app/tools/qualify-local.sh"
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROJECT="$ROOT/iOS app/HCGNews/HCGNews.xcodeproj"
PACKAGE="$ROOT/iOS app/HCGNews/HCGNewsKit"
OUT="$HOME/HCGNews-qualification-$(date +%Y%m%d-%H%M%S)"
DD="$OUT/DerivedData"
mkdir -p "$OUT"
exec > >(tee "$OUT/qualification.log") 2>&1

# Xcode 26: use the selected Xcode if it is 26, otherwise the newest /Applications/Xcode*26*.app.
if ! xcodebuild -version | head -1 | grep -q "Xcode 26"; then
  CANDIDATE=$(ls -d /Applications/Xcode*.app 2>/dev/null | while read -r x; do
    v=$("$x/Contents/Developer/usr/bin/xcodebuild" -version 2>/dev/null | head -1); [[ "$v" == "Xcode 26"* ]] && echo "$x"; done | sort -V | tail -1)
  [ -n "$CANDIDATE" ] || { echo "Xcode 26 not found. Install it from the App Store or developer.apple.com."; exit 2; }
  export DEVELOPER_DIR="$CANDIDATE/Contents/Developer"
fi
echo "== $(xcodebuild -version | tr '\n' ' ') · macOS $(sw_vers -productVersion) · $(uname -m)"
echo "== Output: $OUT"

STATUS=0
step() { echo; echo "===== $1 ====="; }

step "1/4 Package tests (macOS)"
swift test --package-path "$PACKAGE" 2>&1 | tail -5 || STATUS=1

for DEVICE in iphone ipad; do
  step "2/4 Build and test on $DEVICE"
  IFS=$'\t' read -r UDID NAME RUNTIME < <(python3 "$ROOT/.github/scripts/pick-simulator.py" "$DEVICE") || { echo "No $DEVICE simulator"; STATUS=1; continue; }
  echo "Simulator: $NAME ($RUNTIME)"
  xcrun simctl boot "$UDID" 2>/dev/null; xcrun simctl bootstatus "$UDID" -b >/dev/null
  xcodebuild test -project "$PROJECT" -scheme HCGNews -destination "id=$UDID" -derivedDataPath "$DD" \
    -resultBundlePath "$OUT/results-$DEVICE.xcresult" -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO \
    > "$OUT/test-$DEVICE.log" 2>&1 || STATUS=1
  grep -E "\*\* (TEST|BUILD) " "$OUT/test-$DEVICE.log" | tail -2
  python3 "$ROOT/.github/scripts/xcresult-report.py" "$OUT/results-$DEVICE.xcresult" "$OUT/evidence-$DEVICE" | grep -E "^(RESULT|DEVICE|FAILED|ATTACHMENTS)"
done

step "3/4 Release archive (unsigned)"
xcodebuild archive -project "$PROJECT" -scheme HCGNews -configuration Release -destination "generic/platform=iOS" \
  -archivePath "$OUT/HCGNews.xcarchive" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM="" \
  > "$OUT/archive.log" 2>&1 || STATUS=1
grep -E "\*\* ARCHIVE " "$OUT/archive.log" | tail -1

step "4/4 Release audit"
bash "$ROOT/iOS app/tools/release-audit.sh" "$OUT/HCGNews.xcarchive" "$OUT/release-audit.md" | tail -3 || STATUS=1

echo
echo "===== Done: $( [ $STATUS -eq 0 ] && echo 'ALL PASSED' || echo 'FAILURES — see logs' ) ====="
echo "Screenshots: $OUT/evidence-iphone and $OUT/evidence-ipad · Audit: $OUT/release-audit.md"
open "$OUT" 2>/dev/null || true
exit $STATUS
