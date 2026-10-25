#!/usr/bin/env python3
"""Face one speech model off against the shipping one, over the whole corpus, in one command.

  ./bakeoff.py run fluid-speech-mini --label fluid-speech-mini
  ./bakeoff.py compare results/fluid-speech-mini/parakeet-v2 \\
      results/fluid-speech-mini/fluid-speech-mini

`run` builds `asr-replay`, then replays every corpus run below through the baseline and then the
candidate, serially, one process per run. The baseline is rerun every time because latency moves
between sessions far more than between engines. Each engine lands in `results/<label>/<engine>/`
as one JSONL per run plus `runtime/<run>.json`; a missing model is downloaded by `asr-replay`
itself through the app's pinned store into `.build/bakeoff-models/`, and the first process after a
download is the one that pays Core ML's first compile. `run` finishes by printing `compare` and saving it beside them.

`compare` scores any engine directories holding those files — `asr-replay` output or a sibling
script's — and leaves a dash for a run a directory does not have. A run that is present must
cover its stage exactly, so a truncated or duplicated file fails rather than scoring flattered.
Engines are the `id`s in `SpeechModel.catalogue`, replayed by `asr-replay` — a FluidAudio-compatible
model is one entry there — plus the `COHERE` targets, replayed by `transcribe_cohere.py` on MLX.
Cohere has no recognition sidecar, so its boosted runs are skipped and score as dashes.
"""

from __future__ import annotations

import argparse
from collections import Counter
from collections.abc import Callable
from dataclasses import dataclass
import json
from pathlib import Path
import shutil
import statistics
import subprocess
import sys
from typing import Any

CORPUS = Path(__file__).resolve().parent
REPOSITORY = CORPUS.parents[4]
sys.path.insert(0, str(CORPUS))

from score_corpus import (  # noqa: E402
    by_id,
    load_jsonl,
    normalize,
    score_terms,
    stage1_report,
    word_diff,
)
import seam_fixtures  # noqa: E402

PACKAGE = REPOSITORY / "Packages/ASREngine"
REPLAY = PACKAGE / ".build/release/asr-replay"
SEAM_AUDIO = REPOSITORY / ".build/seam-fixtures"
# Never the dev channel's engine directory: the app owns that layout and changes it.
MODEL_ROOTS = REPOSITORY / ".build/bakeoff-models"
BASELINE = "parakeet-v2"
SEAM = "seam"
# Superwhisper ships Cohere Transcribe as MLX 4-bit; full precision is the upstream reference.
# The 4-bit weights are a community conversion: quantizing upstream's at load would cost the
# full-precision download and memory, which is not what a 4-bit deployment pays.
COHERE = {
    "cohere-transcribe": [
        "--model", "CohereLabs/cohere-transcribe-03-2026",
        "--revision", "b1eacc2686a3d08ceaae5f24a88b1d519620bc09",
    ],
    "cohere-transcribe-4bit": [
        "--model", "lyzgeorge/cohere-transcribe-03-2026-mlx-4bit",
        "--revision", "f2f6d89b1a300c51f48ae1ecb8523dbb58636cb0",
    ],
}  # fmt: skip
COHERE_RUNTIME = ["--with", "mlx-audio==0.6.1", "--with", "sentencepiece==0.2.2"]


@dataclass(frozen=True)
class Run:
    name: str
    stage: str
    recordings: str
    boosted: bool = False


RUNS = [
    Run("stage1", "stage1-intelligibility.jsonl", "stage1-intelligibility-built-in"),
    Run("stage1-holdout", "stage1-holdout.jsonl", "stage1-holdout-built-in"),
    Run("stage1-longform", "stage1-longform.jsonl", "stage1-longform"),
    Run("field-cases", "field-cases.jsonl", "field-cases"),
    Run("stage2-bare", "stage2-dictionary.jsonl", "stage2-dictionary-built-in"),
    Run(
        "stage2-boosted", "stage2-dictionary.jsonl", "stage2-dictionary-built-in", True
    ),
    Run("stage2-holdout-bare", "stage2-holdout.jsonl", "stage2-holdout-built-in"),
    Run(
        "stage2-holdout-boosted",
        "stage2-holdout.jsonl",
        "stage2-holdout-built-in",
        True,
    ),
    Run("stage3-raw", "stage3-polish.jsonl", "stage3-polish-built-in"),
    Run("stage3-holdout-raw", "stage3-holdout.jsonl", "stage3-holdout-built-in"),
    Run("stage3-layout-raw", "stage3-layout.jsonl", "stage3-layout"),
]
STAGES = {run.name: CORPUS / run.stage for run in RUNS}


