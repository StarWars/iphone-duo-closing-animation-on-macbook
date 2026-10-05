#!/bin/bash
set -euo pipefail

# Build a fresh universal prototype archive without relying on a local dist tree.
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
native_root="$project_root/duo-animation"
app_bundle="$native_root/build/Build/Products/Release/DuoLid.app"

xcodebuild -project "$native_root/DuoLid.xcodeproj" -scheme DuoLid \
  -configuration Release -derivedDataPath "$native_root/build" build \
  'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO

codesign --verify --deep --strict "$app_bundle"
lipo -verify_arch arm64 "$app_bundle/Contents/MacOS/DuoLid"
lipo -verify_arch x86_64 "$app_bundle/Contents/MacOS/DuoLid"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_bundle/Contents/Info.plist")"
[[ "$bundle_id" == "pl.appbeat.DuoLid" ]]
for legal_file in LICENSE NOTICE EULA.md; do
  cmp "$project_root/$legal_file" "$app_bundle/Contents/Resources/$legal_file"
done

staging_dir="$(mktemp -d "$native_root/build/package.XXXXXX")"
package_root="$staging_dir/Duo-Lid-Prototype"
mkdir -p "$package_root" "$project_root/downloads"
ditto "$app_bundle" "$package_root/Duo Lid.app"
cp "$project_root/downloads/INSTALL.md" "$project_root/ATTRIBUTIONS.md" \
  "$project_root/LICENSE" "$project_root/NOTICE" "$project_root/EULA.md" "$package_root/"
ditto -c -k --keepParent --norsrc --noextattr "$package_root" "$staging_dir/Duo-Lid-Prototype.zip"
mv "$staging_dir/Duo-Lid-Prototype.zip" "$project_root/downloads/Duo-Lid-Prototype.zip"
(
  cd "$project_root/downloads"
  shasum -a 256 Duo-Lid-Prototype.zip > SHA256SUMS
  shasum -a 256 -c SHA256SUMS
)
echo "Prototype package: $project_root/downloads/Duo-Lid-Prototype.zip"
