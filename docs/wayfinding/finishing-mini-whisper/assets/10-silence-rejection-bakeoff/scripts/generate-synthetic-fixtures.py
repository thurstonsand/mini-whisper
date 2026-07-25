#!/usr/bin/env python3
import json
import math
from pathlib import Path
import random
import struct
import wave

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "fixtures" / "synthetic"
OUT.mkdir(parents=True, exist_ok=True)
RATE = 16_000


def write(name, samples):
    path = OUT / f"{name}.wav"
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(RATE)
        wav.writeframes(
            b"".join(
                struct.pack("<h", max(-32768, min(32767, round(x * 32767))))
                for x in samples
            )
        )
    return f"synthetic/{path.name}"


def silence(seconds):
    return [0.0] * round(seconds * RATE)


def noise(seconds, amplitude, seed):
    rng = random.Random(seed)
    return [rng.uniform(-amplitude, amplitude) for _ in range(round(seconds * RATE))]


def tone(seconds, amplitude, frequency=220):
    return [
        amplitude * math.sin(2 * math.pi * frequency * i / RATE)
        for i in range(round(seconds * RATE))
    ]


fixtures = [
    {
        "id": "synthetic-zero-short",
        "file": write("zero-short", silence(0.2)),
        "split": "calibration",
        "label": "no_speech",
        "category": "literal-silence",
        "device": "synthetic",
        "room": "synthetic",
        "reference": "",
        "speech_spans": [],
    },
    {
        "id": "synthetic-zero-long",
        "file": write("zero-long", silence(10)),
        "split": "calibration",
        "label": "no_speech",
        "category": "literal-silence",
        "device": "synthetic",
        "room": "synthetic",
        "reference": "",
        "speech_spans": [],
    },
    {
        "id": "synthetic-low-noise",
        "file": write("low-noise", noise(3, 0.002, 2)),
        "split": "calibration",
        "label": "no_speech",
        "category": "noise",
        "device": "synthetic",
        "room": "synthetic",
        "reference": "",
        "speech_spans": [],
    },
    {
        "id": "synthetic-impulses",
        "file": write("impulses", noise(0.2, 0.15, 3) + silence(1.8)),
        "split": "calibration",
        "label": "no_speech",
        "category": "impulse",
        "device": "synthetic",
        "room": "synthetic",
        "reference": "",
        "speech_spans": [],
    },
    {
        "id": "synthetic-tone",
        "file": write("tone", silence(0.4) + tone(0.7, 0.08) + silence(0.4)),
        "split": "calibration",
        "label": "no_speech",
        "category": "non-speech-tone",
        "device": "synthetic",
        "room": "synthetic",
        "reference": "",
        "speech_spans": [],
    },
]
(ROOT / "fixtures" / "synthetic-manifest.json").write_text(
    json.dumps(fixtures, indent=2) + "\n"
)
print(ROOT / "fixtures" / "synthetic-manifest.json")
