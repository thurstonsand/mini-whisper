#!/usr/bin/env python3
"""Verify fixed inputs and the replay contract without reading or copying audio content into outputs."""

import hashlib
import json
from pathlib import Path
import wave

root = Path(__file__).resolve().parents[1]
corpus = root.parent / "43-dictation-corpus"
results = corpus / "results/voz"
for entry in json.loads((root / "inputs.json").read_text()):
    path = corpus / entry["path"]
    assert path.stat().st_size == entry["bytes"], path
    with path.open("rb") as stream:
        assert hashlib.file_digest(stream, "sha256").hexdigest() == entry["sha256"], (
            path
        )

stages = [
    ("stage1-intelligibility", "stage1-intelligibility-built-in", "stage1"),
    ("stage1-longform", "stage1-longform", "stage1-longform"),
    ("stage2-dictionary", "stage2-dictionary-built-in", "stage2-bare"),
    ("stage3-polish", "stage3-polish-built-in", "stage3-raw"),
    ("stage2-holdout", "stage2-holdout-built-in", "stage2-holdout-bare"),
]
report = {"inputHashesVerified": True, "runs": {}}
for directory in [results, results / "tail-padding-probe"]:
    rows = []
    for stage, recordings, output in stages:
        expected = [
            json.loads(line)["id"]
            for line in (corpus / f"{stage}.jsonl").read_text().splitlines()
        ]
        actual = [
            json.loads(line)
            for line in (directory / f"{output}.jsonl").read_text().splitlines()
        ]
        assert [row["id"] for row in actual] == expected
        for row in actual:
            assert set(row) == {
                "id",
                "transcript",
                "latencyMs",
                "outcome",
                "audioSeconds",
            }
            assert isinstance(row["transcript"], str)
            assert row["latencyMs"] >= 0
            assert row["outcome"] == (
                "transcript" if row["transcript"] else "engineEmpty"
            )
            with wave.open(
                str(corpus / "recordings" / recordings / f"{row['id']}.wav")
            ) as audio:
                assert audio.getframerate() == 16000 and audio.getnchannels() == 1
                assert abs(row["audioSeconds"] - audio.getnframes() / 16000) <= 0.000501
        rows.extend(actual)
    report["runs"][directory.name] = {
        "entries": len(rows),
        "exactFieldsAndOrderedIDs": True,
        "transcriptOutcomes": sum(row["outcome"] == "transcript" for row in rows),
        "emptyIDs": [row["id"] for row in rows if row["outcome"] == "engineEmpty"],
        "audioFormatAndDurationVerified": True,
    }
(results / "validation.json").write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report, indent=2))
