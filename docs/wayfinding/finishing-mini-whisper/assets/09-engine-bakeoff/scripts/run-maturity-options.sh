#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

for model in whisper-medium-en whisper-turbo whisper-large-v3; do
  runtime-harnesses/whisper-cpp/run.py "$model" metal \
    ".artifacts/results/maturity-$model-metal.json"
done

"$root/scripts/aggregate-results.py"
