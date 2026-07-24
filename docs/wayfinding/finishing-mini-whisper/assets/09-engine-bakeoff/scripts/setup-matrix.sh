#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
artifacts="$root/.artifacts"
mkdir -p "$artifacts/runtime-models" "$artifacts/onnx-models"

"$root/scripts/setup.sh"

download() {
  local url="$1" destination="$2" bytes="$3" sha256="$4"
  if [[ ! -f "$destination" ]]; then
    curl --fail --location --retry 3 "$url" --output "$destination.partial"
    mv "$destination.partial" "$destination"
  fi
  test "$(stat -f %z "$destination")" = "$bytes"
  echo "$sha256  $destination" | shasum -a 256 --check
}

whisper_cpp="$artifacts/whisper.cpp"
whisper_cpp_revision=f049fff95a089aa9969deb009cdd4892b3e74916
if [[ ! -d "$whisper_cpp/.git" ]]; then
  git clone --filter=blob:none https://github.com/ggml-org/whisper.cpp.git "$whisper_cpp"
fi
git -C "$whisper_cpp" fetch --quiet origin "$whisper_cpp_revision"
git -C "$whisper_cpp" checkout --quiet --detach "$whisper_cpp_revision"
"$root/runtime-harnesses/whisper-cpp/build.sh"

download \
  https://huggingface.co/ggml-org/parakeet-GGUF/resolve/35156454d1a39de06863303dd209fd2bed6ee079/ggml-parakeet-tdt-0.6b-v3-q4_k.bin \
  "$artifacts/runtime-models/whispercpp-parakeet-v3-q4_k.bin" \
  415611879 \
  8b205b8b39c6535e153de6fb11c51db46125d45c4f16ba496fe41a0fe71b885e

download \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-small.en-q5_1.bin \
  "$artifacts/runtime-models/whispercpp-small.en-q5_1.bin" \
  190098681 \
  bfdff4894dcb76bbf647d56263ea2a96645423f1669176f4844a1bf8e478ad30

download \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-medium.en-q5_0.bin \
  "$artifacts/runtime-models/whispercpp-medium.en-q5_0.bin" \
  539225533 \
  76733e26ad8fe1c7a5bf7531a9d41917b2adc0f20f2e4f5531688a8c6cd88eb0

download \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-large-v3-turbo-q5_0.bin \
  "$artifacts/runtime-models/whispercpp-large-v3-turbo-q5_0.bin" \
  574041195 \
  394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2

download \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-large-v3-q5_0.bin \
  "$artifacts/runtime-models/whispercpp-large-v3-q5_0.bin" \
  1081140203 \
  d75795ecff3f83b5faa89d1900604ad8c780abd5739fae406de19f23ecd98ad1

argmax="$artifacts/argmax-oss-swift"
argmax_revision=25c62997041c134b03ca82731ce2f6fd2cae1eb9
if [[ ! -d "$argmax/.git" ]]; then
  git clone --filter=blob:none https://github.com/argmaxinc/argmax-oss-swift.git "$argmax"
fi
git -C "$argmax" fetch --quiet origin "$argmax_revision"
git -C "$argmax" checkout --quiet --detach "$argmax_revision"

fluid_audio="$artifacts/FluidAudio"
fluid_audio_revision=19600a485baa4998812e4654b70d2bab8f2c9949
if [[ ! -d "$fluid_audio/.git" ]]; then
  git clone --filter=blob:none https://github.com/FluidInference/FluidAudio.git "$fluid_audio"
fi
git -C "$fluid_audio" fetch --quiet origin "$fluid_audio_revision"
git -C "$fluid_audio" checkout --quiet --detach "$fluid_audio_revision"

sherpa_venv="$artifacts/sherpa-venv"
if [[ ! -x "$sherpa_venv/bin/python" ]]; then
  uv venv --python 3.12 "$sherpa_venv"
