#!/usr/bin/env python3
"""Синтез звуков игры: моторы разных типов, турбина, выстрелы, шины, ветер, удары.

Мотор моделируется как поток выхлопных импульсов (по одному на вспышку в цилиндре)
с учётом порядка работы и неравномерности по рядам (у кросс-плейн V8 это даёт
характерное "бурление"), затем импульсы проходят через резонансы выхлопной системы,
перегруз (сатурацию) и смешиваются с шумом впуска.

Каждый тип мотора даёт три зацикленных семпла: газ на низких оборотах, газ на высоких
и сброс газа. В игре они смешиваются и транспонируются по текущим оборотам.

Запуск: python3 tools/gen_audio.py  (нужны numpy и scipy)
Результат: audio/*.wav и scripts/data/engine_db.gd
"""
import os
import wave

import numpy as np
from scipy import signal

SR = 32000
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "audio")
rng = np.random.default_rng(1611)

# порядок вспышек по рядам: 0 — левый ряд, 1 — правый
CROSSPLANE = [0, 1, 1, 0, 1, 0, 0, 1]

ENGINES = {
    "i4t": dict(name="Рядная 4, турбо", cyl=4, lo=2600, hi=6800, off=4200, idle=950, redline=7300, gears=6,
                turbo=True, pops=True, reso=[(430, 7, 1.0), (1150, 5, 0.55), (2600, 4, 0.25)],
                lp=4800, drive=2.6, rasp=0.5, intake=0.22, body=0.45),
    "f6": dict(name="Оппозитная 6", cyl=6, lo=3000, hi=8200, off=5000, idle=900, redline=9000, gears=7,
               turbo=False, pops=True, reso=[(520, 6, 1.0), (1500, 5, 0.65), (3300, 4, 0.3)],
               lp=7000, drive=2.2, rasp=0.35, intake=0.18, body=0.45),
    "v8x": dict(name="V8 (кросс-плейн)", cyl=8, banks=CROSSPLANE, bank_amp=(1.0, 0.5), lo=2300, hi=6200, off=3800,
                idle=800, redline=6900, gears=6, turbo=False, pops=True,
                reso=[(95, 4, 1.0), (250, 5, 0.85), (680, 4, 0.35)], lp=2700, drive=3.4, rasp=0.5,
                intake=0.2, body=0.35),
    "v8f": dict(name="V8 битурбо (флэт-плейн)", cyl=8, banks=[0, 1] * 4, bank_amp=(1.0, 0.85), lo=3000, hi=8000,
                off=5000, idle=950, redline=8600, gears=7, turbo=True, pops=True,
                reso=[(230, 5, 1.0), (640, 5, 0.6), (1700, 4, 0.25)], lp=4800, drive=2.9, rasp=0.4,
                intake=0.2, body=0.55),
    "i6t": dict(name="Рядная 6, битурбо", cyl=6, lo=2600, hi=7000, off=4200, idle=850, redline=7600, gears=6,
                turbo=True, pops=True, reso=[(280, 5, 1.0), (820, 5, 0.65), (2000, 4, 0.28)],
                lp=4000, drive=2.6, rasp=0.4, intake=0.2, body=0.5),
    "v10": dict(name="V10", cyl=10, lo=3200, hi=8600, off=5200, idle=1000, redline=9000, gears=7,
                turbo=False, pops=True, reso=[(330, 5, 1.0), (1050, 6, 0.6), (2400, 4, 0.25)],
                lp=6500, drive=2.5, rasp=0.35, intake=0.18, body=0.55),
    "v12": dict(name="V12", cyl=12, lo=3200, hi=8800, off=5400, idle=1000, redline=9300, gears=7,
                turbo=False, pops=False, reso=[(380, 5, 1.0), (1250, 6, 0.65), (2900, 5, 0.3)],
                lp=7500, drive=2.2, rasp=0.3, intake=0.16, body=0.6),
    "w16": dict(name="W16, четыре турбины", cyl=16, banks=[0, 1, 0, 1, 1, 0, 1, 0] * 2, bank_amp=(1.0, 0.8),
                paired=True, lo=2200, hi=6400, off=3800, idle=750, redline=7000, gears=7, turbo=True, pops=False,
                reso=[(130, 4, 1.0), (380, 5, 0.85), (950, 4, 0.4)], lp=3000, drive=3.3, rasp=0.4,
                intake=0.22, body=0.6),
}

EV = dict(name="Электро", lo=3000, hi=10000, off=6000, idle=0, redline=14000, gears=1, turbo=False, pops=False)


# ---------------------------------------------------------------- утилиты

