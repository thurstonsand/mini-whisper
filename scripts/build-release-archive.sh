#!/usr/bin/env bash
set -euo pipefail

version="${RELEASE_VERSION:-$(git describe --tags --always --dirty)}"
version="${version#v}"

# The channel decides which app this is: its configuration, name, bundle identifier, and therefore
# its application support directory and Keychain service.
channel="${RELEASE_CHANNEL:-release}"
case "${channel}" in
  release)
    configuration="Release"
    app_name="MiniWhisper"
    bundle_identifier="com.thurstonsand.MiniWhisper"
    expected_profile_name="MiniWhisper Developer ID"
    ;;
  nightly)
    configuration="Nightly"
    app_name="MiniWhisper Nightly"
    bundle_identifier="com.thurstonsand.MiniWhisper.nightly"
    expected_profile_name="MiniWhisper Nightly Developer ID"
    ;;
  *) echo "unknown RELEASE_CHANNEL '${channel}'; expected release or nightly" >&2; exit 1 ;;
esac

team_id="6JMB7W6NB4"
name="MiniWhisper_${version}_darwin_arm64"
work_dir=".build/release"
derived_data="${work_dir}/DerivedData"
archive_path="${work_dir}/${app_name}.xcarchive"
archived_app="${archive_path}/Products/Applications/${app_name}.app"
export_path="${work_dir}/export"
export_options="${work_dir}/ExportOptions.plist"
archive_entitlements="${work_dir}/ArchiveEntitlements.plist"
signed_entitlements="${work_dir}/SignedEntitlements.plist"
profile_plist="${work_dir}/ProvisioningProfile.plist"
app_path="${work_dir}/${app_name}.app"
notary_archive="${work_dir}/MiniWhisper-notarization.zip"
archive="dist/${name}.zip"
expected_access_group="${team_id}.${bundle_identifier}"
installed_profile=""
remove_installed_profile=0

cleanup() {
  if [[ "${remove_installed_profile}" == 1 ]]; then
    rm -f "${installed_profile}"
  fi
  rm -rf \
    "${archive_path}" "${export_path}" "${work_dir}/${app_name}.app" "${notary_archive}" \
    "${export_options}" "${archive_entitlements}" "${signed_entitlements}" "${profile_plist}"
}

require_equal() {
  local name="$1" expected="$2" actual="$3"
  if [[ "${actual}" != "${expected}" ]]; then
    echo "${name}: expected '${expected}', got '${actual}'" >&2
    exit 1
  fi
}

trap cleanup EXIT
rm -rf dist "${derived_data}"
mkdir -p dist "${work_dir}"

case "${RELEASE_SIGNING:-0}" in
  0 | 1) ;;
  *) echo "RELEASE_SIGNING must be 0 or 1" >&2; exit 1 ;;
esac

