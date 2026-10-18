"""Synthesizes the three music loops in music/ (ambient, combat, boss).

    python3 tools/make_music.py

Requires numpy and scipy. Every loop is an exact number of bars so it
repeats seamlessly.
"""
import os
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, lfilter

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "music")
rng = np.random.default_rng(11)


def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12.0)


def lp(x, cutoff, order=2):
    b, a = butter(order, min(cutoff / (SR / 2), 0.99), "low")
    return lfilter(b, a, x)


def hp(x, cutoff):
    b, a = butter(2, min(cutoff / (SR / 2), 0.99), "high")
    return lfilter(b, a, x)


def saw(freq, n, detune=0.0):
    t = np.arange(n) / SR
    out = np.zeros(n)
    for d in (-detune, 0.0, detune):
        f = freq * (1 + d)
        out += 2 * ((t * f) % 1.0) - 1
    return out / 3


def sine(freq, n):
    return np.sin(2 * np.pi * freq * np.arange(n) / SR)


def env(n, a=0.01, r=0.3):
    t = np.arange(n) / SR
    return np.clip(t / max(a, 1e-4), 0, 1) * np.exp(-t / max(r, 1e-4))


def place(buf, sig, start):
    end = min(len(buf), start + len(sig))
    buf[start:end] += sig[: end - start]
    # wrap the tail around so the loop is seamless
    if start + len(sig) > len(buf):
        rest = sig[end - start:]
        buf[: len(rest)] += rest


def kick(n=int(SR * 0.35)):
    t = np.arange(n) / SR
    f = 50 + 90 * np.exp(-t * 30)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 9)


def snare(n=int(SR * 0.25)):
    return hp(rng.uniform(-1, 1, n), 1200) * env(n, 0.001, 0.08) * 0.8 + sine(190, n) * env(n, 0.001, 0.05) * 0.4


def hat(n=int(SR * 0.06)):
    return hp(rng.uniform(-1, 1, n), 6000) * env(n, 0.001, 0.02) * 0.4


def save(name, x, gain=0.8):
    x = x / (np.max(np.abs(x)) or 1.0) * gain
    wavfile.write(os.path.join(OUT, name + ".wav"), SR, (x * 32767).astype(np.int16))


def ambient():
    bars, bpm = 16, 60
    beat = 60.0 / bpm
    n = int(SR * beat * 4 * bars)
    buf = np.zeros(n)
    # slow minor chord pad: Dm - Bb - F - C (as low drones)
    chords = [[50, 57, 62, 65], [46, 53, 58, 62], [41, 48, 53, 57], [48, 55, 60, 64]]
    bar_len = int(SR * beat * 4)
    for b in range(bars):
        ch = chords[(b // 4) % 4]
        seg = np.zeros(bar_len)
        for note in ch:
            seg += saw(midi(note), bar_len, 0.004) * 0.25
        seg = lp(seg, 700)
        fade = np.minimum(1, np.minimum(np.arange(bar_len), bar_len - np.arange(bar_len)) / (SR * 0.4))
        place(buf, seg * fade, b * bar_len)
    # sparse plucks
    scale = [62, 65, 67, 69, 72, 74, 77]
    for k in range(40):
        start = int(rng.integers(0, n))
        note = scale[rng.integers(0, len(scale))]
        ln = int(SR * 2.5)
        pl = (sine(midi(note), ln) + 0.3 * sine(midi(note) * 2, ln)) * env(ln, 0.005, 0.7) * 0.25
        place(buf, pl, start)
    # deep heartbeat every 2 beats
    for k in range(bars * 2):
        place(buf, kick() * 0.35, int(k * 2 * beat * SR))
    save("ambient", buf, 0.6)


def combat(name="combat", bpm=124, root=38, heavy=False):
    bars = 8
    beat = 60.0 / bpm
    n = int(SR * beat * 4 * bars)
    buf = np.zeros(n)
    step = beat / 4
    for s in range(bars * 16):
        t0 = int(s * step * SR)
        pos = s % 16
        if pos in (0, 6, 8, 10) or (heavy and pos in (3, 14)):
            place(buf, kick() * 0.9, t0)
        if pos in (4, 12):
            place(buf, snare(), t0)
        if pos % 2 == 0:
            place(buf, hat(), t0)
    # driving bass ostinato
    pattern = [0, 0, 12, 0, 0, 10, 0, 7] if not heavy else [0, 0, 1, 0, 0, 12, 0, 6]
    bass_len = int(step * 2 * SR)
    for s in range(bars * 8):
        bar = s // 8
        shift = [0, 0, -2, -4][bar % 4] if not heavy else [0, 0, 1, -1][bar % 4]
        note = root + pattern[s % 8] + shift
        b = lp(saw(midi(note), bass_len, 0.006), 900) * env(bass_len, 0.003, 0.18) * 0.7
        place(buf, b, int(s * step * 2 * SR))
    # string stabs on bar starts
    stab_len = int(beat * 1.5 * SR)
    for bar in range(bars):
        shift = [0, 0, -2, -4][bar % 4] if not heavy else [0, 0, 1, -1][bar % 4]
        chord = [root + 24 + shift, root + 27 + shift, root + 31 + shift]
        st = sum(saw(midi(c), stab_len, 0.01) for c in chord) * env(stab_len, 0.01, 0.4) * 0.22
        place(buf, lp(st, 2500), int(bar * 4 * beat * SR))
    if heavy:
        # distorted drone underneath
        drone = np.tanh(lp(saw(midi(root - 12), n, 0.01), 300) * 3.0) * 0.25
        buf += drone
    save(name, buf, 0.75)


def main():
    os.makedirs(OUT, exist_ok=True)
    ambient()
    combat("combat", 124, 38, False)
    combat("boss", 138, 37, True)
    print("music written to", os.path.abspath(OUT))


if __name__ == "__main__":
    main()