def write_wav(name, x, rms=None, peak=0.95):
    x = np.asarray(x, dtype=np.float64)
    x = x - np.mean(x)
    if rms is not None:
        x = x * (rms / (np.sqrt(np.mean(x * x)) + 1e-9))
    else:
        x = x * (peak / (np.max(np.abs(x)) + 1e-9))
    # мягкий лимитер, чтобы не было цифрового клиппинга
    x = np.tanh(x * 1.1) / np.tanh(1.1)
    x = np.clip(x, -1.0, 1.0)
    data = (x * 32767).astype("<i2").tobytes()
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)
    print(f"  {name:22s} {len(x) / SR:5.2f} c")


def lp(x, f, order=2):
    return signal.sosfilt(signal.butter(order, min(f, SR * 0.45), "low", fs=SR, output="sos"), x)


def hp(x, f, order=2):
    return signal.sosfilt(signal.butter(order, f, "high", fs=SR, output="sos"), x)


def bp(x, lo, hi, order=2):
    return signal.sosfilt(signal.butter(order, [lo, min(hi, SR * 0.45)], "band", fs=SR, output="sos"), x)


def reso(x, f, q):
    b, a = signal.iirpeak(f, q, fs=SR)
    return signal.lfilter(b, a, x)


def periodic(fn, n):
    """Обрабатывает три копии периодического сигнала и возвращает среднюю: стык цикла бесшовный."""
    def wrapped(x):
        y = fn(np.tile(x, 3))
        return y[n:2 * n]
    return wrapped


def env_exp(n, tau):
    return np.exp(-np.arange(n) / (tau * SR))


# ---------------------------------------------------------------- мотор

