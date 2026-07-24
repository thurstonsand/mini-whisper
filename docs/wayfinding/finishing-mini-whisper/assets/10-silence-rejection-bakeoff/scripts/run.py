#!/usr/bin/env python3
import argparse
import ctypes
import json
import math
import statistics
import subprocess
import time
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FRAME = 512
RATE = 16_000
IRREGULAR_BUFFERS = [73, 511, 128, 2048, 17, 960, 333, 4096, 255]


class VadParams(ctypes.Structure):
    _fields_ = [
        ("threshold", ctypes.c_float),
        ("min_speech_duration_ms", ctypes.c_int),
        ("min_silence_duration_ms", ctypes.c_int),
        ("max_speech_duration_s", ctypes.c_float),
        ("speech_pad_ms", ctypes.c_int),
        ("samples_overlap", ctypes.c_float),
    ]


class VadContextParams(ctypes.Structure):
    _fields_ = [("n_threads", ctypes.c_int), ("use_gpu", ctypes.c_bool), ("gpu_device", ctypes.c_int)]


class Silero:
    def __init__(self, library, model):
        self.lib = ctypes.CDLL(str(library))
        self.log_callback = ctypes.CFUNCTYPE(None, ctypes.c_int, ctypes.c_char_p, ctypes.c_void_p)(lambda _level, _text, _user_data: None)
        self.lib.whisper_log_set.argtypes = [type(self.log_callback), ctypes.c_void_p]
        self.lib.whisper_log_set(self.log_callback, None)
        self.lib.whisper_vad_default_context_params.restype = VadContextParams
        self.lib.whisper_vad_default_params.restype = VadParams
        self.lib.whisper_vad_init_from_file_with_params.argtypes = [ctypes.c_char_p, VadContextParams]
        self.lib.whisper_vad_init_from_file_with_params.restype = ctypes.c_void_p
        self.lib.whisper_vad_detect_speech.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_float), ctypes.c_int]
        self.lib.whisper_vad_detect_speech.restype = ctypes.c_bool
        self.lib.whisper_vad_detect_speech_no_reset.argtypes = self.lib.whisper_vad_detect_speech.argtypes
        self.lib.whisper_vad_detect_speech_no_reset.restype = ctypes.c_bool
        self.lib.whisper_vad_reset_state.argtypes = [ctypes.c_void_p]
        self.lib.whisper_vad_n_probs.argtypes = [ctypes.c_void_p]
        self.lib.whisper_vad_n_probs.restype = ctypes.c_int
        self.lib.whisper_vad_probs.argtypes = [ctypes.c_void_p]
        self.lib.whisper_vad_probs.restype = ctypes.POINTER(ctypes.c_float)
        self.lib.whisper_vad_segments_from_probs.argtypes = [ctypes.c_void_p, VadParams]
        self.lib.whisper_vad_segments_from_probs.restype = ctypes.c_void_p
        self.lib.whisper_vad_segments_n_segments.argtypes = [ctypes.c_void_p]
        self.lib.whisper_vad_segments_n_segments.restype = ctypes.c_int
        self.lib.whisper_vad_segments_get_segment_t0.argtypes = [ctypes.c_void_p, ctypes.c_int]
        self.lib.whisper_vad_segments_get_segment_t0.restype = ctypes.c_float
        self.lib.whisper_vad_segments_get_segment_t1.argtypes = [ctypes.c_void_p, ctypes.c_int]
        self.lib.whisper_vad_segments_get_segment_t1.restype = ctypes.c_float
        self.lib.whisper_vad_free_segments.argtypes = [ctypes.c_void_p]
        self.lib.whisper_vad_free.argtypes = [ctypes.c_void_p]
        params = self.lib.whisper_vad_default_context_params()
        params.use_gpu = False
        self.context = self.lib.whisper_vad_init_from_file_with_params(str(model).encode(), params)
        if not self.context:
            raise RuntimeError(f"could not load {model}")

    def close(self):
        self.lib.whisper_vad_free(self.context)

    @staticmethod
    def array(samples):
        return (ctypes.c_float * len(samples))(*samples)

    def detect(self, samples):
        values = self.array(samples)
        started = time.perf_counter_ns()
        if not self.lib.whisper_vad_detect_speech(self.context, values, len(samples)):
            raise RuntimeError("Silero inference failed")
        elapsed_ms = (time.perf_counter_ns() - started) / 1_000_000
        count = self.lib.whisper_vad_n_probs(self.context)
        pointer = self.lib.whisper_vad_probs(self.context)
        return [pointer[i] for i in range(count)], elapsed_ms

    def segments(self, threshold, minimum_speech_ms):
        params = self.lib.whisper_vad_default_params()
        params.threshold = threshold
        params.min_speech_duration_ms = minimum_speech_ms
        result = self.lib.whisper_vad_segments_from_probs(self.context, params)
        count = self.lib.whisper_vad_segments_n_segments(result)
        segments = [
            {
                "start_seconds": round(float(self.lib.whisper_vad_segments_get_segment_t0(result, i)) / 100, 3),
                "end_seconds": round(float(self.lib.whisper_vad_segments_get_segment_t1(result, i)) / 100, 3),
            }
            for i in range(count)
        ]
        self.lib.whisper_vad_free_segments(result)
        return segments

    def replay_irregular(self, samples):
        self.lib.whisper_vad_reset_state(self.context)
        pending = []
        probabilities = []
        availability_seconds = []
        cursor = 0
        index = 0
        while cursor < len(samples):
            size = IRREGULAR_BUFFERS[index % len(IRREGULAR_BUFFERS)]
            pending.extend(samples[cursor : cursor + size])
            cursor += size
            index += 1
            while len(pending) >= FRAME:
                chunk = self.array(pending[:FRAME])
                del pending[:FRAME]
                if not self.lib.whisper_vad_detect_speech_no_reset(self.context, chunk, FRAME):
                    raise RuntimeError("streaming Silero inference failed")
                probabilities.append(self.lib.whisper_vad_probs(self.context)[0])
                availability_seconds.append(min(cursor, len(samples)) / RATE)
        if pending:
            chunk = self.array(pending)
            if not self.lib.whisper_vad_detect_speech_no_reset(self.context, chunk, len(pending)):
                raise RuntimeError("streaming Silero tail inference failed")
            probabilities.append(self.lib.whisper_vad_probs(self.context)[0])
            availability_seconds.append(len(samples) / RATE)
        return probabilities, availability_seconds


