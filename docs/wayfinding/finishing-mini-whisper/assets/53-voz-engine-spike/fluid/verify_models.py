#!/usr/bin/env python3
"""Verify the effective FluidAudio cache directory against the recorded pinned snapshot."""

import argparse
import hashlib
import json
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("model_root", type=Path)
parser.add_argument("manifest", type=Path)
args = parser.parse_args()
manifest = json.loads(args.manifest.read_text())
root = args.model_root.parent / "parakeet-tdt-0.6b-v3"
for entry in manifest["files"]:
    path = root / entry["path"]
    data = path.read_bytes()
    if (
        len(data) != entry["bytes"]
        or hashlib.sha256(data).hexdigest() != entry["sha256"]
    ):
        raise SystemExit(f"Pinned model mismatch: {path}")
print(
    f"Verified {len(manifest['files'])} files, {manifest['totalBytes']} bytes at {root}"
)
