#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
revision=8e7ab8ca342c6bb00f9347a25e53fe44543b2a40
model="$HOME/.cache/miniwhisper-research/voz/$revision"
python3 - "$model" "$revision" "$root/weights.json" <<'PY'
import concurrent.futures
import hashlib
import json
from pathlib import Path
import sys
import urllib.request

root, revision, manifest = Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3])
metadata = json.load(urllib.request.urlopen(f"https://huggingface.co/api/models/desert-ant-labs/voz/revision/{revision}"))
assert metadata['sha'] == revision
files = [x['rfilename'] for x in metadata['siblings'] if not x['rfilename'].startswith('.')]
def download(name):
    path = root / name
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists():
        temporary = path.with_name(path.name + '.partial')
        urllib.request.urlretrieve(f"https://huggingface.co/desert-ant-labs/voz/resolve/{revision}/{name}", temporary)
        temporary.rename(path)
    return {'path': name, 'bytes': path.stat().st_size, 'sha256': hashlib.file_digest(path.open('rb'), 'sha256').hexdigest()}
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    records = sorted(pool.map(download, files), key=lambda x: x['path'])
actual = {'repository': 'desert-ant-labs/voz', 'revision': revision, 'files': records}
if manifest.exists():
    assert json.loads(manifest.read_text()) == actual, 'Weight hash/size mismatch'
else:
    manifest.write_text(json.dumps(actual, indent=2) + '\n')
print(f'Verified {len(records)} files, {sum(x["bytes"] for x in records)} bytes in {root}')
PY
cp "$root/resolved-pins.json" "$root/Package.resolved"
swift build -c release --force-resolved-versions --package-path "$root"
