#!/usr/bin/env python3
"""Физически-информированный синтез моторов через enginesound (MIT,
https://github.com/DasEtwas/enginesound): цилиндры с впускными/выпускными
волноводами, коллектор, прямая труба и камеры глушителя.

Скрипт пишет конфиги tools/engines/<тип>.esc, рендерит зацикленные семплы
(газ на низах/верхах, сброс газа) и сохраняет их в audio/eng_<тип>_*.wav
(сжатые ogg генерирует tools/gen_audio.py).

Сборка генератора (один раз):
  git clone https://github.com/DasEtwas/enginesound && cd enginesound
  cargo build --release --no-default-features
Запуск:
  ENGINESOUND=/путь/к/enginesound python3 tools/gen_engines.py
"""
import os
import subprocess
import tempfile

import numpy as np
from scipy import signal
from scipy.io import wavfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CFG_DIR = os.path.join(ROOT, "tools", "engines")
OUT = os.path.join(ROOT, "tools", ".build")
SR = 32000

CROSSPLANE = [0, 1, 1, 0, 1, 0, 0, 1]

# exh — длина выпускной трубы каждого цилиндра (сек задержки), по рядам
# ext — длина коллектора, pipe — прямая труба, muf — камеры глушителя
ENGINES = {
    "i4t": dict(cyl=4, lo=2600, hi=6800, off=4200, exh=(0.00062, 0.00062), ext=(0.0011, 0.0011), pipe=0.0052,
                muf=[0.00012, 0.00016, 0.0002, 0.00024], intake=0.42, exhaust=0.6, vib=0.05, ign=4.0, fluct=0.18,
                exh_alpha=0.62),
    "f6": dict(cyl=6, lo=3000, hi=8200, off=5000, exh=(0.00052, 0.00058), ext=(0.0009, 0.0011), pipe=0.0045,
               muf=[0.0001, 0.00013, 0.00017], intake=0.45, exhaust=0.62, vib=0.04, ign=4.5, fluct=0.15,
               exh_alpha=0.66),
    "v8x": dict(cyl=8, banks=CROSSPLANE, lo=2300, hi=6200, off=3800, exh=(0.00105, 0.0021), ext=(0.0019, 0.0036),
                pipe=0.0085, muf=[0.00022, 0.0003, 0.00041], intake=0.22, exhaust=0.8, vib=0.08, ign=6.0,
                fluct=0.3, exh_alpha=0.72),
    "v8f": dict(cyl=8, banks=[0, 1] * 4, lo=3000, hi=8000, off=5000, exh=(0.0008, 0.00088), ext=(0.0014, 0.0016),
                pipe=0.0062, muf=[0.00015, 0.0002, 0.00026], intake=0.35, exhaust=0.72, vib=0.05, ign=5.0,
                fluct=0.2, exh_alpha=0.68),
    "i6t": dict(cyl=6, lo=2600, hi=7000, off=4200, exh=(0.00078, 0.00078), ext=(0.0013, 0.0015), pipe=0.0066,
                muf=[0.00016, 0.00021, 0.00027], intake=0.4, exhaust=0.68, vib=0.05, ign=4.8, fluct=0.18,
                exh_alpha=0.66),
    "v10": dict(cyl=10, banks=[0, 1] * 5, lo=3200, hi=8600, off=5200, exh=(0.00058, 0.00064), ext=(0.001, 0.0012),
                pipe=0.0048, muf=[0.0001, 0.00014, 0.00018], intake=0.38, exhaust=0.66, vib=0.04, ign=4.6,
                fluct=0.12, exh_alpha=0.66),
    "v12": dict(cyl=12, banks=[0, 1] * 6, lo=3200, hi=8800, off=5400, exh=(0.0005, 0.00054), ext=(0.0009, 0.001),
                pipe=0.0042, muf=[0.0001, 0.00013, 0.00016], intake=0.42, exhaust=0.62, vib=0.03, ign=4.2,
                fluct=0.1, exh_alpha=0.64),
    "w16": dict(cyl=16, paired=True, banks=[0, 1, 0, 1, 1, 0, 1, 0] * 2, lo=2200, hi=6400, off=3800,
                exh=(0.0012, 0.0016), ext=(0.0022, 0.0028), pipe=0.0095, muf=[0.00025, 0.00033, 0.00045],
                intake=0.38, exhaust=0.75, vib=0.07, ign=5.5, fluct=0.22, exh_alpha=0.7),
}


def wg(delay, alpha, beta):
    return (f"(chamber0:(samples:(delay:{delay:.8f},),),chamber1:(samples:(delay:{delay:.8f},),),"
            f"alpha:{alpha:.6f},beta:{beta:.6f},)")