def endpoint_latencies(probabilities, availability_seconds, threshold):
    required_silence_frames = math.ceil(100 / (FRAME / RATE * 1000))
    active = False
    silence_frames = 0
    latencies = []
    for index, probability in enumerate(probabilities):
        if probability >= threshold:
            active = True
            silence_frames = 0
        elif active:
            silence_frames += 1
            if silence_frames == required_silence_frames:
                last_speech_frame = index - required_silence_frames
                acoustic_end = (last_speech_frame + 1) * FRAME / RATE
                latencies.append((availability_seconds[index] - acoustic_end) * 1000)
                active = False
                silence_frames = 0
    return latencies


def load_wav(path):
    with wave.open(str(path), "rb") as wav:
        if (wav.getnchannels(), wav.getframerate(), wav.getsampwidth(), wav.getcomptype()) != (1, RATE, 2, "NONE"):
            raise ValueError(f"{path}: expected mono 16 kHz PCM16 WAV")
        frames = wav.readframes(wav.getnframes())
    integers = memoryview(frames).cast("h")
    return [sample / 32768 for sample in integers]


def rms(samples):
    return math.sqrt(sum(sample * sample for sample in samples) / len(samples)) if samples else 0


def rms_metrics(samples):
    frame_size = RATE // 10
    frames = [samples[i : i + frame_size] for i in range(0, len(samples), frame_size)]
    frame_values = [rms(frame) for frame in frames]
    return {
        "whole": rms(samples),
        "frame_max": max(frame_values, default=0),
        "frames": frame_values,
    }


