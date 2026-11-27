#!/usr/bin/env bash
# HCG News — audit a Release build against the App Store privacy answers and export compliance.
#
# Usage: release-audit.sh <path to HCGNews.xcarchive or HCGNews.app> [report.md]
# Runs on macOS with Xcode. Reads the built product only; changes nothing.
set -uo pipefail

INPUT="$1"
REPORT="${2:-release-audit.md}"
if [[ "$INPUT" == *.xcarchive ]]; then APP="$INPUT/Products/Applications/HCGNews.app"; else APP="$INPUT"; fi
BIN="$APP/HCGNews"
[ -x "$BIN" ] || { echo "No executable at $BIN"; exit 2; }

exec > >(tee "$REPORT") 2>&1
echo "# HCG News Release build audit"
echo
echo "- Built product: \`$(basename "$APP")\`"
echo "- Toolchain: $(xcodebuild -version | tr '\n' ' ')"
echo "- Audited: $(date -u +%Y-%m-%dT%H:%MZ)"
echo

FAIL=0
check() { if eval "$2"; then echo "- ✅ $1"; else echo "- ❌ $1"; FAIL=1; fi; }
pl() { /usr/libexec/PlistBuddy -c "Print :$1" "$APP/Info.plist" 2>/dev/null; }

echo "## 1. Info.plist"
echo
echo '```'
for k in CFBundleIdentifier CFBundleDisplayName CFBundleShortVersionString CFBundleVersion MinimumOSVersion DTSDKName DTXcode \
         ITSAppUsesNonExemptEncryption NSAppTransportSecurity UIBackgroundModes CFBundleURLTypes LSApplicationQueriesSchemes \
         NSHumanReadableCopyright LSApplicationCategoryType UIDeviceFamily; do
  v=$(pl "$k" | tr '\n' ' ' | sed 's/  */ /g'); echo "$k = ${v:-(not set)}"
done
plutil -p "$APP/Info.plist" | grep -E '"NS[A-Za-z]+UsageDescription"' || echo "(no NS…UsageDescription permission strings)"
echo '```'
echo
check "Bundle id is com.hakmicapitalgroup.hcgnews" '[ "$(pl CFBundleIdentifier)" = "com.hakmicapitalgroup.hcgnews" ]'
check "Version 1.0.0 (3)" '[ "$(pl CFBundleShortVersionString)" = "1.0.0" ] && [ "$(pl CFBundleVersion)" = "3" ]'
check "ITSAppUsesNonExemptEncryption = NO (export compliance: exempt)" '[ "$(pl ITSAppUsesNonExemptEncryption)" = "false" ]'
check "No App Transport Security exceptions (HTTPS only)" '[ -z "$(pl NSAppTransportSecurity)" ]'
check "No background modes" '[ -z "$(pl UIBackgroundModes)" ]'
check "No permission prompts (camera, location, contacts, tracking …)" '! plutil -p "$APP/Info.plist" | grep -qE "\"NS[A-Za-z]+UsageDescription\""'
check "Built with the iOS 26 SDK" '[[ "$(pl DTSDKName)" == iphoneos26* ]]'
echo

echo "## 2. Privacy manifest"
echo
if [ -f "$APP/PrivacyInfo.xcprivacy" ]; then
  echo '```'; plutil -p "$APP/PrivacyInfo.xcprivacy"; echo '```'
  check "PrivacyInfo.xcprivacy is in the bundle and valid" 'plutil -lint "$APP/PrivacyInfo.xcprivacy" >/dev/null'
  check "Tracking is declared false" '[ "$(/usr/libexec/PlistBuddy -c "Print :NSPrivacyTracking" "$APP/PrivacyInfo.xcprivacy")" = "false" ]'
else
  echo "- ❌ PrivacyInfo.xcprivacy missing from the bundle"; FAIL=1
fi
echo

echo "## 3. Required-reason APIs referenced by the executable"
echo
SYMS=$(xcrun nm -u "$BIN" 2>/dev/null; strings -a "$BIN")
probe() { if echo "$SYMS" | grep -qE "$2"; then echo "| $1 | **referenced** | $3 |"; else echo "| $1 | not found | $3 |"; fi; }
echo "| API category | In binary | Declared in manifest |"
echo "|---|---|---|"
probe "UserDefaults" "NSUserDefaults|UserDefaults" "CA92.1"
probe "File timestamp (stat/getattrlist/modification dates)" "_stat\$|_fstat\$|_lstat\$|_getattrlist|NSFileModificationDate|contentModificationDate|attributesOfItem" "C617.1"
probe "System boot time" "_mach_absolute_time|systemUptime|kern.boottime" "not declared"
probe "Disk space" "NSFileSystemFreeSize|volumeAvailableCapacity|_statfs|_statvfs" "not declared"
probe "Active keyboards" "activeInputModes" "not declared"
echo
echo "A **referenced** API that is \"not declared\" must be added to the manifest, with its reason, before submission."
echo

