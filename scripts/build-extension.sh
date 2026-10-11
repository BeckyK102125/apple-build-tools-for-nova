#!/bin/bash
# Builds the two native programs the extension needs and puts them in
# AppleBuildTools.novaextension/Executables:
#   AppleBuildHelper         the Swift helper that talks to Xcode, devicectl, and simctl
#   Apple Build Reader.app   the VoiceOver-friendly reader and chooser window
# Usage: scripts/build-extension.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd -P)"
bundle="$root/AppleBuildTools.novaextension"
executables="$bundle/Executables"

if ! xcrun --find swift >/dev/null 2>&1; then
  echo "Swift was not found. Install Xcode, open it once, then run this script again." >&2
  exit 1
fi

mkdir -p "$executables"

echo "Building AppleBuildHelper (release)…" >&2
swift build --package-path "$root/Swift" --configuration release --product AppleBuildHelper >&2
helper_bin="$(swift build --package-path "$root/Swift" --configuration release --show-bin-path)/AppleBuildHelper"
cp "$helper_bin" "$executables/AppleBuildHelper"
chmod 755 "$executables/AppleBuildHelper"
codesign --force --sign - "$executables/AppleBuildHelper"

echo "Building Apple Build Reader (release)…" >&2
"$root/Native/MarkdownReader/build-app.sh" \
  "Apple Build Reader" \
  "io.github.beckyk102125.AppleBuildTools.reader" \
  "$executables" >/dev/null

echo "Done. The extension is ready at:" >&2
echo "$bundle"