# MARK: - Replay


def replay(engine: str, out: Path) -> None:
    (out / "runtime").mkdir(parents=True, exist_ok=True)
    # The fixture definitions travel with the results, so scoring them never needs the audio.
    seam_stage = out / seam_fixtures.FIXTURES_FILE
    shutil.copy(
        seam_fixtures.build(
            STAGES["stage1"],
            CORPUS / "recordings/stage1-intelligibility-built-in",
            SEAM_AUDIO,
        ),
        seam_stage,
    )
    invocations = [
        (
            run.name,
            STAGES[run.name],
            CORPUS / "recordings" / run.recordings,
            run.boosted,
        )
        for run in RUNS
    ] + [(SEAM, seam_stage, SEAM_AUDIO, False)]
    for name, stage, recordings, boosted in invocations:
        files = [
            "--stage",
            str(stage),
            "--recordings",
            str(recordings),
            "--output",
            str(out / f"{name}.jsonl"),
            "--runtime",
            str(out / "runtime" / f"{name}.json"),
        ]
        if engine in COHERE:
            if boosted:
                continue
            command = [
                "uv",
                "run",
                "--no-project",
                *COHERE_RUNTIME,
                "python",
                str(CORPUS / "transcribe_cohere.py"),
                *COHERE[engine],
                *files,
            ]
        else:
            command = [
                str(REPLAY),
                "--engine",
                engine,
                "--model-root",
                str(MODEL_ROOTS / engine),
                *files,
            ]
            if boosted:
                command.append("--boost-from-wants")
        print(f"{engine}: {name}", file=sys.stderr, flush=True)
        log = subprocess.run(command, capture_output=True, text=True)
        if log.returncode != 0:
            sys.exit(f"asr-replay failed on {engine}/{name}:\n{log.stderr}")


def run(args: argparse.Namespace) -> None:
    subprocess.run(
        [
            "swift",
            "build",
            "-c",
            "release",
            "--package-path",
            str(PACKAGE),
            "--product",
            "asr-replay",
        ],
        check=True,
    )
    label_directory = CORPUS / "results" / args.label
    engines = [args.baseline, args.engine]
    for engine in engines:
        replay(engine, label_directory / engine)
    report = comparison([label_directory / engine for engine in engines])
    print(report)
    (label_directory / "comparison.txt").write_text(report + "\n")


# MARK: - Scoring


def stage_file(directory: Path, name: str) -> Path:
    return directory / seam_fixtures.FIXTURES_FILE if name == SEAM else STAGES[name]


def results(directory: Path, name: str) -> list[dict[str, Any]] | None:
    path = directory / f"{name}.jsonl"
    if not path.exists():
        return None
    entries = load_jsonl(path)
    expected = Counter(entry["id"] for entry in load_jsonl(stage_file(directory, name)))
    actual = Counter(entry["id"] for entry in entries)
    if actual != expected:
        missing = sorted((expected - actual).elements())
        unexpected = sorted((actual - expected).elements())
        sys.exit(
            f"{path} does not cover {stage_file(directory, name).name} exactly: "
            f"missing {missing}, unexpected or duplicated {unexpected}"
        )
    return entries


def wer(directory: Path, name: str) -> str:
    entries = results(directory, name)
    if entries is None:
        return "—"
    report = stage1_report(by_id(load_jsonl(STAGES[name])), entries)
    breakdown = (
        f"{report['substitutions']}S {report['deletions']}D {report['insertions']}I"
    )
    return f"{report['wer'] * 100:.2f}% ({breakdown} / {report['words']})"


def terms(directory: Path, name: str) -> dict[str, Any] | None:
    entries = results(directory, name)
    if entries is None:
        return None
    return score_terms(by_id(load_jsonl(STAGES[name])), by_id(entries))


