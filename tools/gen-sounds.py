#!/usr/bin/env python3
"""share/sounds/*.wav 를 만든다. 표준 라이브러리만 쓴다.

세 OS 가 같은 소리를 내야 알림의 의미가 기계마다 흔들리지 않는다. macOS 의
/System/Library/Sounds 와 Windows 의 C:\\Windows\\Media 는 목록도 이름도 서로
달라서 공통 이름표를 얹을 수 없다 — 그래서 직접 합성해 번들로 넣는다.
"""
import math
import struct
import wave
from pathlib import Path

RATE = 44100
OUT = Path(__file__).resolve().parent.parent / "share" / "sounds"

# 이름표 -> [(주파수 Hz, 길이 초, 시작 시각 초), ...]
TONES = {
    # 올라가는 장3화음. 끝났다/성공.
    "ok":     [(1046.5, 0.12, 0.00), (1318.5, 0.12, 0.09), (1568.0, 0.30, 0.18)],
    # 내려가는 두 음, 낮게. 실패.
    "error":  [(440.0, 0.16, 0.00), (329.6, 0.36, 0.14)],
    # 같은 음 두 번. 주의.
    "warn":   [(698.5, 0.11, 0.00), (698.5, 0.22, 0.17)],
    # 올라가는 두 음. 묻는 억양 — 사람의 응답이 필요할 때.
    "ask":    [(587.3, 0.11, 0.00), (880.0, 0.30, 0.10)],
    # 짧은 한 음. 시작.
    "start":  [(784.0, 0.14, 0.00)],
    # 한 음, 길게 울림. 범용 알림.
    "notify": [(1046.5, 0.38, 0.00)],
}

ATTACK = 0.004  # 이보다 짧으면 파형이 급히 서서 딸깍 소리가 난다


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
            # 지수 감쇠. 종을 친 소리에 가깝게 들린다.
            env = math.exp(-4.5 * t / dur)
            if t < ATTACK:
                env *= t / ATTACK
            # 2배음을 약하게 섞어야 순수 사인보다 작은 스피커에서 잘 들린다.
            v = math.sin(2 * math.pi * freq * t) + 0.22 * math.sin(4 * math.pi * freq * t)
            buf[s0 + i] += v * env * 0.34
    peak = max(abs(x) for x in buf) or 1.0
    scale = 0.89 / peak  # 1.0 에 붙이면 재생기에 따라 클리핑한다
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
