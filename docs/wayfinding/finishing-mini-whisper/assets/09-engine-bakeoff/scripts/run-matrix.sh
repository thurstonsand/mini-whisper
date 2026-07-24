#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
raw_results="$root/.artifacts/results"
mkdir -p "$raw_results" results

swift build --configuration release --product EngineBakeoff
for model in parakeet-v3 whisper-small-en; do
  for backend in metal cpu; do
    .build/release/EngineBakeoff batch "$model" \
      ".artifacts/results/matrix-transcribe-cpp-$model-$backend.json" \
      --backend "$backend"
  done
done

for family in parakeet whisper; do
  for backend in metal cpu; do
    runtime-harnesses/whisper-cpp/run.py "$family" "$backend" \
      ".artifacts/results/matrix-whisper-cpp-$family-$backend.json"
  done
done

for family in parakeet whisper; do
  for provider in cpu coreml; do
    .artifacts/sherpa-venv/bin/python runtime-harnesses/sherpa-onnx/run.py \
      "$family" "$provider" ".artifacts/results/matrix-sherpa-onnx-$family-$provider.json"
  done
done

export HF_HOME="$root/.artifacts/huggingface"
for family in parakeet whisper; do
  .artifacts/mlx-venv/bin/python runtime-harnesses/mlx/run.py \
    "$family" ".artifacts/results/matrix-mlx-$family.json"
done

whisperkit_package="$root/runtime-harnesses/whisperkit"
swift build --package-path "$whisperkit_package" --configuration release
whisperkit="$whisperkit_package/.build/release/WhisperKitHarness"
model="$HF_HOME/hub/models--argmaxinc--whisperkit-coreml/snapshots/97a5bf9bbc74c7d9c12c755d04dea59e672e3808/openai_whisper-small.en_217MB"
tokenizer="$HF_HOME/hub/models--openai--whisper-small.en/snapshots/e8727524f962ee844a7319d92be39ac1bd25655a"
"$whisperkit" "$model" "$tokenizer" "$root/fixtures/local-manifest.json" \
  "$raw_results/matrix-whisperkit-whisper-coreml-pass-1.json"
"$whisperkit" "$model" "$tokenizer" "$root/fixtures/local-manifest.json" \
  "$raw_results/matrix-whisperkit-whisper-coreml-pass-2.json"

"$root/scripts/report-matrix.py"
"$root/scripts/aggregate-results.py"