def terms_cell(directory: Path, name: str) -> str:
    score = terms(directory, name)
    if score is None:
        return "—"
    return (
        f"{score['wantsHit']}/{score['wantsTotal']} wants · "
        f"{score['trapsBitten']}/{score['trapsTotal']} traps"
    )


def latencies(directory: Path, name: str) -> list[float] | None:
    entries = results(directory, name)
    return None if entries is None else sorted(e["latencyMs"] for e in entries)


def latency(directory: Path, name: str) -> str:
    values = latencies(directory, name)
    if values is None:
        return "—"
    p90 = values[round(0.9 * (len(values) - 1))]
    return f"{statistics.median(values):.1f} / {p90:.1f} / {values[-1]:.1f} ms"


def realtime(directory: Path, name: str) -> str:
    entries = results(directory, name)
    if entries is None:
        return "—"
    audio = sum(e["audioSeconds"] for e in entries)
    return f"{audio / (sum(e['latencyMs'] for e in entries) / 1000):.0f}x"


def boost_overhead(directory: Path) -> str:
    bare, boosted = (
        latencies(directory, "stage2-bare"),
        latencies(directory, "stage2-boosted"),
    )
    if bare is None or boosted is None:
        return "—"
    return f"{statistics.median(boosted) - statistics.median(bare):+.1f} ms"


def seam(directory: Path) -> str:
    if results(directory, SEAM) is None or results(directory, "stage1") is None:
        return "—"
    report = seam_fixtures.diff(
        directory / seam_fixtures.FIXTURES_FILE,
        directory / f"{SEAM}.jsonl",
        directory / "stage1.jsonl",
    )
    kinds = Counter(change["kind"] for f in report for change in f["changes"])
    changed = sum(fixture["changedWords"] for fixture in report)
    words = sum(fixture["isolatedWords"] for fixture in report)
    return (
        f"{kinds['duplicated']} dup · {kinds['dropped']} dropped · "
        f"{changed}/{words} changed"
    )


def runtimes(directory: Path) -> list[dict[str, Any]]:
    """In replay order, so the first is the process that loaded the model first."""
    paths = [directory / "runtime" / f"{name}.json" for name in [*STAGES, SEAM]]
    return [json.loads(path.read_text()) for path in paths if path.exists()]


def model_size(directory: Path) -> str:
    processes = runtimes(directory)
    if not processes:
        return "—"
    return f"{processes[0]['modelBytes'] / 1e6:.0f} MB"


def download(directory: Path) -> str:
    processes = runtimes(directory)
    if not processes:
        return "—"
    downloads = [p["downloadSeconds"] for p in processes if "downloadSeconds" in p]
    return f"{downloads[0]:.1f} s" if downloads else "already installed"


def first_load(directory: Path) -> str:
    processes = runtimes(directory)
    return f"{processes[0]['loadSeconds']:.2f} s" if processes else "—"


def warm_load(directory: Path) -> str:
    warm = [process["loadSeconds"] for process in runtimes(directory)[1:]]
    return f"{statistics.median(warm):.3f} s" if warm else "—"


def peak_memory(directory: Path) -> str:
    processes = runtimes(directory)
    if not processes:
        return "—"
    return f"{max(p['peakResidentBytes'] for p in processes) / 2**20:.1f} MiB"


ROWS: list[tuple[str, Callable[[Path], str]]] = [
    ("Stage 1 WER", lambda d: wer(d, "stage1")),
    ("Stage 1 holdout WER", lambda d: wer(d, "stage1-holdout")),
    ("Longform WER", lambda d: wer(d, "stage1-longform")),
    ("Field cases WER (say seeded from v2)", lambda d: wer(d, "field-cases")),
    ("Stage 3 raw vs verbatim say", lambda d: wer(d, "stage3-raw")),
    ("Stage 3 holdout raw vs say", lambda d: wer(d, "stage3-holdout-raw")),
    ("Stage 3 layout raw vs say", lambda d: wer(d, "stage3-layout-raw")),
    ("Stage 2 bare", lambda d: terms_cell(d, "stage2-bare")),
    ("Stage 2 boosted", lambda d: terms_cell(d, "stage2-boosted")),
    ("Stage 2 holdout bare", lambda d: terms_cell(d, "stage2-holdout-bare")),
    ("Stage 2 holdout boosted", lambda d: terms_cell(d, "stage2-holdout-boosted")),
    ("Boost overhead (median)", boost_overhead),
    ("Seam fixtures", seam),
    ("Latency stage 1 med/p90/max", lambda d: latency(d, "stage1")),
    ("Latency stage 3 med/p90/max", lambda d: latency(d, "stage3-raw")),
    ("Latency longform med/p90/max", lambda d: latency(d, "stage1-longform")),
    ("Latency seam med/p90/max", lambda d: latency(d, SEAM)),
    ("Real-time factor, stage 1", lambda d: realtime(d, "stage1")),
    ("Real-time factor, longform", lambda d: realtime(d, "stage1-longform")),
    ("Model on disk", model_size),
    ("Download", download),
    ("First process load", first_load),
    ("Warm load (median)", warm_load),
    ("Peak replay RSS", peak_memory),
]


