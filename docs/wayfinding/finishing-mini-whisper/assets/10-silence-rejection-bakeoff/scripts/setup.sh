#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
artifacts="$root/.artifacts"
mkdir -p "$artifacts"

clone_at() {
  local url="$1" path="$2" revision="$3"
  if [[ ! -d "$path/.git" ]]; then
    git clone --filter=blob:none "$url" "$path"
  fi
  git -C "$path" fetch --depth 1 origin "$revision"
  git -C "$path" checkout --detach "$revision"
}

clone_at https://github.com/ggml-org/whisper.cpp.git "$artifacts/whisper.cpp" f049fff95a089aa9969deb009cdd4892b3e74916

vad_model="$artifacts/ggml-silero-v6.2.0.bin"
if [[ ! -f "$vad_model" ]]; then
  curl -fL https://huggingface.co/ggml-org/whisper-vad/resolve/9ffd54a1e1ee413ddf265af9913beaf518d1639b/ggml-silero-v6.2.0.bin -o "$vad_model"
fi
echo "2aa269b785eeb53a82983a20501ddf7c1d9c48e33ab63a41391ac6c9f7fb6987  $vad_model" | shasum -a 256 -c -

cmake -S "$artifacts/whisper.cpp" -B "$artifacts/whisper.cpp/build" \
  -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON \
  -DWHISPER_BUILD_EXAMPLES=OFF -DWHISPER_BUILD_TESTS=OFF
cmake --build "$artifacts/whisper.cpp/build" --config Release -j

venv="$artifacts/huggingface-venv"
if [[ ! -x "$venv/bin/python" ]]; then
  python3 -m venv "$venv"
  "$venv/bin/pip" install 'huggingface_hub==0.34.4'
fi
export HF_HOME="$artifacts/huggingface"
"$venv/bin/python" - <<'PY'
import os
from huggingface_hub import snapshot_download
snapshot_download(
    "FluidInference/parakeet-tdt-0.6b-v2-coreml",
    revision="ee09c569f73759e6d44c9bd16766f477b2b36d39",
    allow_patterns=[
        "Preprocessor.mlmodelc/**", "Encoder.mlmodelc/**", "Decoder.mlmodelc/**",
        "JointDecision.mlmodelc/**", "parakeet_vocab.json",
    ],
)
snapshot_download(
    "FluidInference/silero-vad-coreml",
    revision="b419383c55c110e2c9271fa6ee0ea83d03c70d96",
    allow_patterns=["silero-vad-unified-256ms-v6.2.1.mlmodelc/**", "config.json"],
)
PY

model="$artifacts/huggingface/hub/models--FluidInference--parakeet-tdt-0.6b-v2-coreml/snapshots/ee09c569f73759e6d44c9bd16766f477b2b36d39"
ln -sfn "$model" "$artifacts/parakeet-v2"
vad_model="$artifacts/huggingface/hub/models--FluidInference--silero-vad-coreml/snapshots/b419383c55c110e2c9271fa6ee0ea83d03c70d96"
mkdir -p "$artifacts/vad/Models"
ln -sfn "$vad_model" "$artifacts/vad/Models/silero-vad"
swift build --package-path "$root" --configuration release
"$root/scripts/generate-synthetic-fixtures.py"
