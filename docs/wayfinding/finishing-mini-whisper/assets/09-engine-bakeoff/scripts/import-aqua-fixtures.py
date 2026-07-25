#!/usr/bin/env python3

import json
from pathlib import Path
import shutil

root = Path(__file__).resolve().parent.parent
selection_path = root / ".artifacts" / "fixture-selection.json"
local_manifest_path = root / "fixtures" / "local-manifest.json"
aqua_root = Path.home() / "Library" / "Application Support" / "Aqua Voice"
history_path = aqua_root / "settings.json"
history_items = [
    item
    for item in json.loads(history_path.read_text())["history"]
    if item.get("audioFilePath") and item.get("rawText")
]
history = {Path(item["audioFilePath"]).name: item for item in history_items}

if selection_path.exists():
    saved = json.loads(selection_path.read_text())
    fixtures = saved["fixtures"] if isinstance(saved, dict) else saved
else:
    available = [
        item
        for item in history_items
        if (aqua_root / "audio" / Path(item["audioFilePath"]).name).exists()
    ]
    available.sort(
        key=lambda item: (item.get("audioDurationSeconds", 0), item["timestamp"])
    )
    count = min(24, len(available))
    if count < 2:
        raise SystemExit("Aqua Voice does not contain enough retained audio fixtures")
    indexes = [
        round(index * (len(available) - 1) / (count - 1)) for index in range(count)
    ]
    fixtures = []
    for index, history_index in enumerate(indexes, start=1):
        item = available[history_index]
        fixtures.append(
            {
                "id": f"fixture-{index:02d}",
                "sourceFilename": Path(item["audioFilePath"]).name,
                "filename": f"fixture-{index:02d}.wav",
                "durationSeconds": item["audioDurationSeconds"],
                "reference": item["rawText"],
            }
        )
    selection_path.parent.mkdir(parents=True, exist_ok=True)
    selection_path.write_text(
        json.dumps({"schemaVersion": 1, "fixtures": fixtures}, indent=2) + "\n"
    )

for index, fixture in enumerate(fixtures, 1):
    source_name = fixture["sourceFilename"]
    item = history.get(source_name)
    if item is None:
        raise SystemExit(
            f"Aqua Voice history no longer contains private fixture {index}"
        )
    if item["rawText"] != fixture["reference"]:
        raise SystemExit(f"Aqua Voice reference changed for private fixture {index}")

    source = aqua_root / "audio" / source_name
    destination = root / "fixtures" / fixture["filename"]
    if not source.exists():
        raise SystemExit(f"Aqua Voice audio is missing for private fixture {index}")
    shutil.copy2(source, destination)

local_manifest_path.write_text(
    json.dumps({"schemaVersion": 1, "fixtures": fixtures}, indent=2) + "\n"
)
print(f"imported {len(fixtures)} private fixtures")
print(local_manifest_path)
