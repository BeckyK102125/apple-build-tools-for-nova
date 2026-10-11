#!/bin/bash
# Builds one named copy of the reader: build-app.sh "<App Name>" <bundle-id> <output-dir>
set -euo pipefail
name="$1"
identifier="$2"
output="$3"
package_dir="$(cd "$(dirname "$0")" && pwd -P)"
swift build --package-path "$package_dir" --configuration release --product MarkdownReader >&2
binary="$(swift build --package-path "$package_dir" --configuration release --show-bin-path)/MarkdownReader"
bundle="$output/$name.app"
rm -rf "$bundle"
mkdir -p "$bundle/Contents/MacOS"
cp "$binary" "$bundle/Contents/MacOS/MarkdownReader"
sed -e "s/__NAME__/$name/g" -e "s/__IDENTIFIER__/$identifier/g" "$package_dir/Info.plist.template" > "$bundle/Contents/Info.plist"
codesign --force --sign - "$bundle"
codesign --verify --strict "$bundle"
printf '%s\n' "$bundle"
