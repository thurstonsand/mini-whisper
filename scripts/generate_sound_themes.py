#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = ["numpy"]
# ///
"""Synthesizes every sound theme's four cues into MiniWhisper/Sounds.

The cues are meant to sit in the background, so every theme shares one budget, taken from
measuring Apple Dictation, Hex, and VoiceInk as they actually play: energy under about 1 kHz,
soft attacks, high-pass at 150 Hz and low-pass at 2.5 kHz, about -32 dBFS RMS (activate -34,
since it sounds as the microphone opens), and peaks no higher than -18 dBFS. Each theme differs
in its source, not its level. Activate is one gesture, complete rises, cancel falls, and error
falls a minor third.

Run: scripts/generate_sound_themes.py
"""

from collections.abc import Callable
from pathlib import Path
import wave

import numpy as np

SR = 48_000
OUT = Path(__file__).resolve().parent.parent / "MiniWhisper" / "Sounds"
CUES = ("activate", "complete", "cancel", "error")
TARGET_RMS = {"activate": -34.0, "complete": -32.0, "cancel": -33.0, "error": -32.0}
rng = np.random.default_rng(23)


def t_axis(dur: float) -> np.ndarray:
    return np.arange(int(dur * SR)) / SR


def note(name: str) -> float:
    steps = {"C": -9, "C#": -8, "D": -7, "D#": -6, "E": -5, "F": -4, "F#": -3}
    steps |= {"G": -2, "G#": -1, "A": 0, "A#": 1, "B": 2}
    return 440.0 * 2 ** ((steps[name[:-1]] + 12 * (int(name[-1]) - 4)) / 12)


def place(parts: list[tuple[float, np.ndarray]]) -> np.ndarray:
    out = np.zeros(max(int(s * SR) + len(x) for s, x in parts))
    for start, x in parts:
        i = int(start * SR)
        out[i : i + len(x)] += x
    return out


def biquad(x: np.ndarray, kind: str, f0: float, q: float = 0.707) -> np.ndarray:
    w0 = 2 * np.pi * f0 / SR
    alpha, c = np.sin(w0) / (2 * q), np.cos(w0)
    b = {
        "lp": ((1 - c) / 2, 1 - c, (1 - c) / 2),
        "hp": ((1 + c) / 2, -(1 + c), (1 + c) / 2),
        "bp": (alpha, 0.0, -alpha),
    }[kind]
    a0 = 1 + alpha
    b0, b1, b2 = (v / a0 for v in b)
    a1, a2 = -2 * c / a0, (1 - alpha) / a0
    y = np.zeros_like(x)
    x1 = x2 = y1 = y2 = 0.0
    for n, xn in enumerate(x):
        yn = b0 * xn + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, xn, y1, yn
        y[n] = yn
    return y


def rise(t: np.ndarray, attack: float) -> np.ndarray:
    ramp = 0.5 - 0.5 * np.cos(np.pi * np.clip(t / attack, 0, 1))
    return np.where(t < attack, ramp, 1.0)


# --- Drop: a droplet, a small pitch glide on a sine -------------------------------------------


def drop(f_start: float, f_end: float, dur: float, decay: float = 0.07) -> np.ndarray:
    t = t_axis(dur)
    f = f_start + (f_end - f_start) * (1 - np.exp(-t / 0.025))
    envelope = rise(t, 0.012) * np.exp(-np.maximum(t - 0.012, 0) / decay)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * envelope


# --- Pluck: a nylon string (Karplus-Strong, fractional delay so intervals stay in tune) -------


def pluck(f: float, dur: float) -> np.ndarray:
    n = int(dur * SR)
    delay = SR / f - 0.5
    burst = biquad(rng.standard_normal(int(delay) + 2), "lp", f * 1.2)
    y = np.zeros(n)
    y[: len(burst)] = burst
    whole, frac = int(delay), delay - int(delay)
    for i in range(len(burst), n):
        a, b, c = y[i - whole], y[i - whole - 1], y[i - whole - 2]
        y[i] = 0.994 * 0.5 * ((1 - frac) * a + frac * b + (1 - frac) * b + frac * c)
    t = t_axis(dur)
    return biquad(y, "lp", f * 2.2) * rise(t, 0.006) * np.exp(-t / 0.18)


# --- Hum: a voiced "mm" through two vowel formants, shaped like mm-hm and uh-uh ---------------