if [[ "${RELEASE_SIGNING:-0}" == 1 ]]; then
  : "${APPLE_NOTARY_KEY_PATH:?APPLE_NOTARY_KEY_PATH is required for notarization}"
  : "${APPLE_NOTARY_KEY_ID:?APPLE_NOTARY_KEY_ID is required for notarization}"
  : "${APPLE_NOTARY_ISSUER_ID:?APPLE_NOTARY_ISSUER_ID is required for notarization}"
  : "${APPLE_PROVISIONING_PROFILE_PATH:?APPLE_PROVISIONING_PROFILE_PATH is required for signed export}"
  test -f "${APPLE_NOTARY_KEY_PATH}"
  test -f "${APPLE_PROVISIONING_PROFILE_PATH}"

  security cms -D -i "${APPLE_PROVISIONING_PROFILE_PATH}" > "${profile_plist}"
  profile_uuid=$(/usr/libexec/PlistBuddy -c "Print :UUID" "${profile_plist}")
  profile_name=$(/usr/libexec/PlistBuddy -c "Print :Name" "${profile_plist}")
  profile_team=$(/usr/libexec/PlistBuddy -c "Print :TeamIdentifier:0" "${profile_plist}")
  profile_application_identifier=$(
    /usr/libexec/PlistBuddy \
      -c "Print :Entitlements:com.apple.application-identifier" "${profile_plist}"
  )
  profile_access_group=$(
    /usr/libexec/PlistBuddy -c "Print :Entitlements:keychain-access-groups:0" "${profile_plist}"
  )
  provisions_all_devices=$(
    /usr/libexec/PlistBuddy -c "Print :ProvisionsAllDevices" "${profile_plist}"
  )
  signing_fingerprint=$(
    security find-identity -v -p codesigning \
      | awk -v team="${team_id}" \
        '/Developer ID Application:/ && index($0, "(" team ")") {print $2; exit}'
  )

  require_equal "provisioning profile name" "${expected_profile_name}" "${profile_name}"
  require_equal "provisioning team" "${team_id}" "${profile_team}"
  require_equal "profile application identifier" \
    "${expected_access_group}" "${profile_application_identifier}"
  require_equal "provisions all devices" "true" "${provisions_all_devices}"
  if [[ "${profile_access_group}" != "${expected_access_group}" \
    && "${profile_access_group}" != "${team_id}.*" ]]
  then
    echo "provisioning profile does not authorize '${expected_access_group}'" >&2
    exit 1
  fi
  if [[ -z "${signing_fingerprint}" ]]; then
    echo "no Developer ID Application identity found for team '${team_id}'" >&2
    exit 1
  fi

  PROFILE_PLIST="${profile_plist}" SIGNING_FINGERPRINT="${signing_fingerprint}" python3 <<'PY'
import datetime
import hashlib
import os
import plistlib

with open(os.environ["PROFILE_PLIST"], "rb") as file:
    profile = plistlib.load(file)

expiration = profile["ExpirationDate"].replace(tzinfo=datetime.timezone.utc)
if expiration <= datetime.datetime.now(datetime.timezone.utc):
    raise SystemExit("provisioning profile has expired")

fingerprints = {
    hashlib.sha1(certificate).hexdigest().upper()
    for certificate in profile["DeveloperCertificates"]
}
if os.environ["SIGNING_FINGERPRINT"] not in fingerprints:
    raise SystemExit("provisioning profile does not contain the signing certificate")
PY

  profile_dir="${HOME}/Library/Developer/Xcode/UserData/Provisioning Profiles"
  installed_profile="${profile_dir}/${profile_uuid}.provisionprofile"
  mkdir -p "${profile_dir}"
  if [[ -f "${installed_profile}" ]]; then
    cmp -s "${APPLE_PROVISIONING_PROFILE_PATH}" "${installed_profile}" || {
      echo "installed provisioning profile '${profile_uuid}' has unexpected contents" >&2
      exit 1
    }
  else
    cp "${APPLE_PROVISIONING_PROFILE_PATH}" "${installed_profile}"
    remove_installed_profile=1
  fi
fi

# The archive is intentionally unsigned. The script seeds it with the requested entitlements, then
# Xcode applies the pinned profile and local Developer ID identity during manual export. Local
# validation takes the same archive path without requiring signing credentials.
xcodebuild \
  -scheme MiniWhisper \
  -configuration "${configuration}" \
  -destination "generic/platform=macOS" \
  -archivePath "${archive_path}" \
  -derivedDataPath "${derived_data}" \
  -skipMacroValidation \
  -skipPackagePluginValidation \
  CODE_SIGNING_ALLOWED=NO \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  MARKETING_VERSION="${version}" \
  CURRENT_PROJECT_VERSION="${version}" \
  DEPLOYMENT_POSTPROCESSING=YES \
  STRIP_INSTALLED_PRODUCT=YES \
  ENABLE_CODE_COVERAGE=NO \
  CLANG_ENABLE_CODE_COVERAGE=NO \
  SWIFT_ENABLE_CODE_COVERAGE=NO \
  archive