def engine_loop(p, rpm, load, seconds=1.25):
    cyl = p["cyl"]
    cycle = int(round(SR * 120.0 / rpm))           # 4-тактный цикл = 2 оборота
    real_rpm = SR * 120.0 / cycle
    cycles = max(4, int(round(seconds * SR / cycle)))
    n = cycle * cycles
    banks = p.get("banks")
    bank_amp = p.get("bank_amp", (1.0, 1.0))

    pulses = np.zeros(n)
    rasp = np.zeros(n)
    burst_len = int(0.0022 * SR)
    burst_env = env_exp(burst_len, 0.0006)
    for c in range(cycles):
        for k in range(cyl):
            amp = 1.0
            if banks:
                amp = bank_amp[banks[k % len(banks)]]
            jitter = rng.normal(0, 0.004 if load > 0.5 else 0.01)
            if p.get("paired"):
                # две половины мотора вспыхивают почти одновременно — тон ниже и гуще
                frac = (k // 2) / (cyl / 2) + (k % 2) * 0.011
            else:
                frac = k / cyl
            pos = (c * cycle + (frac + jitter) * cycle) % n
            a = amp * (1.0 + rng.normal(0, 0.06 if load > 0.5 else 0.22))
            if load < 0.5 and rng.random() < 0.12:
                a *= 0.15                               # пропуски на сбросе газа
            a *= load
            i = int(pos)
            fr = pos - i
            pulses[i % n] += a * (1 - fr)
            pulses[(i + 1) % n] += a * fr
            idx = (i + np.arange(burst_len)) % n
            rasp[idx] += a * burst_env * rng.normal(0, 1, burst_len)

    def chain(x_pulses, x_rasp):
        y = np.zeros_like(x_pulses)
        src = x_pulses + x_rasp * p["rasp"] * 0.35
        for f, q, g in p["reso"]:
            y += g * reso(src, f, q)
        # "грудь" звука: основная частота вспышек
        fire = rpm / 120.0 * (cyl / 2 if p.get("paired") else cyl)
        y += p["body"] * lp(x_pulses, max(160.0, fire * 1.35), 2) * 6.0
        y = lp(y, p["lp"], 2)
        y = y / (np.std(y) * 3.0 + 1e-9)
        drive = p["drive"] * (1.0 if load > 0.5 else 0.7)
        y = np.tanh(drive * y)
        y = lp(y, p["lp"], 2)
        return hp(y, 32, 2)

    proc = periodic(lambda x: x, n)
    y = chain(np.tile(pulses, 3), np.tile(rasp, 3))[n:2 * n]
    # шум впуска, модулированный тактами двигателя
    noise = rng.normal(0, 1, n)
    envl = lp(np.tile(np.abs(pulses), 3), 60, 2)[n:2 * n]
    envl = envl / (np.max(envl) + 1e-9)
    intake = periodic(lambda x: bp(x, 450, 2200, 2), n)(noise) * (0.35 + 0.65 * envl)
    intake = intake / (np.std(intake) + 1e-9) * np.std(y)
    y = y + intake * p["intake"] * (1.0 if load > 0.5 else 0.45)
    if load < 0.5:
        # потрескивание на сбросе
        for _ in range(int(cycles * 0.25)):
            i = rng.integers(0, n)
            L = int(0.006 * SR)
            idx = (i + np.arange(L)) % n
            y[idx] += rng.normal(0, 1, L) * env_exp(L, 0.0015) * np.std(y) * 2.5
    del proc
    return y, real_rpm


def ev_loop(rpm, load, seconds=1.0):
    f0 = rpm / 60.0 * 2.0                            # 2 пары полюсов
    period = int(round(SR / f0))
    real_rpm = SR / period * 60.0 / 2.0
    n = period * max(8, int(round(seconds * SR / period)))
    t = np.arange(n) / SR
    f = SR / period
    y = np.zeros(n)
    for h, a in [(1, 1.0), (2, 0.45), (3, 0.3), (4, 0.18), (6, 0.12), (8, 0.08)]:
        y += a * np.sin(2 * np.pi * f * h * t + h)
    y += 0.25 * np.sin(2 * np.pi * f * 0.5 * t)       # гул редуктора
    y += 0.12 * np.sign(np.sin(2 * np.pi * f * 12 * t)) * 0.3  # свист инвертора
    hiss = periodic(lambda x: bp(x, 2500, 9000, 2), n)(rng.normal(0, 1, n))
    y = y / np.std(y) + hiss / np.std(hiss) * 0.15
    if load < 0.5:
        y = periodic(lambda x: lp(x, 2500, 2), n)(y) * 0.6
    return y, real_rpm


# ---------------------------------------------------------------- прочие звуки

def turbo_loop():
    n = int(SR * 1.0)
    t = np.arange(n) / SR
    f = 3200.0
    y = np.sin(2 * np.pi * f * t) + 0.35 * np.sin(2 * np.pi * f * 2 * t) + 0.2 * np.sin(2 * np.pi * f * 1.5 * t)
    hiss = periodic(lambda x: bp(x, 3000, 9000, 2), n)(rng.normal(0, 1, n))
    return y / np.std(y) + hiss / np.std(hiss) * 0.6


def blowoff(flutter=False):
    n = int(SR * (0.7 if flutter else 0.55))
    t = np.arange(n) / SR
    e = (1 - np.exp(-t / 0.004)) * np.exp(-t / (0.22 if flutter else 0.16))
    noise = rng.normal(0, 1, n)
    y = bp(noise, 1800, 7000, 2) * e
    if flutter:
        y *= 0.5 + 0.5 * np.maximum(0, np.sin(2 * np.pi * (28 - 10 * t) * t))
        y += 0.5 * np.sin(2 * np.pi * 75 * t) * np.exp(-t / 0.08)
    return y


def pop(kind):
    n = int(SR * 0.35)
    t = np.arange(n) / SR
    y = np.zeros(n)
    shots = {0: [0.0], 1: [0.0, 0.07], 2: [0.0, 0.05, 0.11, 0.2]}[kind]
    for s in shots:
        i = int(s * SR)
        L = n - i
        tt = np.arange(L) / SR
        a = rng.uniform(0.6, 1.0)
        bang = rng.normal(0, 1, L) * np.exp(-tt / 0.012) + 1.6 * np.sin(2 * np.pi * 85 * tt) * np.exp(-tt / 0.035)
        y[i:] += a * bang
    y = np.tanh(lp(y, 4000, 2) * 2.5)
    return y


def screech_loop():
    n = int(SR * 2.0)
    t = np.arange(n) / SR
    wob = 40 * np.sin(2 * np.pi * 3 * t / 1.0 * 1) + 25 * np.sin(2 * np.pi * 7 * t)
    phase = 2 * np.pi * np.cumsum(1050 + wob) / SR
    # фаза должна замкнуться: подгоняем частоту
    phase *= np.round(phase[-1] / (2 * np.pi)) * 2 * np.pi / phase[-1]
    y = np.sin(phase) + 0.5 * np.sin(1.5 * phase) + 0.3 * np.sin(2 * phase)
    noise = periodic(lambda x: bp(x, 700, 2600, 2), n)(rng.normal(0, 1, n))
    return y / np.std(y) + noise / np.std(noise) * 0.7


def wind_loop():
    n = int(SR * 3.0)
    white = rng.normal(0, 1, n)
    pink = periodic(lambda x: lp(x, 500, 1), n)(white)
    gust = 0.7 + 0.3 * np.sin(2 * np.pi * np.arange(n) / n * 2)
    return pink * gust + periodic(lambda x: bp(x, 900, 2500, 2), n)(white) * 0.15


def hit():
    n = int(SR * 0.6)
    t = np.arange(n) / SR
    thump = np.sin(2 * np.pi * 55 * t) * np.exp(-t / 0.12)
    crunch = bp(rng.normal(0, 1, n), 600, 5000, 2) * np.exp(-t / 0.09)
    ring = (np.sin(2 * np.pi * 870 * t) + 0.6 * np.sin(2 * np.pi * 1330 * t)) * np.exp(-t / 0.25) * 0.25
    return np.tanh(2.0 * (thump * 1.4 + crunch + ring))


def shift():
    n = int(SR * 0.12)
    t = np.arange(n) / SR
    return bp(rng.normal(0, 1, n), 1200, 5000, 2) * np.exp(-t / 0.012) + np.sin(2 * np.pi * 110 * t) * np.exp(-t / 0.03)


def beep(f, dur):
    n = int(SR * dur)
    t = np.arange(n) / SR
    e = np.minimum(1, t / 0.005) * np.minimum(1, (dur - t) / 0.04)
    return (np.sin(2 * np.pi * f * t) + 0.3 * np.sin(2 * np.pi * f * 2 * t) + 0.15 * np.sin(2 * np.pi * f * 3 * t)) * e


# ---------------------------------------------------------------- main

def main():
    os.makedirs(OUT, exist_ok=True)
    db = {}
    for key, p in ENGINES.items():
        print(key, p["name"])
        lo, lo_rpm = engine_loop(p, p["lo"], 1.0)
        hi, hi_rpm = engine_loop(p, p["hi"], 1.0)
        off, off_rpm = engine_loop(p, p["off"], 0.35)
        write_wav(f"eng_{key}_lo.wav", lo, rms=0.26)
        write_wav(f"eng_{key}_hi.wav", hi, rms=0.26)
        write_wav(f"eng_{key}_off.wav", off, rms=0.17)
        db[key] = dict(name=p["name"], lo_rpm=lo_rpm, hi_rpm=hi_rpm, off_rpm=off_rpm, idle=p["idle"],
                       redline=p["redline"], gears=p["gears"], turbo=p["turbo"], pops=p["pops"])
    print("ev")
    lo, lo_rpm = ev_loop(EV["lo"], 1.0)
    hi, hi_rpm = ev_loop(EV["hi"], 1.0)
    off, off_rpm = ev_loop(EV["off"], 0.3)
    write_wav("eng_ev_lo.wav", lo, rms=0.2)
    write_wav("eng_ev_hi.wav", hi, rms=0.2)
    write_wav("eng_ev_off.wav", off, rms=0.12)
    db["ev"] = dict(name=EV["name"], lo_rpm=lo_rpm, hi_rpm=hi_rpm, off_rpm=off_rpm, idle=EV["idle"],
                    redline=EV["redline"], gears=1, turbo=False, pops=False)

    print("fx")
    write_wav("turbo.wav", turbo_loop(), rms=0.2)
    write_wav("bov.wav", blowoff(False))
    write_wav("flutter.wav", blowoff(True))
    for k in range(3):
        write_wav(f"pop{k}.wav", pop(k))
    write_wav("screech.wav", screech_loop(), rms=0.22)
    write_wav("wind.wav", wind_loop(), rms=0.2)
    write_wav("hit.wav", hit())
    write_wav("shift.wav", shift(), peak=0.7)
    write_wav("beep.wav", beep(660, 0.25), peak=0.6)
    write_wav("go.wav", beep(1320, 0.7), peak=0.6)

    lines = [
        "class_name EngineDB",
        "extends RefCounted",
        "",
        "## Сгенерировано tools/gen_audio.py — не править вручную.",
        "## *_rpm — обороты, на которых записан семпл (для транспонирования).",
        "",
        "const ENGINES := {",
    ]
    for key, d in db.items():
        lines.append(
            f'\t"{key}": {{"name": "{d["name"]}", "lo_rpm": {d["lo_rpm"]:.1f}, "hi_rpm": {d["hi_rpm"]:.1f}, '
            f'"off_rpm": {d["off_rpm"]:.1f}, "idle": {float(d["idle"]):.1f}, "redline": {float(d["redline"]):.1f}, '
            f'"gears": {d["gears"]}, "turbo": {str(d["turbo"]).lower()}, "pops": {str(d["pops"]).lower()}}},')
    lines.append("}")
    lines.append("")
    with open(os.path.join(ROOT, "scripts", "data", "engine_db.gd"), "w") as f:
        f.write("\n".join(lines))
    print("engine_db.gd written")


if __name__ == "__main__":
    main()