def transcript_differences(directories: list[Path], name: str) -> list[str]:
    """Entries whose normalized transcripts differ, each engine's diff against the script."""
    runs = [results(directory, name) for directory in directories]
    if any(entries is None for entries in runs):
        return []
    scripts = by_id(load_jsonl(STAGES[name]))
    keyed = [by_id(entries) for entries in runs]
    lines = []
    for entry_id in scripts:
        heard = [normalize(entries[entry_id]["transcript"]) for entries in keyed]
        if all(words == heard[0] for words in heard):
            continue
        reference = normalize(scripts[entry_id]["say"])
        lines.append(f"  {entry_id}")
        for directory, words in zip(directories, heard, strict=True):
            lines.append(f"    {directory.name:>20}: {word_diff(reference, words)}")
    return lines


def term_differences(directories: list[Path], name: str) -> list[str]:
    """`wants` hit or `traps` bitten by some engines and not others."""
    scores = [terms(directory, name) for directory in directories]
    if any(score is None for score in scores):
        return []
    lines = []
    for kind, flag in (("wants", "hit"), ("traps", "bitten")):
        for rows in zip(*(score[kind] for score in scores), strict=True):
            outcomes = [row[flag] for row in rows]
            if all(outcome == outcomes[0] for outcome in outcomes):
                continue
            lines.append(f"  {rows[0]['id']} {kind[:-1]} {rows[0]['term']}")
            for directory, row in zip(directories, rows, strict=True):
                lines.append(
                    f"    {directory.name:>20}: {flag if row[flag] else 'no':6} "
                    f"{row['transcript']}"
                )
    return lines


def comparison(directories: list[Path]) -> str:
    table = [["", *[directory.name for directory in directories]]]
    table += [[label, *[cell(d) for d in directories]] for label, cell in ROWS]
    widths = [max(len(row[column]) for row in table) for column in range(len(table[0]))]
    lines = [
        "  ".join(value.ljust(width) for value, width in zip(row, widths, strict=True))
        for row in table
    ]
    sections = [
        (name, transcript_differences)
        for name in ("stage1", "stage1-holdout", "field-cases")
    ] + [
        (name, term_differences)
        for name in (
            "stage2-bare",
            "stage2-boosted",
            "stage2-holdout-bare",
            "stage2-holdout-boosted",
        )
    ]
    for name, differences in sections:
        found = differences(directories, name)
        if found:
            lines += ["", f"{name}: where the engines differ", *found]
    return "\n".join(lines)


def compare(args: argparse.Namespace) -> None:
    for directory in args.directories:
        if not directory.is_dir():
            sys.exit(f"{directory} is not a results directory")
    print(comparison(args.directories))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    commands = parser.add_subparsers(dest="command", required=True)
    run_parser = commands.add_parser(
        "run", help="replay and compare against the baseline"
    )
    run_parser.add_argument(
        "engine", help=f"SpeechModel.catalogue id, or one of {', '.join(COHERE)}"
    )
    run_parser.add_argument("--label", required=True, help="results/<label>/")
    run_parser.add_argument("--baseline", default=BASELINE)
    run_parser.set_defaults(command_function=run)
    compare_parser = commands.add_parser("compare", help="score engine directories")
    compare_parser.add_argument("directories", type=Path, nargs="+")
    compare_parser.set_defaults(command_function=compare)
    args = parser.parse_args()
    args.command_function(args)
    return 0


if __name__ == "__main__":
    sys.exit(main())
