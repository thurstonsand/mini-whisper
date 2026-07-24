#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
raw_results="$root/.artifacts/results"
mkdir -p "$raw_results" results

swift build --configuration release
binary="$root/.build/release/EngineBakeoff"
for model in parakeet-v2 parakeet-v3 whisper-turbo whisper-base-en; do
  "$binary" batch "$model" ".artifacts/results/$model.json"
done
stream_fixture="$(python3 - <<'PY'
import json
fixtures = json.load(open('fixtures/local-manifest.json'))['fixtures']
print(min(fixtures, key=lambda fixture: abs(fixture['durationSeconds'] - 10))['id'])
PY
)"
"$binary" stream "$stream_fixture" .artifacts/results/moonshine-streaming-tiny.json

{
  system_profiler SPHardwareDataType SPSoftwareDataType \
    | grep -E 'Model Name:|Model Identifier:|Chip:|Total Number of Cores:|Memory:|System Version:|Kernel Version:'
  xcodebuild -version
  swift --version
  printf 'Architecture: %s\n' "$(uname -m)"
  printf 'transcribe.cpp revision: %s\n' a94e021ef658dc7c788837341a13f6acea3baf3c
  printf 'XCFramework SHA-256: %s\n' b7a3442e2f3552cac1ee71b5e164934dd4db243f6b4b16b1e3e3ed5d1645eefd
  shasum -a 256 models/*.gguf
} > results/environment.txt

"$root/scripts/aggregate-results.py"
