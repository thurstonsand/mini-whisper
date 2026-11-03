#!/usr/bin/env python3
"""Replay a corpus stage through Fluid Speech Pro on NVIDIA NeMo, writing asr-replay JSONL.

The repository publishes only a `.nemo`: Parakeet TDT 0.6B v3 with one extra residual block between
subsampling and the first Conformer layer, which plain `restore_from` rejects. `load_model` adds
that block the way the repository's own `fluid_speech.py` does, rather than importing that file,
then loads every tensor strictly. `--clean-mode` folds in the published low-rank adapter that drops
repeated and filler words.

`--runtime` writes the same runtime record `asr-replay` does, so `bakeoff.py` can compare the two.
Load runs from resolving the cached weights through the warmup transcription; a download is timed
apart, and only happens when the weights are not cached. Each recording is decoded before its
timer starts, as `asr-replay` does.
"""

import argparse
import json
import os
from pathlib import Path
import resource
import sys
import tarfile
import tempfile
import time

import numpy as np

MODEL = "FluidVoice-Labs/fluid-speech-pro"
REVISION = "53f490b9292c5943847f635b7abfc3f123018964"
NEMO_FILE = "fluid-speech-pro.nemo"
CLEAN_MODE_FILE = "clean-mode.safetensors"


def read_samples(path: Path) -> np.ndarray:
    """16 kHz mono like `asr-replay` demands; field cases are float WAVs, the rest int16."""
    import soundfile

    samples, sample_rate = soundfile.read(path, dtype="float32")
    if sample_rate != 16000 or samples.ndim != 1:
        raise ValueError(f"{path} is not 16 kHz mono")
    return samples


def peak_rss_bytes() -> int:
    # macOS reports ru_maxrss in bytes, unlike Linux's KiB.
    return resource.getrusage(resource.RUSAGE_SELF).ru_maxrss


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", type=Path, required=True)
    parser.add_argument("--recordings", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--model", default=MODEL)
    parser.add_argument("--revision", default=REVISION)
    parser.add_argument("--clean-mode", action="store_true")
    parser.add_argument("--device", choices=("cpu", "mps"), default="mps")
    parser.add_argument("--runtime", type=Path, help="JSON destination: load, memory")
    return parser.parse_args()


def resolve_weights(args: argparse.Namespace) -> tuple[list[Path], float | None]:
    """The cached files, downloading them first if needed; returns the download seconds."""
    from huggingface_hub import hf_hub_download
    from huggingface_hub.errors import LocalEntryNotFoundError

    names = [NEMO_FILE, CLEAN_MODE_FILE] if args.clean_mode else [NEMO_FILE]

    def files(local_files_only: bool) -> list[Path]:
        return [
            Path(
                hf_hub_download(
                    args.model,
                    name,
                    revision=args.revision,
                    local_files_only=local_files_only,
                )
            )
            for name in names
        ]

    try:
        return files(local_files_only=True), None
    except LocalEntryNotFoundError:
        started = time.monotonic()
        paths = files(local_files_only=False)
        return paths, time.monotonic() - started


def load_model(args: argparse.Namespace, weights: list[Path]):
    from nemo.collections.asr.models import ASRModel
    import torch
    import torch.nn as nn

    class FrameCleaner(nn.Module):
        def __init__(self, width: int, dim: int, kernel: int):
            super().__init__()
            self.ln = nn.LayerNorm(width)
            self.down = nn.Linear(width, dim)
            self.mix = nn.Conv1d(dim, dim, kernel, padding=kernel // 2, groups=dim)
            self.up = nn.Linear(dim, width)

        def forward(self, x):
            h = self.down(self.ln(x)).transpose(1, 2)
            return x + self.up(nn.functional.gelu(self.mix(h)).transpose(1, 2))

    nemo_path = weights[0]
    model = ASRModel.restore_from(str(nemo_path), map_location="cpu", strict=False)
    spec = model.cfg.fluid_speech
    encoder = model.encoder
    encoder.fv_insert = FrameCleaner(
        encoder.d_model, spec.insert_dim, spec.insert_kernel
    )

    def clean_frames(module, inputs, out):
        if isinstance(out, tuple):
            return (encoder.fv_insert(out[0]), *out[1:])
        return encoder.fv_insert(out)

    encoder.pre_encode.register_forward_hook(clean_frames)

    with tarfile.open(nemo_path) as tar, tempfile.TemporaryDirectory() as tmp:
        member = next(
            m
            for m in tar.getmembers()
            if os.path.basename(m.name) == "model_weights.ckpt"
        )
        tar.extract(member, tmp, filter="data")
        state = torch.load(
            os.path.join(tmp, member.name), map_location="cpu", weights_only=True
        )
    if args.clean_mode:
        from safetensors import safe_open

        with safe_open(weights[1], framework="pt") as adapter:
            scale = float(adapter.metadata()["alpha"]) / int(adapter.metadata()["rank"])
            tensors = adapter.keys()  # safe_open is not iterable
            for name in sorted({key.rsplit(".", 1)[0] for key in tensors}):
                key = f"encoder.{name}.weight"
                delta = scale * (
                    adapter.get_tensor(f"{name}.B") @ adapter.get_tensor(f"{name}.A")
                )
                state[key] = state[key] + delta.view_as(state[key]).to(state[key].dtype)
    model.load_state_dict(state, strict=True)
    return model.eval().to(args.device)


def transcribe(model, samples: np.ndarray) -> str:
    (hypothesis,) = model.transcribe([samples], batch_size=1, verbose=False)
    return hypothesis.text.strip()


def main() -> int:
    args = parse_args()
    entries = [
        json.loads(line)
        for line in args.stage.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    recordings = [(entry, args.recordings / f"{entry['id']}.wav") for entry in entries]
    missing = [path for _, path in recordings if not path.exists()]
    if missing:
        raise FileNotFoundError(f"missing recording: {missing[0]}")

    weights, download_seconds = resolve_weights(args)
    started = time.monotonic()
    model = load_model(args, weights)
    transcribe(model, read_samples(recordings[0][1]))
    load_seconds = time.monotonic() - started
    args.output.parent.mkdir(parents=True, exist_ok=True)

    with args.output.open("w", encoding="utf-8") as sink:
        for entry, wav in recordings:
            samples = read_samples(wav)
            started = time.monotonic()
            transcript = transcribe(model, samples)
            latency_ms = (time.monotonic() - started) * 1000
            sink.write(
                json.dumps(
                    {
                        "audioSeconds": len(samples) / 16000,
                        "id": entry["id"],
                        "latencyMs": latency_ms,
                        "outcome": "transcript",
                        "transcript": transcript,
                    },
                    sort_keys=True,
                )
                + "\n"
            )
            print(f"{entry['id']}: {latency_ms:.0f} ms  {transcript}")

    peak = peak_rss_bytes()
    print(
        f"model load: {load_seconds * 1000:.0f} ms; peak RSS: {peak / 2**20:.0f} MiB",
        file=sys.stderr,
    )
    if args.runtime:
        clean = " clean-mode" if args.clean_mode else ""
        runtime = {
            "identity": f"{args.model}@{args.revision}{clean} nemo-{args.device}",
            "stage": args.stage.name,
            "entries": len(recordings),
            "loadSeconds": load_seconds,
            "peakResidentBytes": peak,
            "modelBytes": sum(path.stat().st_size for path in weights),
        }
        if download_seconds is not None:
            runtime["downloadSeconds"] = download_seconds
        args.runtime.write_text(json.dumps(runtime, indent=2, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