def candidates():
    values = {(0.5, 250)}
    values.update((threshold, minimum) for threshold in (0.35, 0.5, 0.65) for minimum in (96, 160, 250))
    return [{"threshold": threshold, "minimum_speech_ms": minimum} for threshold, minimum in sorted(values)]


def rms_candidates():
    return [
        {"shape": shape, "threshold": threshold}
        for shape in ("whole", "framed")
        for threshold in (0.001, 0.005, 0.01, 0.02)
    ]


def rms_key(settings):
    return f"{settings['shape']}-rms-{settings['threshold']:.3f}"


def decision_key(settings):
    return f"t{settings['threshold']:.2f}-m{settings['minimum_speech_ms']}"


def counts(fixtures, key, split, decision_field="decisions"):
    selected = [fixture for fixture in fixtures if fixture["split"] == split]
    false_accepts = sum(fixture["label"] == "no_speech" and fixture[decision_field][key] for fixture in selected)
    false_rejects = sum(fixture["label"] == "speech" and not fixture[decision_field][key] for fixture in selected)
    return {"fixtures": len(selected), "false_accepts": false_accepts, "false_rejects": false_rejects}


def transcribe(manifest, output):
    executable = ROOT / ".build" / "release" / "SilenceBakeoffTranscriber"
    subprocess.run([str(executable), str(ROOT / ".artifacts" / "parakeet-v2"), str(manifest), str(output)], check=True)
    return {item["id"]: item for item in json.loads(output.read_text())}


