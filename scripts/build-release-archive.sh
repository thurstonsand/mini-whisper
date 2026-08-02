#!/usr/bin/env bash
set -euo pipefail

version="${RELEASE_VERSION:-$(git describe --tags --always --dirty)}"
version="${version#v}"
name="MiniWhisper_${version}_darwin_arm64"
work_dir=".build/release"
archive_path="${work_dir}/MiniWhisper.xcarchive"
app_path="${work_dir}/MiniWhisper.app"
archive="dist/${name}.zip"
plist="${app_path}/Contents/Info.plist"

rm -rf dist "${work_dir}"
mkdir -p dist "${work_dir}"

xcodebuild \
  -scheme MiniWhisper \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "${archive_path}" \
  -derivedDataPath "${work_dir}/DerivedData" \
  -skipMacroValidation \
  -skipPackagePluginValidation \
  CODE_SIGNING_ALLOWED=NO \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  archive

/usr/bin/ditto "${archive_path}/Products/Applications/MiniWhisper.app" "${app_path}"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName MiniWhisper" "${plist}"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${version}" "${plist}"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${version}" "${plist}"

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  codesign \
    --force \
    --timestamp \
    --options runtime \
    --entitlements MiniWhisper/MiniWhisper.entitlements \
    --sign "${CODESIGN_IDENTITY}" \
    "${app_path}"
fi

if [[ -n "${APPLE_NOTARY_KEY_PATH:-}" && -n "${APPLE_NOTARY_KEY_ID:-}" && -n "${APPLE_NOTARY_ISSUER_ID:-}" ]]; then
  notary_archive="${work_dir}/MiniWhisper-notarization.zip"
  /usr/bin/ditto -c -k --sequesterRsrc --keepParent "${app_path}" "${notary_archive}"
  xcrun notarytool submit "${notary_archive}" \
    --key "${APPLE_NOTARY_KEY_PATH}" \
    --key-id "${APPLE_NOTARY_KEY_ID}" \
    --issuer "${APPLE_NOTARY_ISSUER_ID}" \
    --wait
  xcrun stapler staple "${app_path}"
  xcrun stapler validate "${app_path}"
fi

/usr/bin/ditto -c -k --sequesterRsrc --keepParent "${app_path}" "${archive}"
(cd dist && shasum -a 256 "${name}.zip" > "${name}.zip.sha256")
rm -rf "${work_dir}"