def config(p, rpm, ignition_scale=1.0):
    cyl = p["cyl"]
    banks = p.get("banks", [0] * cyl)
    rng = np.random.default_rng(cyl * 7 + int(p["exh"][0] * 1e6))
    cyls = []
    for k in range(cyl):
        if p.get("paired"):
            off = (k // 2) / (cyl / 2) + (k % 2) * 0.012
        else:
            off = k / cyl
        b = banks[k % len(banks)]
        exh = p["exh"][b] * (1.0 + rng.uniform(-0.04, 0.04))
        ext = p["ext"][b] * (1.0 + rng.uniform(-0.05, 0.05))
        intake = 0.00015 * (1.0 + rng.uniform(-0.2, 0.2))
        cyls.append(
            "(crank_offset:%.6f,exhaust_waveguide:%s,intake_waveguide:%s,extractor_waveguide:%s,"
            "intake_open_refl:0.006,intake_closed_refl:1,exhaust_open_refl:-0.0007,exhaust_closed_refl:%.4f,"
            "piston_motion_factor:2.4,ignition_factor:%.4f,ignition_time:0.07,)"
            % (off % 1.0, wg(exh, p["exh_alpha"], 0.06), wg(intake, 1.0, -0.75), wg(ext, 0.0, -0.0008),
               p["exh_alpha"], p["ign"] * ignition_scale))
    muf = ",".join(wg(d, 0.0, -0.14) for d in p["muf"])
    return (
        f"(rpm:{rpm:.3f},intake_volume:{p['intake']:.4f},exhaust_volume:{p['exhaust']:.4f},"
        f"engine_vibrations_volume:{p['vib']:.4f},cylinders:[{','.join(cyls)}],"
        f"intake_noise_factor:0.2,intake_noise_lp:(delay:0.0001,),engine_vibration_filter:(delay:0.0108,),"
        f"muffler:(straight_pipe:{wg(p['pipe'], 0.06, 0.0016)},muffler_elements:[{muf}],),"
        f"intake_valve_shift:-0.04,exhaust_valve_shift:-0.0035,crankshaft_fluctuation:{p['fluct']:.4f},"
        f"crankshaft_fluctuation_lp:(delay:0.017,),)")


def render(binary, cfg_text, rpm, seconds=4.0):
    with tempfile.TemporaryDirectory() as td:
        cfg = os.path.join(td, "e.esc")
        out = os.path.join(td, "o.wav")
        with open(cfg, "w") as f:
            f.write(cfg_text)
        subprocess.run([binary, "-h", "-c", cfg, "-r", f"{rpm}", "-o", out, "-l", f"{seconds:.3f}",
                        "-w", "1.5", "-q", str(SR), "-v", "0.05"], check=True, stdout=subprocess.DEVNULL)
        sr, x = wavfile.read(out)
    x = x.astype(np.float64)
    if x.ndim > 1:
        x = x.mean(axis=1)
    return x


def make_loop(x, rpm, seconds=1.3):
    """Бесшовная петля: целое число циклов двигателя + кроссфейд на стыке."""
    cycle = SR * 120.0 / rpm
    n_cyc = max(4, int(round(seconds * SR / cycle)))
    # подбираем число циклов, при котором длина ближе всего к целому числу семплов
    best = min(range(n_cyc, n_cyc + 8), key=lambda k: abs(k * cycle - round(k * cycle)))
    L = int(round(best * cycle))
    F = int(min(cycle * 2, SR * 0.06))
    s0 = len(x) // 4
    seg = x[s0:s0 + L + F].copy()
    fade = np.linspace(0.0, 1.0, F)
    loop = seg[:L].copy()
    loop[:F] = seg[:F] * fade + seg[L:L + F] * (1.0 - fade)
    return loop


def post(x, drive):
    """Лёгкая обработка всей записи: срез инфранизов, сатурация для плотности."""
    x = signal.sosfiltfilt(signal.butter(2, 30, "high", fs=SR, output="sos"), x)
    x = x / (np.std(x) * 3.0 + 1e-12)
    return np.tanh(drive * x) / np.tanh(drive)


def main():
    binary = os.environ.get("ENGINESOUND", "enginesound")
    os.makedirs(CFG_DIR, exist_ok=True)
    os.makedirs(OUT, exist_ok=True)
    for key, p in ENGINES.items():
        print(key)
        with open(os.path.join(CFG_DIR, key + ".esc"), "w") as f:
            f.write(config(p, p["lo"]))
        for layer, rpm, ign, drive in (("lo", p["lo"], 1.0, 1.6), ("hi", p["hi"], 1.0, 1.8), ("off", p["off"], 0.25, 1.2)):
            x = make_loop(post(render(binary, config(p, rpm, ign), rpm), drive), rpm)
            wavfile.write(os.path.join(OUT, f"eng_{key}_{layer}.wav"), SR, (x / np.max(np.abs(x)) * 0.9 * 32767).astype(np.int16))


if __name__ == "__main__":
    main()
