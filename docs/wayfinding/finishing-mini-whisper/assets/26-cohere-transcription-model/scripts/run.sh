#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
bakeoff="$(cd "$root/../09-engine-bakeoff" && pwd)"
aqua_audio="$HOME/Library/Application Support/Aqua Voice/audio"
output="$root/.artifacts/results/cohere-local.json"

mkdir -p "$(dirname "$output")"
manifest="$bakeoff/fixtures/local-manifest.json"
test -f "$manifest"
test -d "$aqua_audio"
python3 - "$manifest" "$aqua_audio" <<'PY'
import json
from pathlib import Path
import sys

manifest = Path(sys.argv[1])
audio_root = Path(sys.argv[2])
fixtures = json.loads(manifest.read_text())["fixtures"]
missing = [fixture for fixture in fixtures if not (audio_root / fixture["sourceFilename"]).is_file()]
if missing:
    raise SystemExit(
        f"required bakeoff corpus is unavailable: {len(missing)}/{len(fixtures)} private WAVs are missing"
    )
PY

"$root/.build/release/CohereTranscriptionHarness" \
  "$root/.artifacts/model" \
  "$manifest" \
  "$aqua_audio" \
  "$output"
