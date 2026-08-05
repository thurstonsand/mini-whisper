#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
artifacts="$root/.artifacts"
fluid_audio="$artifacts/FluidAudio"
fluid_audio_revision=19600a485baa4998812e4654b70d2bab8f2c9949
model_revision=fccec19ecf93b40969d4888f27e10d714daeb3cf

mkdir -p "$artifacts"
if [[ ! -d "$fluid_audio/.git" ]]; then
  git clone --filter=blob:none https://github.com/FluidInference/FluidAudio.git "$fluid_audio"
fi
git -C "$fluid_audio" fetch --quiet origin "$fluid_audio_revision"
git -C "$fluid_audio" checkout --quiet --detach "$fluid_audio_revision"
test "$(git -C "$fluid_audio" rev-parse HEAD)" = "$fluid_audio_revision"

venv="$artifacts/huggingface-venv"
if [[ ! -x "$venv/bin/python" ]]; then
  uv venv --python 3.12 "$venv"
fi
uv pip install --python "$venv/bin/python" --requirement "$root/requirements.lock"

export HF_HOME="$artifacts/huggingface"
"$venv/bin/python" - "$artifacts/model" "$model_revision" <<'PY'
from huggingface_hub import snapshot_download
from pathlib import Path
import sys

destination = Path(sys.argv[1])
revision = sys.argv[2]
snapshot_download(
    "FluidInference/cohere-transcribe-03-2026-coreml",
    revision=revision,
    local_dir=destination,
    allow_patterns=[
        "q8/cohere_encoder.mlmodelc/**",
        "q8/cohere_decoder_cache_external_v2.mlmodelc/**",
        "vocab.json",
    ],
)
PY

test "$(stat -f %z "$artifacts/model/q8/cohere_encoder.mlmodelc/weights/weight.bin")" = 1881964672
echo "f2992beb02730c9b751fe73c0fd898d83b013241531793e659776e5b3b9bc8a7  $artifacts/model/q8/cohere_encoder.mlmodelc/weights/weight.bin" | shasum -a 256 --check
test "$(stat -f %z "$artifacts/model/q8/cohere_decoder_cache_external_v2.mlmodelc/weights/weight.bin")" = 304453120
echo "86eac4bce6ca5d4ca49f5bf1078a1b42ab75f59d7c809678592a493742c29568  $artifacts/model/q8/cohere_decoder_cache_external_v2.mlmodelc/weights/weight.bin" | shasum -a 256 --check

swift build --package-path "$root" --configuration release