if [[ "${RELEASE_SIGNING:-0}" == 1 ]]; then
  cp MiniWhisper/MiniWhisper.entitlements "${archive_entitlements}"
  /usr/libexec/PlistBuddy \
    -c "Set :keychain-access-groups:0 ${team_id}.${bundle_identifier}" \
    "${archive_entitlements}"

  # Export reads the archive's requested entitlements and pairs them with the pinned profile. The
  # ad-hoc signature is only that handoff; export replaces it with the Developer ID signature.
  codesign \
    --force \
    --sign - \
    --options runtime \
    --entitlements "${archive_entitlements}" \
    "${archived_app}"

  cat > "${export_options}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>developer-id</string>
  <key>destination</key>
  <string>export</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>signingCertificate</key>
  <string>${signing_fingerprint}</string>
  <key>provisioningProfiles</key>
  <dict>
    <key>${bundle_identifier}</key>
    <string>${expected_profile_name}</string>
  </dict>
  <key>teamID</key>
  <string>${team_id}</string>
</dict>
</plist>
EOF

  xcodebuild \
    -exportArchive \
    -archivePath "${archive_path}" \
    -exportPath "${export_path}" \
    -exportOptionsPlist "${export_options}"

  app_path="${export_path}/${app_name}.app"
  embedded_profile="${app_path}/Contents/embedded.provisionprofile"

  test -f "${embedded_profile}"
  codesign --verify --deep --strict --verbose=2 "${app_path}"
  codesign -d --entitlements :- "${app_path}" > "${signed_entitlements}"
  security cms -D -i "${embedded_profile}" > "${profile_plist}"

  actual_application_identifier=$(
    /usr/libexec/PlistBuddy -c "Print :com.apple.application-identifier" "${signed_entitlements}"
  )
  actual_access_group=$(
    /usr/libexec/PlistBuddy -c "Print :keychain-access-groups:0" "${signed_entitlements}"
  )
  profile_team=$(/usr/libexec/PlistBuddy -c "Print :TeamIdentifier:0" "${profile_plist}")
  profile_access_group=$(
    /usr/libexec/PlistBuddy -c "Print :Entitlements:keychain-access-groups:0" "${profile_plist}"
  )
  get_task_allow=$(
    /usr/libexec/PlistBuddy \
      -c "Print :com.apple.security.get-task-allow" "${signed_entitlements}" 2>/dev/null \
      || true
  )

  require_equal "application identifier" "${expected_access_group}" \
    "${actual_application_identifier}"
  require_equal "keychain access group" "${expected_access_group}" "${actual_access_group}"
  require_equal "provisioning team" "${team_id}" "${profile_team}"
  if [[ "${profile_access_group}" != "${expected_access_group}" \
    && "${profile_access_group}" != "${team_id}.*" ]]
  then
    echo "provisioning profile does not authorize '${expected_access_group}'" >&2
    exit 1
  fi
  if [[ "${get_task_allow}" == true ]]; then
    echo "release signature must not allow debugging" >&2
    exit 1
  fi

  signature=$(/usr/bin/codesign -dv --verbose=4 "${app_path}" 2>&1)
  grep -Fq "Authority=Developer ID Application:" <<< "${signature}"
  grep -Fq "TeamIdentifier=${team_id}" <<< "${signature}"
  grep -Fq "flags=0x10000(runtime)" <<< "${signature}"

  /usr/bin/ditto -c -k --sequesterRsrc --keepParent "${app_path}" "${notary_archive}"
  xcrun notarytool submit "${notary_archive}" \
    --key "${APPLE_NOTARY_KEY_PATH}" \
    --key-id "${APPLE_NOTARY_KEY_ID}" \
    --issuer "${APPLE_NOTARY_ISSUER_ID}" \
    --wait
  xcrun stapler staple "${app_path}"
  xcrun stapler validate "${app_path}"
  spctl --assess --type execute --verbose=2 "${app_path}"
else
  /usr/bin/ditto "${archived_app}" "${app_path}"
fi

info_plist="${app_path}/Contents/Info.plist"
require_equal "bundle identifier" "${bundle_identifier}" \
  "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${info_plist}")"
require_equal "short version" "${version}" \
  "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${info_plist}")"
require_equal "build version" "${version}" \
  "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${info_plist}")"

/usr/bin/ditto -c -k --sequesterRsrc --keepParent "${app_path}" "${archive}"
(cd dist && shasum -a 256 "${name}.zip" > "${name}.zip.sha256")
