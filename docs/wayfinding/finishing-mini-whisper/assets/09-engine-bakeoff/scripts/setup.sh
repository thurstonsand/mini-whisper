#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
artifacts="$root/.artifacts"
checkout="$artifacts/transcribe.cpp"
framework_archive="$artifacts/TranscribeCpp.xcframework.zip"
runtime_revision=a94e021ef658dc7c788837341a13f6acea3baf3c
framework_sha256=b7a3442e2f3552cac1ee71b5e164934dd4db243f6b4b16b1e3e3ed5d1645eefd

mkdir -p "$artifacts" "$root/models"

if [[ ! -d "$checkout/.git" ]]; then
  git clone --filter=blob:none https://github.com/handy-computer/transcribe.cpp.git "$checkout"
fi
git -C "$checkout" fetch --quiet origin "$runtime_revision"
git -C "$checkout" checkout --quiet --detach "$runtime_revision"
test "$(git -C "$checkout" rev-parse HEAD)" = "$runtime_revision"

if [[ ! -f "$framework_archive" ]]; then
  curl --fail --location --retry 3 \
    https://github.com/handy-computer/transcribe.cpp/releases/download/v0.1.3/TranscribeCpp.xcframework.zip \
    --output "$framework_archive"
fi
echo "$framework_sha256  $framework_archive" | shasum -a 256 --check

framework="$checkout/bindings/swift/build-apple/TranscribeCpp.xcframework"
if [[ ! -d "$framework" ]]; then
  mkdir -p "$(dirname "$framework")"
  ditto -x -k "$framework_archive" "$(dirname "$framework")"
fi

while IFS=$'\t' read -r id repository revision filename bytes sha256 mode; do
  [[ -z "$id" || "$id" == \#* ]] && continue
  destination="$root/models/$filename"
  if [[ ! -f "$destination" ]]; then
    curl --fail --location --retry 3 \
      "https://huggingface.co/$repository/resolve/$revision/$filename" \
      --output "$destination.partial"
    mv "$destination.partial" "$destination"
  fi
  test "$(stat -f %z "$destination")" = "$bytes"
  echo "$sha256  $destination" | shasum -a 256 --check
done < "$root/models.tsv"

"$root/scripts/import-aqua-fixtures.py"

swift build --package-path "$root" --configuration release