echo "## 4. Network hosts embedded in the app"
echo
echo '```'
{ strings -a "$BIN"; find "$APP" -name '*.json' -exec cat {} \; ; } | grep -oE 'https?://[A-Za-z0-9.-]+' | sort -u
echo '```'
echo
check "No analytics, advertising or tracking SDK hosts" '! { strings -a "$BIN"; find "$APP" -name "*.json" -exec cat {} \; ; } | grep -qiE "firebase|google-analytics|crashlytics|amplitude|mixpanel|segment\.io|appsflyer|adjust\.com|facebook|branch\.io|sentry"'
echo

echo "## 5. Cryptography (export compliance)"
echo
echo '```'
echo "$SYMS" | grep -oE '_CC_[A-Z0-9_]+|_Sec(Item|Key|Trust)[A-Za-z]*|CryptoKit|SHA256|_CCCrypt[A-Za-z]*|AES|ChaChaPoly' | sort -u | head -40
echo '```'
echo
echo "Expected: hashing (SHA-256 for sign-in PKCE), Keychain (SecItem) and system TLS only — all exempt."
check "No custom encryption (CCCrypt / AES / ChaChaPoly not used)" '! echo "$SYMS" | grep -qE "_CCCrypt|AES\.GCM|ChaChaPoly"'
echo

echo "## 6. Linked frameworks and embedded code"
echo
echo '```'
xcrun otool -L "$BIN" | tail -n +2 | awk '{print $1}'
echo '```'
if [ -d "$APP/Frameworks" ]; then echo "Embedded frameworks:"; ls "$APP/Frameworks"; else echo "No embedded frameworks (no third-party SDKs)."; fi
check "No third-party frameworks embedded" '[ ! -d "$APP/Frameworks" ] || [ -z "$(ls "$APP/Frameworks" | grep -v "^libswift")" ]'
echo

echo "## 7. Resources"
echo
check "Bundled publication configuration present" '[ -f "$APP/HCGNewsConfiguration.json" ]'
check "Bundled configuration contains no service-role or secret key" '! grep -qiE "service_role|sb_secret_|\"secret\"|password" "$APP/HCGNewsConfiguration.json"'
check "Newsreader and Manrope fonts and their OFL licences present" 'ls "$APP" | grep -q Newsreader-Variable.ttf && ls "$APP" | grep -q Manrope-Variable.ttf && ls "$APP" | grep -q Newsreader-OFL.txt && ls "$APP" | grep -q Manrope-OFL.txt'
if [ -f "$APP/Assets.car" ]; then
  INFO=$(xcrun --sdk iphoneos assetutil --info "$APP/Assets.car" 2>/dev/null)
  echo
  echo "Compiled asset catalog (name · appearance · size):"
  echo '```'
  echo "$INFO" | python3 -c '
import json, sys
seen = set()
for a in json.load(sys.stdin):
    n = a.get("Name")
    if not n: continue
    key = (n, a.get("Appearance", "any"), a.get("PixelWidth"), a.get("PixelHeight"))
    if key in seen: continue
    seen.add(key)
    print(f"{n:24} {a.get(\"Appearance\", \"any\"):28} {a.get(\"PixelWidth\")}x{a.get(\"PixelHeight\")}")
' | sort | head -60
  echo '```'
  check "HCGClassicLogo has Light and Dark variants" 'echo "$INFO" | grep -q HCGClassicLogo && echo "$INFO" | python3 -c "import json,sys;d=json.load(sys.stdin);a=[x.get(\"Appearance\",\"\") for x in d if x.get(\"Name\")==\"HCGClassicLogo\"];sys.exit(0 if any(\"Dark\" in v for v in a) else 1)"'
  check "HCGFutureLogo has Light and Dark variants" 'echo "$INFO" | python3 -c "import json,sys;d=json.load(sys.stdin);a=[x.get(\"Appearance\",\"\") for x in d if x.get(\"Name\")==\"HCGFutureLogo\"];sys.exit(0 if any(\"Dark\" in v for v in a) else 1)"'
  check "App icon compiled into the catalog" 'echo "$INFO" | grep -q "\"Name\" : \"AppIcon\""'
fi
check "App icon declared in Info.plist (CFBundleIcons)" 'plutil -p "$APP/Info.plist" | grep -q CFBundleIcons'
echo

echo "## Result"
echo
if [ $FAIL -eq 0 ]; then echo "**All checks passed.**"; else echo "**One or more checks failed (see ❌ above).**"; fi
exit $FAIL
