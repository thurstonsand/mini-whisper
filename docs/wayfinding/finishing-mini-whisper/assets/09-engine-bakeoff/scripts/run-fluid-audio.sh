#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
harness_package="$root/runtime-harnesses/fluid-audio"
swift build --package-path "$harness_package" --configuration release
harness="$harness_package/.build/release/FluidAudioHarness"
raw_results="$root/.artifacts/results"
mkdir -p "$raw_results"

for version in v2 v3; do
  model="$root/.artifacts/fluid-models/parakeet-tdt-0.6b-$version-coreml"
  "$harness" "$version" default "$model" "$root/fixtures/local-manifest.json" \
    "$raw_results/fluid-audio-parakeet-$version-default-pass-1.json" 10
  "$harness" "$version" default "$model" "$root/fixtures/local-manifest.json" \
    "$raw_results/fluid-audio-parakeet-$version-default-pass-2.json" 10
done

model="$root/.artifacts/fluid-models/parakeet-tdt-0.6b-v3-coreml"
for mode in no-mel dual; do
  "$harness" v3 "$mode" "$model" "$root/fixtures/local-manifest.json" \
    "$raw_results/fluid-audio-parakeet-v3-$mode.json" 10
done

"$root/scripts/report-fluid-audio.py"
"$root/scripts/aggregate-results.py"
