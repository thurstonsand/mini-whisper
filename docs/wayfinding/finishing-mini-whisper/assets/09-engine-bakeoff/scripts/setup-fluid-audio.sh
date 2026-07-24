#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
artifacts="$root/.artifacts"
fluid_audio="$artifacts/FluidAudio"
fluid_audio_revision=19600a485baa4998812e4654b70d2bab8f2c9949
mkdir -p "$artifacts"

if [[ ! -d "$fluid_audio/.git" ]]; then
  git clone --filter=blob:none https://github.com/FluidInference/FluidAudio.git "$fluid_audio"
fi
git -C "$fluid_audio" fetch --quiet origin "$fluid_audio_revision"
git -C "$fluid_audio" checkout --quiet --detach "$fluid_audio_revision"

venv="$artifacts/huggingface-venv"
if [[ ! -x "$venv/bin/python" ]]; then
  uv venv --python 3.12 "$venv"
fi
uv pip install --python "$venv/bin/python" \
  --requirement "$root/runtime-harnesses/fluid-audio/requirements.lock"

export HF_HOME="$artifacts/huggingface"
"$venv/bin/python" - <<'PY'
from huggingface_hub import snapshot_download

snapshots = [
    (
        "FluidInference/parakeet-tdt-0.6b-v2-coreml",
        "ee09c569f73759e6d44c9bd16766f477b2b36d39",
        ["Preprocessor.mlmodelc/**", "Encoder.mlmodelc/**", "Decoder.mlmodelc/**", "JointDecision.mlmodelc/**", "parakeet_vocab.json"],
    ),
    (
        "FluidInference/parakeet-tdt-0.6b-v3-coreml",
        "aed02740059203c4a87495924f685de3722ae9ce",
        ["Preprocessor.mlmodelc/**", "Encoder.mlmodelc/**", "Decoder.mlmodelc/**", "JointDecisionv3.mlmodelc/**", "parakeet_vocab.json"],
    ),
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

"$venv/bin/python" - "$root/results/fluid-audio-model-hashes.txt" "$fluid_models" <<'PY'
import hashlib
import sys
from pathlib import Path

hash_file, models = map(Path, sys.argv[1:])
version = None
expected = {}
for line in hash_file.read_text().splitlines():
    if line.startswith("["):
        version = line[1:-1]
    elif line:
        digest, relative_path = line.split(maxsplit=1)
        expected[(version, relative_path)] = digest
for (version, relative_path), digest in expected.items():
    path = models / f"parakeet-tdt-0.6b-{version}-coreml" / relative_path
    actual = hashlib.sha256(path.read_bytes()).hexdigest()
    if actual != digest:
        raise SystemExit(f"SHA-256 mismatch: {path}")
print(f"verified {len(expected)} FluidAudio model files")
PY

"$root/scripts/import-aqua-fixtures.py"
swift build --package-path "$root/runtime-harnesses/fluid-audio" --configuration release
