#!/usr/bin/env python3
"""Generate share/sounds/*.wav. Standard library only.

A tone must mean the same thing on every OS. macOS's /System/Library/Sounds and
Windows's C:\\Windows\\Media differ in both contents and names, so no common set
of names fits both — the sounds are synthesised and bundled instead.
"""
import math
import struct
import wave
from pathlib import Path

RATE = 44100
OUT = Path(__file__).resolve().parent.parent / "share" / "sounds"

# name -> [(frequency Hz, duration s, start s), ...]
TONES = {
    # Rising major triad: done / success.
    "ok":     [(1046.5, 0.12, 0.00), (1318.5, 0.12, 0.09), (1568.0, 0.30, 0.18)],
    # Two low falling notes: failure.
    "error":  [(440.0, 0.16, 0.00), (329.6, 0.36, 0.14)],
    # Same note twice: warning.
    "warn":   [(698.5, 0.11, 0.00), (698.5, 0.22, 0.17)],
    # Two rising notes, a questioning tone: a human's answer is needed.
    "ask":    [(587.3, 0.11, 0.00), (880.0, 0.30, 0.10)],
    # One short note: start.
    "start":  [(784.0, 0.14, 0.00)],
    # One long ringing note: general notification.
    "notify": [(1046.5, 0.38, 0.00)],
}

ATTACK = 0.004  # shorter attacks click


def render(parts):
    total = max(start + dur for _, dur, start in parts)
    n = int((total + 0.05) * RATE)
    buf = [0.0] * n
    for freq, dur, start in parts:
        s0 = int(start * RATE)
        count = int(dur * RATE)
        for i in range(count):
            if s0 + i >= n:
                break
            t = i / RATE
            # Exponential decay, close to a struck bell.
            env = math.exp(-4.5 * t / dur)
            if t < ATTACK:
                env *= t / ATTACK
            # A weak 2nd harmonic carries better than a pure sine on small speakers.
            v = math.sin(2 * math.pi * freq * t) + 0.22 * math.sin(4 * math.pi * freq * t)
            buf[s0 + i] += v * env * 0.34
    peak = max(abs(x) for x in buf) or 1.0
    scale = 0.89 / peak  # normalising to 1.0 clips on some players
    return b"".join(struct.pack("<h", int(max(-1.0, min(1.0, x * scale)) * 32767)) for x in buf)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, parts in TONES.items():
        data = render(parts)
        path = OUT / f"{name}.wav"
        with wave.open(str(path), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(data)
        print(f"  {path.name:<12} {len(data) // 2 / RATE:.2f}s  {len(data) // 1024}K")


if __name__ == "__main__":
    main()
