#!/usr/bin/env bash
# Fails if the app source picks up an API or setting that would leak user data or weaken
# transport security. Run by the pre-commit hook and by CI. Comment lines are ignored.
set -euo pipefail
cd "$(dirname "$0")/.."

failed=0

# forbid <description> <extended regex> <path>...
forbid() {
  local description=$1 pattern=$2
  shift 2
  local hits
  hits=$(grep -rnE --include='*.swift' --include='*.plist' "$pattern" "$@" 2>/dev/null \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(//|\*|///)' || true)
  if [[ -n $hits ]]; then
    echo "privacy-guard: $description" >&2
    echo "$hits" | sed 's/^/  /' >&2
    failed=1
  fi
}

forbid "UIDevice.name is the user-assigned device name; it must not be shared (use DefaultPlayerName)" \
  'UIDevice\.current\.name|\.current\.name\b' Puzzle
forbid "Advertising and vendor identifiers are tracking identifiers" \
  'ASIdentifierManager|advertisingIdentifier|identifierForVendor' Puzzle
forbid "Console logging can leak player names and photos into device logs" \
  '(^|[^A-Za-z_.])(print|debugPrint|NSLog|os_log)\(' Puzzle
forbid "Plain-HTTP URLs send data in cleartext" \
  '"http://' Puzzle
forbid "App Transport Security exceptions weaken transport security" \
  'NSAllowsArbitraryLoads|NSExceptionAllowsInsecureHTTPLoads' Puzzle Configuration

manifest=Puzzle/PrivacyInfo.xcprivacy
if ! python3 - "$manifest" <<'EOF'
import plistlib, sys
path = sys.argv[1]
try:
    with open(path, "rb") as f:
        manifest = plistlib.load(f)
except (OSError, plistlib.InvalidFileException) as error:
    sys.exit(f"privacy-guard: {path} is missing or not a valid plist ({error})")
if manifest.get("NSPrivacyTracking") is not False:
    sys.exit(f"privacy-guard: {path} must declare NSPrivacyTracking = false")
reasons = {entry.get("NSPrivacyAccessedAPIType"): entry.get("NSPrivacyAccessedAPITypeReasons", [])
           for entry in manifest.get("NSPrivacyAccessedAPITypes", [])}
if "CA92.1" not in reasons.get("NSPrivacyAccessedAPICategoryUserDefaults", []):
    sys.exit(f"privacy-guard: {path} must declare UserDefaults with reason CA92.1")
EOF
then
  failed=1
fi

if [[ $failed -ne 0 ]]; then
  exit 1
fi
echo "privacy-guard: OK"
