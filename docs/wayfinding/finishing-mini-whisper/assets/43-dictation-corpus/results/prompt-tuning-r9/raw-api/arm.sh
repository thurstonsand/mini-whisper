#!/bin/bash
# ./arm.sh <candidate> : round 8's guard set on the raw API for candidates/<candidate>.txt, without
# Additional Instructions. Writes runs/<candidate>/.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
label=$1
P=$HERE/candidates/$label.txt
OUT=$HERE/runs/$label
mkdir -p "$OUT"
cd "$HERE/../../prompt-tuning-haiku"
T="--provider anthropic-api --metered"
./tune.py stage3 $T --prompt "$P" --repeat 10 --label "$label" --output "$OUT/frozen10.json" > "$OUT/frozen10.txt" 2>&1
./tune.py stage3 $T --holdout --prompt "$P" --repeat 10 --label "$label" --output "$OUT/holdout10.json" > "$OUT/holdout10.txt" 2>&1
./tune.py stage3 $T --prompt "$P" --script ../../stage3-layout.jsonl --raw ../prompt-tuning-r4/stage3-layout-raw.jsonl --include-excluded --repeat 10 --label "$label" --output "$OUT/layout10.json" > "$OUT/layout10.txt" 2>&1
for i in 1 2 3; do ./tune.py stage2 $T --prompt "$P" --output "$OUT/stage2-$i.jsonl" >> "$OUT/stage2.txt" 2>&1; done
./perturb.py $T --prompt "$P" --repeat 10 --out "$OUT/grid" > "$OUT/grid.txt" 2>&1
