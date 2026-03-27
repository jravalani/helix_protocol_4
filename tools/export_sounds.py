#!/usr/bin/env python3
"""
Export all procedural sound effects to MP3 files.

Requires: numpy  (pip install numpy)
          ffmpeg (brew install ffmpeg)

Run from the project root:
    python3 tools/export_sounds.py
"""

import math
import os
import subprocess
import wave

import numpy as np

SAMPLE_RATE = 22050
TAU = 2 * math.pi

SCRIPT_DIR  = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
OUTPUT_DIR  = os.path.join(PROJECT_DIR, "sounds")


# ─────────────────────────────────────────────
# I/O helpers
# ─────────────────────────────────────────────

def _save_wav(path: str, samples: np.ndarray) -> None:
    pcm = (np.clip(samples, -1.0, 1.0) * 32767).astype(np.int16)
    with wave.open(path, "w") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(pcm.tobytes())


def _wav_to_mp3(wav_path: str, mp3_path: str) -> None:
    subprocess.run(
        ["ffmpeg", "-y", "-i", wav_path, "-q:a", "2", mp3_path],
        check=True,
        capture_output=True,
    )
    os.remove(wav_path)


def export(name: str, samples: np.ndarray) -> None:
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    wav_path = os.path.join(OUTPUT_DIR, name + ".wav")
    mp3_path = os.path.join(OUTPUT_DIR, name + ".mp3")
    _save_wav(wav_path, samples)
    _wav_to_mp3(wav_path, mp3_path)
    print(f"  Exported: sounds/{name}.mp3")


# ─────────────────────────────────────────────
# Sound generators  (mirrors sound_manager.gd)
# ─────────────────────────────────────────────

def gen_chime() -> np.ndarray:
    """packet_delivered — satisfying two-note ascending chime"""
    dur = 0.3
    n   = int(SAMPLE_RATE * dur)
    t   = np.arange(n) / SAMPLE_RATE
    s   = np.zeros(n)

    m1 = t < 0.12
    s[m1] = np.sin(TAU * 880.0 * t[m1]) * np.exp(-t[m1] * 14.0)

    m2 = ~m1
    t2 = t[m2] - 0.12
    s[m2] = np.sin(TAU * 1318.5 * t2) * np.exp(-t2 * 16.0)

    return s * 0.4


def gen_metallic_clank() -> np.ndarray:
    """pipe_place — short metallic clank/snap"""
    dur = 0.12
    n   = int(SAMPLE_RATE * dur)
    t   = np.arange(n) / SAMPLE_RATE
    env = np.exp(-t * 35.0)

    v  = np.sin(TAU * 1200.0 * t) * 0.30
    v += np.sin(TAU * 2150.0 * t) * 0.20
    v += np.sin(TAU * 3400.0 * t) * 0.15
    v += np.sin(TAU * 4850.0 * t) * 0.10

    # Click transient
    mask = t < 0.004
    v[mask] += (np.random.rand(mask.sum()) * 2.0 - 1.0) * (1.0 - t[mask] / 0.004) * 0.5

    return v * env * 0.5


def gen_rumble() -> np.ndarray:
    """fracture_wave — deep rumble / siren"""
    dur = 2.5
    n   = int(SAMPLE_RATE * dur)
    t   = np.arange(n) / SAMPLE_RATE
    env = np.minimum(t / 0.4, 1.0) * np.maximum(1.0 - (t - 2.0) / 0.5, 0.0)

    freq = 50.0 + np.sin(t * 1.8) * 12.0
    v  = np.sin(TAU * freq * t) * 0.45
    v += np.sin(TAU * freq * 2.0 * t) * 0.25
    v += (np.random.rand(n) * 2.0 - 1.0) * 0.12

    return v * env * 0.45


def gen_rocket_launch() -> np.ndarray:
    """rocket_launch — ignition rumble transitioning to rising roar"""
    dur = 3.5
    n   = int(SAMPLE_RATE * dur)
    t   = np.arange(n) / SAMPLE_RATE
    env = np.minimum(t / 0.6, 1.0) * np.maximum(1.0 - (t - 3.0) / 0.5, 0.0)

    freq = 35.0 + t * 70.0
    v  = np.sin(TAU * freq * t) * 0.25
    v += np.sin(TAU * 28.0 * t) * 0.2 * np.maximum(1.0 - t / 1.5, 0.0)

    roar = np.clip(t / 2.0, 0.0, 1.0)
    v += (np.random.rand(n) * 2.0 - 1.0) * roar * 0.45

    return v * env * 0.45


def gen_whoosh() -> np.ndarray:
    """packet_spawned — quick whoosh / pulse"""
    dur = 0.18
    n   = int(SAMPLE_RATE * dur)
    t   = np.arange(n) / SAMPLE_RATE
    env = np.exp(-t * 18.0)

    freq = 2200.0 * np.exp(-t * 10.0)
    v  = np.sin(TAU * freq * t) * 0.35
    v += (np.random.rand(n) * 2.0 - 1.0) * 0.30

    return v * env * 0.35


def gen_crack() -> np.ndarray:
    """pipe_fracture — sharp crack / shatter"""
    dur = 0.25
    n   = int(SAMPLE_RATE * dur)
    t   = np.arange(n) / SAMPLE_RATE
    env = np.exp(-t * 22.0)

    v  = (np.random.rand(n) * 2.0 - 1.0) * 0.50
    v += np.sin(TAU * 800.0 * t) * np.exp(-t * 45.0) * 0.30
    v += np.sin(TAU * 3200.0 * t) * np.exp(-t * 28.0) * 0.15

    return v * env * 0.50


def gen_shutdown() -> np.ndarray:
    """hub_fracture — electrical shutdown / failure buzz"""
    dur = 0.55
    n   = int(SAMPLE_RATE * dur)
    t   = np.arange(n) / SAMPLE_RATE
    env = np.maximum(1.0 - t / dur, 0.0)

    freq = 400.0 * np.exp(-t * 2.5)
    v  = np.sin(TAU * freq * t) * 0.30
    v += np.sin(TAU * freq * 3.0 * t) * 0.15
    v += np.sin(TAU * freq * 5.0 * t) * 0.08

    # Electrical crackle
    crackle = np.random.rand(n) < 0.06
    v[crackle] += (np.random.rand(crackle.sum()) * 2.0 - 1.0) * 0.40

    return v * env * 0.50


# ─────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────

SOUNDS = {
    "packet_delivered": gen_chime,
    "pipe_place":       gen_metallic_clank,
    "fracture_wave":    gen_rumble,
    "rocket_launch":    gen_rocket_launch,
    "packet_spawned":   gen_whoosh,
    "pipe_fracture":    gen_crack,
    "hub_fracture":     gen_shutdown,
}

if __name__ == "__main__":
    print("Exporting sound effects to sounds/ ...")
    for name, gen_fn in SOUNDS.items():
        export(name, gen_fn())
    print("Done!")