def hum(contour: list[tuple[float, float]], dur: float) -> np.ndarray:
    t = t_axis(dur)
    f0 = np.interp(t, [p[0] for p in contour], [p[1] for p in contour])
    glide = int(0.04 * SR)
    f0 = np.convolve(f0, np.ones(glide) / glide, mode="same")
    f0[: glide // 2] = contour[0][1]
    f0[-glide // 2 :] = contour[-1][1]
    vibrato = 1 + 0.006 * np.sin(2 * np.pi * 5.5 * t) * np.clip((t - 0.06) / 0.08, 0, 1)
    phase = 2 * np.pi * np.cumsum(f0 * vibrato) / SR
    source = sum(np.sin(k * phase) / k for k in range(1, 10))
    voiced = 0.6 * np.sin(phase)
    voiced += biquad(source, "bp", 350, 5) + 0.5 * biquad(source, "bp", 950, 7)
    end = np.clip((dur - t) / 0.06, 0, 1)
    return voiced * rise(t, 0.025) * (0.5 - 0.5 * np.cos(np.pi * end))


def two_hums(
    first: float, first_dur: float, gap: float, second: float, second_dur: float
) -> np.ndarray:
    return place(
        [
            (0, hum([(0, first)], first_dur)),
            (first_dur + gap, hum([(0, second)], second_dur)),
        ]
    )


# --- Bloom: vibraphone bars with motor tremolo, rolled as chords ------------------------------


def bar(f: float, dur: float, decay: float) -> np.ndarray:
    t = t_axis(dur)
    body = np.sin(2 * np.pi * f * t) * np.exp(-t / decay)
    fourth = 0.18 * np.sin(2 * np.pi * f * 4 * t) * np.exp(-t / (decay * 0.2))
    tremolo = 1 - 0.28 * (0.5 - 0.5 * np.cos(2 * np.pi * 5.2 * t))
    return (body + fourth) * tremolo * rise(t, 0.008)


def chord(notes: list[str], dur: float, roll: float, decay: float) -> np.ndarray:
    scale = len(notes) ** -0.5
    return place(
        [
            (i * roll, scale * bar(note(n), dur - i * roll, decay))
            for i, n in enumerate(notes)
        ]
    )


THEMES: dict[str, dict[str, Callable[[], np.ndarray]]] = {
    "drop": {
        "activate": lambda: drop(note("A4"), note("C5"), 0.16, 0.05),
        "complete": lambda: place(
            [
                (0, 0.8 * drop(note("C5"), note("D5"), 0.14, 0.04)),
                (0.075, drop(note("F5"), note("G5"), 0.2, 0.06)),
            ]
        ),
        "cancel": lambda: drop(note("D5"), note("G4"), 0.22, 0.07),
        "error": lambda: place(
            [
                (0, drop(note("A4"), note("G4"), 0.18, 0.05)),
                (0.12, drop(note("F#4"), note("E4"), 0.24, 0.07)),
            ]
        ),
    },
    "pluck": {
        "activate": lambda: pluck(note("D5"), 0.26),
        "complete": lambda: place(
            [(0, 0.8 * pluck(note("D5"), 0.24)), (0.08, pluck(note("A5"), 0.34))]
        ),
        "cancel": lambda: place(
            [(0, 0.8 * pluck(note("D5"), 0.24)), (0.09, pluck(note("A4"), 0.34))]
        ),
        "error": lambda: place(
            [(0, pluck(note("B4"), 0.24)), (0.12, pluck(note("G#4"), 0.36))]
        ),
    },
    "hum": {
        "activate": lambda: hum([(0, note("G4"))], 0.2),
        "complete": lambda: two_hums(note("G4"), 0.13, 0.035, note("D5"), 0.2),
        "cancel": lambda: hum(
            [(0, note("D5")), (0.1, note("D5")), (0.16, note("G4"))], 0.32
        ),
        "error": lambda: two_hums(note("A4"), 0.12, 0.06, note("F#4"), 0.18),
    },
    "bloom": {
        "activate": lambda: chord(["G4", "B4"], 0.34, 0.0, 0.12),
        "complete": lambda: chord(["G4", "B4", "D5"], 0.62, 0.045, 0.2),
        "cancel": lambda: chord(["B4", "G4", "E4"], 0.56, 0.05, 0.17),
        "error": lambda: place(
            [
                (0, chord(["E4", "G4"], 0.26, 0.0, 0.08)),
                (0.15, chord(["C#4", "E4"], 0.42, 0.0, 0.13)),
            ]
        ),
    },
}

# A voice reads louder than a pure tone at the same RMS.
THEME_TRIM = {"drop": 0.0, "pluck": 0.0, "hum": -1.5, "bloom": 0.0}


def finish(x: np.ndarray, theme: str, cue: str) -> np.ndarray:
    x = biquad(biquad(x, "hp", 150), "lp", 2500)
    fade = min(len(x), int(0.015 * SR))
    x[-fade:] *= np.linspace(1, 0, fade)
    audible = np.abs(x) > 0.01 * np.abs(x).max()
    x *= 10 ** ((TARGET_RMS[cue] + THEME_TRIM[theme]) / 20) / np.sqrt(
        np.mean(x[audible] ** 2)
    )
    ceiling = 10 ** (-18 / 20)
    return x * min(1.0, ceiling / np.abs(x).max())


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for theme, cues in THEMES.items():
        assert tuple(cues) == CUES, f"{theme} must define every cue in order"
        for cue, make in cues.items():
            x = finish(make(), theme, cue)
            path = OUT / f"{theme}-{cue}.wav"
            with wave.open(str(path), "wb") as w:
                w.setnchannels(1)
                w.setsampwidth(2)
                w.setframerate(SR)
                w.writeframes((x * 32767).astype(np.int16).tobytes())
            audible = np.abs(x) > 0.01 * np.abs(x).max()
            rms = 20 * np.log10(np.sqrt(np.mean(x[audible] ** 2)))
            peak = 20 * np.log10(np.abs(x).max())
            print(
                f"{path.name:22} {len(x) / SR * 1000:4.0f} ms  rms {rms:5.1f}  peak {peak:5.1f}"
            )


if __name__ == "__main__":
    main()
