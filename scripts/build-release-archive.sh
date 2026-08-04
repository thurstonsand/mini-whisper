#!/usr/bin/env bash
set -euo pipefail

version="${RELEASE_VERSION:-$(git describe --tags --always --dirty)}"
version="${version#v}"

# The channel decides which app this is: its configuration, its name, and therefore its bundle
# identifier and its application support directory. The archive keeps one name for both because
# a nightly version string already says so.
channel="${RELEASE_CHANNEL:-release}"
case "${channel}" in
  release) configuration="Release"; app_name="MiniWhisper" ;;
  nightly) configuration="Nightly"; app_name="MiniWhisper Nightly" ;;
  *) echo "unknown RELEASE_CHANNEL '${channel}'; expected release or nightly" >&2; exit 1 ;;
esac

name="MiniWhisper_${version}_darwin_arm64"
work_dir=".build/release"
derived_data="${work_dir}/DerivedData"
built_app="${derived_data}/Build/Products/${configuration}/${app_name}.app"
app_path="${work_dir}/${app_name}.app"
notary_archive="${work_dir}/MiniWhisper-notarization.zip"
archive="dist/${name}.zip"
plist="${app_path}/Contents/Info.plist"

# Everything this run produces is discarded, but DerivedData survives so an
# incremental rebuild can reuse the compiled dependency graph.
rm -rf dist "${app_path}"
mkdir -p dist "${work_dir}"

# `build` rather than `archive` because only `build` reuses incremental state:
# an archive action compiles into its own intermediates root every time. The
# settings below restore what an archive would otherwise imply — deployment
# postprocessing strips the binary, and coverage instrumentation (which the
# scheme enables for testing) has no place in a shipped build. Together they
# produce a byte-for-byte size match with the archived product.
xcodebuild \
  -scheme MiniWhisper \
  -configuration "${configuration}" \
  -destination "generic/platform=macOS" \
  -derivedDataPath "${derived_data}" \
  -skipMacroValidation \
  -skipPackagePluginValidation \
  CODE_SIGNING_ALLOWED=NO \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  DEPLOYMENT_POSTPROCESSING=YES \
  STRIP_INSTALLED_PRODUCT=YES \
  ENABLE_CODE_COVERAGE=NO \
  CLANG_ENABLE_CODE_COVERAGE=NO \
  SWIFT_ENABLE_CODE_COVERAGE=NO \
  build

/usr/bin/ditto "${built_app}" "${app_path}"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName ${app_name}" "${plist}"
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

# A partially configured notary environment must fail rather than silently ship an
# unnotarized archive that Gatekeeper will reject on the user's machine.
if [[ -n "${APPLE_NOTARY_KEY_PATH:-}${APPLE_NOTARY_KEY_ID:-}${APPLE_NOTARY_ISSUER_ID:-}" ]]; then
  : "${CODESIGN_IDENTITY:?CODESIGN_IDENTITY is required for notarization}"
  : "${APPLE_NOTARY_KEY_PATH:?APPLE_NOTARY_KEY_PATH is required for notarization}"
  : "${APPLE_NOTARY_KEY_ID:?APPLE_NOTARY_KEY_ID is required for notarization}"
  : "${APPLE_NOTARY_ISSUER_ID:?APPLE_NOTARY_ISSUER_ID is required for notarization}"

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
rm -rf "${app_path}" "${notary_archive}"