def markdown(result):
    selected = result["selected_settings"]
    lines = [
        "# Silence rejection bakeoff results",
        "",
        f"Selected on calibration: Silero threshold `{selected['threshold']}`, minimum speech `{selected['minimum_speech_ms']} ms`.",
        "",
        "| Split | Fixtures | False accepts | False rejects | Nonempty no-speech transcripts | Skipped decodes |",
        "| --- | ---: | ---: | ---: | ---: | ---: |",
    ]
    for split in ("calibration", "holdout"):
        summary = result["summary"][split]
        lines.append(f"| {split} | {summary['fixtures']} | {summary['false_accepts']} | {summary['false_rejects']} | {summary['nonempty_no_speech_transcripts']} | {summary['skipped_decodes']} |")
    lines += [
        "",
        "| Baseline selected on calibration | Threshold | Calibration FA / FR | Holdout FA / FR |",
        "| --- | ---: | ---: | ---: |",
    ]
    for baseline in result["rms_baselines"]:
        lines.append(
            f"| {baseline['shape']} RMS | {baseline['threshold']:.3f} | {baseline['calibration']['false_accepts']} / {baseline['calibration']['false_rejects']} | {baseline['holdout']['false_accepts']} / {baseline['holdout']['false_rejects']} |"
        )
    lines += [
        "",
        f"Median VAD runtime: `{result['runtime']['vad_median_ms']:.3f} ms`; median decoder runtime: `{result['runtime']['decoder_median_ms']}`.",
        f"Irregular-buffer probability equivalence: `{result['boundary']['maximum_probability_delta']:.8f}` maximum delta.",
        "",
        "## Fixture judgments",
        "",
        "| Fixture | Split | Label | Gate | No-gate transcript | Onset clip | Endpoint latency |",
        "| --- | --- | --- | --- | --- | ---: | ---: |",
    ]
    for fixture in result["fixtures"]:
        transcript = (fixture.get("no_gate_transcript") or "").replace("|", "\\|")
        lines.append(
            f"| {fixture['id']} | {fixture['split']} | {fixture['label']} | {'accept' if fixture['selected_accepts'] else 'reject'} | {transcript or '—'} | {fixture.get('onset_clipping_ms', '—')} | {fixture.get('endpoint_latency_ms', '—')} |"
        )
    lines += ["", "## Acceptance", ""]
    for name, passed in result["acceptance"].items():
        lines.append(f"- {'PASS' if passed else 'FAIL'} — {name.replace('_', ' ')}")
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--skip-asr", action="store_true")
    parser.add_argument("--output", type=Path, default=ROOT / "results" / "raw.json")
    args = parser.parse_args()
    manifest = args.manifest.resolve()
    fixture_data = json.loads(manifest.read_text())
    library_matches = list((ROOT / ".artifacts" / "whisper.cpp" / "build").glob("**/libwhisper.dylib"))
    if not library_matches:
        raise RuntimeError("run scripts/setup.sh first")
    vad = Silero(library_matches[0], ROOT / ".artifacts" / "ggml-silero-v6.2.0.bin")
    settings = candidates()
    results = []
    try:
        for fixture in fixture_data:
            samples = load_wav(manifest.parent / fixture["file"])
            probabilities, runtime_ms = vad.detect(samples)
            decisions = {}
            segments = {}
            for candidate in settings:
                key = decision_key(candidate)
                value = vad.segments(candidate["threshold"], candidate["minimum_speech_ms"])
                decisions[key] = bool(value)
                segments[key] = value
            irregular, availability_seconds = vad.replay_irregular(samples)
            maximum_delta = max((abs(a - b) for a, b in zip(probabilities, irregular)), default=0)
            if len(probabilities) != len(irregular):
                maximum_delta = math.inf
            rms_result = rms_metrics(samples)
            baseline_decisions = {
                rms_key(candidate): rms_result["whole" if candidate["shape"] == "whole" else "frame_max"] >= candidate["threshold"]
                for candidate in rms_candidates()
            }
            results.append({
                **fixture,
                "duration_seconds": len(samples) / RATE,
                "rms": rms_result,
                "baseline_decisions": baseline_decisions,
                "vad_runtime_ms": runtime_ms,
                "probabilities": probabilities,
                "decisions": decisions,
                "segments": segments,
                "irregular_probability_delta": maximum_delta,
                "irregular_availability_seconds": availability_seconds,
            })
    finally:
        vad.close()

    calibration_scores = []
    for candidate in settings:
        key = decision_key(candidate)
        score = counts(results, key, "calibration")
        distance = abs(candidate["threshold"] - 0.5) + abs(candidate["minimum_speech_ms"] - 250) / 1000
        calibration_scores.append((score["false_rejects"], score["false_accepts"], distance, decision_key(candidate), candidate))
    selected = min(calibration_scores)[4]
    selected_key = decision_key(selected)

    baseline_scores = []
    for candidate in rms_candidates():
        key = rms_key(candidate)
        score = counts(results, key, "calibration", decision_field="baseline_decisions")
        baseline_scores.append((score["false_rejects"], score["false_accepts"], key, candidate))
    selected_baselines = [min((score for score in baseline_scores if score[3]["shape"] == shape))[3] for shape in ("whole", "framed")]

    transcript_results = {}
    transcript_output = args.output.with_name("no-gate-transcripts.json")
    if not args.skip_asr:
        transcript_results = transcribe(manifest, transcript_output)

    for fixture in results:
        fixture["selected_accepts"] = fixture["decisions"][selected_key]
        transcript = transcript_results.get(fixture["id"], {})
        fixture["no_gate_transcript"] = transcript.get("transcript")
        fixture["decoder_milliseconds"] = transcript.get("milliseconds")
        fixture["decoder_error"] = transcript.get("error")
        fixture["final_transcript"] = transcript.get("transcript") if fixture["selected_accepts"] else ""
        fixture["decoder_skipped"] = not fixture["selected_accepts"]
        fixture["onset_clipping_ms"] = 0 if fixture["selected_accepts"] else None
        latencies = endpoint_latencies(
            fixture["probabilities"],
            fixture["irregular_availability_seconds"],
            selected["threshold"],
        )
        fixture["endpoint_confirmation_latencies_ms"] = [round(value, 3) for value in latencies]
        fixture["endpoint_latency_ms"] = round(max(latencies), 3) if latencies else None

    summary = {}
    for split in ("calibration", "holdout"):
        base = counts(results, selected_key, split)
        selected_fixtures = [fixture for fixture in results if fixture["split"] == split]
        base["nonempty_no_speech_transcripts"] = sum(
            fixture["label"] == "no_speech" and bool((fixture.get("no_gate_transcript") or "").strip()) for fixture in selected_fixtures
        )
        base["final_nonempty_no_speech_transcripts"] = sum(
            fixture["label"] == "no_speech" and bool((fixture.get("final_transcript") or "").strip()) for fixture in selected_fixtures
        )
        base["skipped_decodes"] = sum(fixture["decoder_skipped"] for fixture in selected_fixtures)
        summary[split] = base

    vad_median = statistics.median(fixture["vad_runtime_ms"] for fixture in results)
    decoder_times = [fixture["decoder_milliseconds"] for fixture in results if fixture["decoder_milliseconds"] is not None]
    decoder_median = statistics.median(decoder_times) if decoder_times else None
    maximum_delta = max(fixture["irregular_probability_delta"] for fixture in results)
    endpoint_values = [value for fixture in results for value in fixture["endpoint_confirmation_latencies_ms"]]
    all_summary = {name: sum(summary[split][name] for split in summary) for name in ("false_accepts", "false_rejects", "final_nonempty_no_speech_transcripts")}
    result = {
        "environment": {
            "whisper_cpp_revision": "f049fff95a089aa9969deb009cdd4892b3e74916",
            "silero": "v6.2.0 / 2aa269b785eeb53a82983a20501ddf7c1d9c48e33ab63a41391ac6c9f7fb6987",
            "fluid_audio_revision": "19600a485baa4998812e4654b70d2bab8f2c9949",
            "parakeet_revision": "ee09c569f73759e6d44c9bd16766f477b2b36d39",
        },
        "selected_settings": selected,
        "calibration_sweep": [{**candidate, **counts(results, decision_key(candidate), "calibration")} for candidate in settings],
        "rms_baselines": [
            {
                **candidate,
                "calibration": counts(results, rms_key(candidate), "calibration", decision_field="baseline_decisions"),
                "holdout": counts(results, rms_key(candidate), "holdout", decision_field="baseline_decisions"),
            }
            for candidate in selected_baselines
        ],
        "summary": summary,
        "runtime": {"vad_median_ms": vad_median, "decoder_median_ms": decoder_median},
        "boundary": {
            "buffer_sizes": IRREGULAR_BUFFERS,
            "maximum_probability_delta": maximum_delta,
            "mvp_onset_clipping_ms": 0,
            "future_endpoint_confirmation_median_ms": statistics.median(endpoint_values) if endpoint_values else None,
            "future_endpoint_confirmation_maximum_ms": max(endpoint_values) if endpoint_values else None,
        },
        "acceptance": {
            "no_final_nonempty_transcript_for_no_speech": all_summary["final_nonempty_no_speech_transcripts"] == 0,
            "no_rejected_speech": all_summary["false_rejects"] == 0,
            "vad_below_provisional_ten_percent_ratio": decoder_median is not None and vad_median < decoder_median * 0.1,
            "vad_below_accepted_fifteen_ms_budget": vad_median < 15,
            "capture_buffer_invariant": maximum_delta < 1e-6,
        },
        "fixtures": results,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    args.output.with_suffix(".md").write_text(markdown(result))
    print(args.output)
    print(args.output.with_suffix(".md"))


if __name__ == "__main__":
    main()
