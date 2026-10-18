"""Synthesizes every sound effect in sfx/ from scratch (noise, tones and
envelopes), so the project needs no downloaded audio.

    python3 tools/make_sounds.py

Requires numpy and scipy.
"""
import os
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, lfilter

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "sfx")
rng = np.random.default_rng(7)


def t(d):
    return np.linspace(0, d, int(SR * d), endpoint=False)


def noise(d):
    return rng.uniform(-1, 1, int(SR * d))


def env(n, attack=0.005, decay=0.2, curve=4.0):
    x = np.arange(n) / SR
    a = np.clip(x / max(attack, 1e-4), 0, 1)
    d = np.exp(-np.maximum(x - attack, 0) / max(decay, 1e-4) * curve / 4.0)
    return a * d


def lp(x, cutoff):
    b, a = butter(2, min(cutoff / (SR / 2), 0.99), "low")
    return lfilter(b, a, x)


def hp(x, cutoff):
    b, a = butter(2, min(cutoff / (SR / 2), 0.99), "high")
    return lfilter(b, a, x)


def bp(x, lo, hi):
    b, a = butter(2, [lo / (SR / 2), min(hi / (SR / 2), 0.99)], "band")
    return lfilter(b, a, x)


def sweep(f0, f1, d):
    tt = t(d)
    f = np.geomspace(f0, f1, len(tt))
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def save(name, x, gain=0.9):
    x = np.asarray(x, dtype=np.float64)
    peak = np.max(np.abs(x)) or 1.0
    x = x / peak * gain
    # tiny fade to avoid clicks
    f = min(64, len(x) // 4)
    x[:f] *= np.linspace(0, 1, f)
    x[-f:] *= np.linspace(1, 0, f)
    wavfile.write(os.path.join(OUT, name + ".wav"), SR, (x * 32767).astype(np.int16))


def main():
    os.makedirs(OUT, exist_ok=True)
    # body hits
    n = noise(0.18)
    save("punch", lp(n, 900) * env(len(n), 0.002, 0.05) + sweep(160, 60, 0.18) * env(len(n), 0.002, 0.06) * 0.8)
    n = noise(0.25)
    save("slash", bp(n, 1800, 7000) * env(len(n), 0.01, 0.08) + sweep(3000, 900, 0.25) * env(len(n), 0.005, 0.05) * 0.2)
    n = noise(0.45)
    save("heavy", lp(n, 500) * env(len(n), 0.003, 0.15) + sweep(110, 35, 0.45) * env(len(n), 0.002, 0.2) * 1.2)
    # explosion: low rumble + crackle
    n = noise(2.2)
    boom = lp(n, 300) * env(len(n), 0.004, 0.9) * 1.4 + lp(n, 2500) * env(len(n), 0.002, 0.15) * 0.6
    boom += sweep(80, 25, 2.2) * env(len(n), 0.002, 0.6)
    save("explosion", boom)
    n = noise(0.22)
    save("gunshot", hp(lp(n, 6000), 300) * env(len(n), 0.001, 0.05) + lp(n, 400) * env(len(n), 0.001, 0.04) * 0.7)
    n = noise(1.2)
    save("rocket", bp(n, 300, 3000) * env(len(n), 0.05, 0.9) * (0.6 + 0.4 * np.sin(2 * np.pi * 18 * t(1.2))))
    n = noise(0.6)
    save("land", lp(n, 350) * env(len(n), 0.002, 0.25) + sweep(90, 30, 0.6) * env(len(n), 0.002, 0.3))
    n = noise(0.35)
    w = bp(n, 400, 2500) * np.sin(np.linspace(0, np.pi, len(n))) ** 2
    save("whoosh", w, 0.6)
    n = noise(0.9)
    save("consume", lp(n, 700) * env(len(n), 0.05, 0.6) * (0.5 + 0.5 * np.sin(2 * np.pi * 9 * t(0.9))) +
         sweep(220, 70, 0.9) * env(len(n), 0.02, 0.5) * 0.4)
    n = noise(0.7)
    save("crash", hp(n, 800) * env(len(n), 0.001, 0.25) * 0.7 + lp(n, 300) * env(len(n), 0.001, 0.2))
    n = noise(0.5)
    save("spike", bp(n, 600, 4000) * env(len(n), 0.002, 0.18) + sweep(400, 90, 0.5) * env(len(n), 0.002, 0.2) * 0.6)
    n = noise(0.4)
    save("tendril", bp(n, 900, 5000) * env(len(n), 0.01, 0.15) * (0.6 + 0.4 * np.sin(2 * np.pi * 40 * t(0.4))))
    # alert: two rising tones
    a = np.concatenate([np.sin(2 * np.pi * 660 * t(0.12)), np.zeros(800), np.sin(2 * np.pi * 880 * t(0.18))])
    save("alert", a * np.concatenate([env(int(SR * 0.12), 0.005, 0.2), np.zeros(800), env(int(SR * 0.18), 0.005, 0.3)]), 0.5)
    save("ui", np.sin(2 * np.pi * 520 * t(0.08)) * env(int(SR * 0.08), 0.002, 0.04), 0.4)
    n = noise(0.3)
    save("dash", bp(n, 500, 4000) * env(len(n), 0.005, 0.12) + sweep(300, 900, 0.3) * env(len(n), 0.005, 0.1) * 0.3, 0.7)
    n = noise(1.6)
    save("tank_shot", lp(n, 600) * env(len(n), 0.002, 0.5) * 1.3 + hp(n, 1500) * env(len(n), 0.001, 0.06) * 0.5)
    # monster roar: detuned saws + growl noise
    tt = t(1.4)
    f = 85 + 25 * np.sin(2 * np.pi * 2.5 * tt)
    saw = 2 * ((np.cumsum(f) / SR) % 1.0) - 1
    saw2 = 2 * ((np.cumsum(f * 1.51) / SR) % 1.0) - 1
    roar = lp(saw + saw2 * 0.6 + noise(1.4) * 0.5, 1200) * env(len(tt), 0.15, 1.0)
    save("roar", roar)
    n = noise(0.3)
    save("block", sweep(900, 400, 0.3) * env(len(n), 0.001, 0.12) + bp(n, 2000, 6000) * env(len(n), 0.001, 0.05) * 0.5, 0.7)
    n = noise(0.25)
    save("jump", lp(n, 1200) * env(len(n), 0.003, 0.08) + sweep(120, 220, 0.25) * env(len(n), 0.003, 0.08) * 0.4, 0.6)
    n = noise(1.0)
    save("glide", bp(n, 300, 1500) * np.sin(np.linspace(0, np.pi, len(n))), 0.5)
    tt = t(0.8)
    f = 900 + 300 * np.sin(2 * np.pi * 6 * tt)
    save("scream", bp(np.sin(2 * np.pi * np.cumsum(f) / SR) + noise(0.8) * 0.3, 500, 3000) * env(len(tt), 0.05, 0.6), 0.45)
    # helicopter: rotor thump loop (exactly 1 second for seamless looping)
    tt = t(1.0)
    thump = np.zeros(len(tt))
    for k in range(9):
        start = int(k * SR / 9)
        seg = lp(noise(0.06), 250) * env(int(SR * 0.06), 0.002, 0.05)
        thump[start:start + len(seg)] += seg[: len(thump) - start]
    whine = np.sin(2 * np.pi * 220 * tt) * 0.05 + lp(noise(1.0), 2000) * 0.08
    save("helicopter", thump + whine, 0.7)
    tt = t(2.0)
    hive = lp(noise(2.0), 200) * (0.6 + 0.4 * np.sin(2 * np.pi * 1.5 * tt)) + np.sin(2 * np.pi * 55 * tt) * 0.3
    save("hive", hive, 0.6)
    save("pickup", np.concatenate([np.sin(2 * np.pi * 700 * t(0.07)), np.sin(2 * np.pi * 1050 * t(0.1))]) *
         env(int(SR * 0.17), 0.002, 0.2), 0.45)
    n = noise(1.2)
    save("death", lp(n, 400) * env(len(n), 0.01, 0.6) + sweep(200, 40, 1.2) * env(len(n), 0.01, 0.6))
    ev = sum(np.sin(2 * np.pi * f * t(0.9)) for f in (440, 554, 659, 880)) * env(int(SR * 0.9), 0.02, 0.7)
    save("evolve", ev, 0.5)
    n = noise(0.3)
    save("zap", sweep(200, 1800, 0.3) * env(len(n), 0.005, 0.15) * 0.6 + hp(n, 4000) * env(len(n), 0.002, 0.08) * 0.3, 0.5)
    # rain loop: 3 seconds of soft filtered noise with random droplets
    n = noise(3.0)
    rain = bp(n, 800, 6000) * 0.5 + lp(noise(3.0), 400) * 0.3
    drops = np.zeros(len(n))
    for k in range(120):
        i = rng.integers(0, len(n) - 400)
        drops[i:i + 400] += hp(noise(400 / SR), 3000) * env(400, 0.001, 0.01) * rng.uniform(0.2, 0.8)
    save("rain", rain + drops, 0.5)
    print("sounds written to", os.path.abspath(OUT))


if __name__ == "__main__":
    main()