fi
uv pip install --python "$sherpa_venv/bin/python" \
  --requirement "$root/runtime-harnesses/sherpa-onnx/requirements.lock"

mlx_venv="$artifacts/mlx-venv"
if [[ ! -x "$mlx_venv/bin/python" ]]; then
  uv venv --python 3.12 "$mlx_venv"
fi
uv pip install --python "$mlx_venv/bin/python" \
  --requirement "$root/runtime-harnesses/mlx/requirements.lock"

parakeet_onnx_archive="$artifacts/onnx-models/parakeet-v3-int8.tar.bz2"
download \
  https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8.tar.bz2 \
  "$parakeet_onnx_archive" \
  487170055 \
  5793d0fd397c5778d2cf2126994d58e9d56b1be7c04d13c7a15bb1b4eafb16bf
if [[ ! -d "$artifacts/onnx-models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8" ]]; then
  tar -xjf "$parakeet_onnx_archive" -C "$artifacts/onnx-models"
fi

whisper_onnx_archive="$artifacts/onnx-models/whisper-small.en.tar.bz2"
download \
  https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-small.en.tar.bz2 \
  "$whisper_onnx_archive" \
  635693775 \
  0cdba2b8aaab69e04847f3427cc9709574112e67913a1a84b7fec3a8729faa9a
if [[ ! -d "$artifacts/onnx-models/sherpa-onnx-whisper-small.en" ]]; then
  tar -xjf "$whisper_onnx_archive" -C "$artifacts/onnx-models"
fi

export HF_HOME="$artifacts/huggingface"
"$mlx_venv/bin/python" - <<'PY'
from huggingface_hub import snapshot_download

snapshots = [
    ("mlx-community/parakeet-tdt-0.6b-v3", "ed2b7e8c15f9aaa0b5772e2efb986255eaef7e15", None),
    ("mlx-community/whisper-small.en-mlx-4bit", "78852d6d86b5fd23b5d9315e7fcbadbf844bd85b", None),
    ("argmaxinc/whisperkit-coreml", "97a5bf9bbc74c7d9c12c755d04dea59e672e3808", ["openai_whisper-small.en_217MB/**"]),
    ("openai/whisper-small.en", "e8727524f962ee844a7319d92be39ac1bd25655a", ["*.json", "*.txt", "*.tiktoken"]),
    ("FluidInference/parakeet-tdt-0.6b-v2-coreml", "ee09c569f73759e6d44c9bd16766f477b2b36d39", ["Preprocessor.mlmodelc/**", "Encoder.mlmodelc/**", "Decoder.mlmodelc/**", "JointDecision.mlmodelc/**", "parakeet_vocab.json"]),
    ("FluidInference/parakeet-tdt-0.6b-v3-coreml", "aed02740059203c4a87495924f685de3722ae9ce", ["Preprocessor.mlmodelc/**", "Encoder.mlmodelc/**", "Decoder.mlmodelc/**", "JointDecisionv3.mlmodelc/**", "parakeet_vocab.json"]),
]
for repository, revision, patterns in snapshots:
    snapshot_download(repository, revision=revision, allow_patterns=patterns)
PY

fluid_models="$artifacts/fluid-models"
mkdir -p "$fluid_models"
ln -sfn ../huggingface/hub/models--FluidInference--parakeet-tdt-0.6b-v2-coreml/snapshots/ee09c569f73759e6d44c9bd16766f477b2b36d39 \
  "$fluid_models/parakeet-tdt-0.6b-v2-coreml"
ln -sfn ../huggingface/hub/models--FluidInference--parakeet-tdt-0.6b-v3-coreml/snapshots/aed02740059203c4a87495924f685de3722ae9ce \
  "$fluid_models/parakeet-tdt-0.6b-v3-coreml"

swift build --package-path "$root/runtime-harnesses/whisperkit" --configuration release
swift build --package-path "$root/runtime-harnesses/fluid-audio" --configuration release
