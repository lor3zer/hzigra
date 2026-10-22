#!/usr/bin/env python3
"""Звуки игры: моторы (из tools/gen_engines.py) + электро, турбина, выстрелы,
шины, ветер, удары, атмосфера трасс (толпа, птицы, сверчки, город, море, ветер)
и перекодирование музыки в сжатый ogg.

Каждый тип мотора — три зацикленных семпла: газ на низких оборотах, газ на высоких
и сброс газа. В игре они смешиваются и транспонируются по текущим оборотам.

Моторы (кроме электро) рендерятся физической моделью в tools/gen_engines.py.
Запуск: ENGINESOUND=... python3 tools/gen_engines.py && MUSIC_DIR=<папка с mp3> python3 tools/gen_audio.py
Результат: audio/*.wav и scripts/data/engine_db.gd
"""
import os
import wave

import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 32000
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "audio")
rng = np.random.default_rng(1611)

# паспорт моторов для игры (сами семплы — в tools/gen_engines.py)
ENGINES = {
    "i4t": dict(name="Рядная 4, турбо", idle=950, redline=7300, gears=6, turbo=True, pops=True),
    "f6": dict(name="Оппозитная 6", idle=900, redline=9000, gears=7, turbo=False, pops=True),
    "v8x": dict(name="V8 (кросс-плейн)", idle=800, redline=6900, gears=6, turbo=False, pops=True),
    "v8f": dict(name="V8 битурбо (флэт-плейн)", idle=950, redline=8600, gears=7, turbo=True, pops=True),
    "i6t": dict(name="Рядная 6, битурбо", idle=850, redline=7600, gears=6, turbo=True, pops=True),
    "v10": dict(name="V10", idle=1000, redline=9000, gears=7, turbo=False, pops=True),
    "v12": dict(name="V12", idle=1000, redline=9300, gears=7, turbo=False, pops=True),
    "w16": dict(name="W16, четыре турбины", idle=750, redline=7000, gears=7, turbo=True, pops=False),
}

# моторы на чужих семплах: другой паспорт (турбина, обороты), тот же звук
ALIASES = {
    "v8tt": dict(base="v8x", name="V8 битурбо (кросс-плейн)", idle=700, redline=6800, gears=6, turbo=True, pops=True),
}

EV = dict(name="Электромоторы", lo=3000, hi=9000, off=6000, idle=0, redline=12000, gears=1, turbo=False, pops=False)


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

def ev_loop(rpm, load, seconds=1.0):
    """Электромотор: низкий гул с быстро спадающими гармониками, тихий вой
    редуктора и шелест. Без резкого свиста инвертора — он утомляет."""
    f0 = rpm / 60.0 * 2.0                            # 2 пары полюсов
    period = int(round(SR / f0))
    real_rpm = SR / period * 60.0 / 2.0
    k = max(8, int(round(seconds * SR / period)))
    n = period * (k + k % 2)                         # чётное число периодов: субгармоника тоже замкнётся
    t = np.arange(n) / SR
    f = SR / period
    y = np.zeros(n)
    for h, a in [(1, 1.0), (2, 0.4), (3, 0.16), (4, 0.07)]:
        y += a * np.sin(2 * np.pi * f * h * t + h)
    y += 0.55 * np.sin(2 * np.pi * f * 0.5 * t)       # гул редуктора
    y += 0.05 * np.sin(2 * np.pi * f * 7 * t)         # вой шестерён, тихо
    rumble = periodic(lambda x: bp(x, 60, 400, 2), n)(rng.normal(0, 1, n))
    hiss = periodic(lambda x: bp(x, 400, 2500, 2), n)(rng.normal(0, 1, n))
    y = y / np.std(y) + rumble / np.std(rumble) * 0.35 + hiss / np.std(hiss) * 0.08
    y = periodic(lambda x: lp(x, 3000, 2), n)(y)
    if load < 0.5:
        y = periodic(lambda x: lp(x, 1500, 2), n)(y) * 0.6
    return y, real_rpm


# ---------------------------------------------------------------- прочие звуки

def turbo_loop():
    """Турбина: в основном поток воздуха, тон свиста ниже и тише (раньше был
    чистый синус 3.2 кГц — самая «режущая» для слуха частота)."""
    n = int(SR * 1.0)
    t = np.arange(n) / SR
    f = 1700.0                                        # целое число периодов за секунду — шов незаметен
    phase = 2 * np.pi * f * t + 2.0 * np.sin(2 * np.pi * 3 * t)   # лёгкое «плавание» тона, цикл замкнут
    tone = np.sin(phase) + 0.25 * np.sin(2 * phase)
    air = periodic(lambda x: bp(x, 700, 3200, 2), n)(rng.normal(0, 1, n))
    y = tone / np.std(tone) * 0.3 + air / np.std(air)
    return periodic(lambda x: lp(x, 5000, 2), n)(y)


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
    """Выстрел в выхлоп — маленький взрыв: резкий треск (ударная волна, доли мс),
    низкий «бух» резонанса выхлопной системы и потрескивание остывающих газов.
    0 — одиночный, 1 — двойной, 2 — очередь мелких, 3 — крупный, 4 — треск."""
    n = int(SR * 0.6)
    y = np.zeros(n)
    shots = {0: [(0.0, 1.0)], 1: [(0.0, 1.0), (0.085, 0.7)],
             2: [(0.0, 0.7), (0.06, 0.5), (0.13, 0.65), (0.21, 0.45), (0.3, 0.35)],
             3: [(0.0, 1.0)], 4: [(0.0, 0.5), (0.04, 0.35), (0.09, 0.4)]}[kind]
    big = kind == 3
    for t0, a in shots:
        i = int(t0 * SR)
        L = n - i
        tt = np.arange(L) / SR
        # треск: N-волна (производная гауссианы) + короткий шумовой всплеск
        w = 0.00035 if not big else 0.0005
        nwave = -(tt - 3 * w) / w * np.exp(-((tt - 3 * w) / w) ** 2 / 2)
        burst = hp(rng.normal(0, 1, L), 1500, 2) * np.exp(-tt / 0.003)
        # «бух»: затухающий резонанс с лёгким падением частоты
        f0 = rng.uniform(70, 95) * (0.8 if big else 1.0)
        f = f0 * (1 + 0.5 * np.exp(-tt / 0.02))
        boom = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt / (0.11 if big else 0.07))
        boom += 0.4 * np.sin(2 * np.pi * np.cumsum(f * 2.3) / SR) * np.exp(-tt / 0.035)
        body = lp(rng.normal(0, 1, L), 600, 2) * np.exp(-tt / 0.03) * 0.8
        y[i:] += a * (1.6 * nwave + 0.9 * burst + (1.6 if big else 1.2) * boom + body)
    # потрескивание: редкие щелчки, затихающие
    tail = np.zeros(n)
    k = 6 if kind != 4 else 18
    for _ in range(k):
        j = int(rng.uniform(0.02, 0.45 if kind != 4 else 0.5) * SR)
        m = min(n - j, int(0.004 * SR))
        tail[j:j + m] += rng.normal(0, 1, m) * np.exp(-np.arange(m) / (0.0008 * SR)) * rng.uniform(0.2, 0.6)
    y += bp(tail, 1200, 7000, 2) * (0.6 if kind != 4 else 1.2)
    y *= np.minimum(1.0, (n - np.arange(n)) / (0.05 * SR))   # плавный конец
    return np.tanh(y * 1.2)


def screech_loop():
    """Визг шин: узкополосный шум около 1 кГц с неровной, «живой» огибающей
    и тихий скрежет резины по асфальту. Без чистого тона — он раздражал."""
    n = int(SR * 3.0)
    squeal = periodic(lambda x: bp(x, 850, 1350, 2), n)(rng.normal(0, 1, n))
    squeal2 = periodic(lambda x: bp(x, 1700, 2300, 2), n)(rng.normal(0, 1, n))
    scrub = periodic(lambda x: bp(x, 150, 700, 2), n)(rng.normal(0, 1, n))
    env = periodic(lambda x: lp(x, 6, 2), n)(rng.normal(0, 1, n))
    env = 0.6 + 0.4 * env / (np.max(np.abs(env)) + 1e-9)
    y = squeal / np.std(squeal) * env + squeal2 / np.std(squeal2) * 0.3 * env + scrub / np.std(scrub) * 0.5
    return periodic(lambda x: lp(x, 4000, 2), n)(y)


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


# ---------------------------------------------------------------- атмосфера

def _place(buf, x, pos):
    """Кладёт сигнал x в кольцевой буфер с позиции pos (для бесшовных петель)."""
    n = len(buf)
    idx = (pos + np.arange(len(x))) % n
    np.add.at(buf, idx, x)


def crowd_loop(seconds=8.0):
    n = int(SR * seconds)
    y = np.zeros(n)
    # гул множества голосов: шум в полосе речи с "слоговой" модуляцией
    for _ in range(40):
        v = periodic(lambda x: bp(x, rng.uniform(250, 500), rng.uniform(1500, 3200), 2), n)(rng.normal(0, 1, n))
        rate = rng.uniform(2.5, 6.0)
        ph = rng.uniform(0, 2 * np.pi)
        k = max(1, round(rate * seconds))
        am = 0.5 + 0.5 * np.sin(2 * np.pi * k * np.arange(n) / n + ph)
        y += v * am ** 2 * rng.uniform(0.3, 1.0)
    y /= np.std(y)
    # волны восторга
    for c in (0.15, 0.62):
        L = int(SR * 1.6)
        t = np.arange(L) / SR
        e = np.sin(np.pi * t / 1.6) ** 2
        cheer = bp(rng.normal(0, 1, L), 700, 2800, 2)
        _place(y, cheer / np.std(cheer) * e * 1.6, int(c * n))
    # аплодисменты
    for _ in range(int(seconds * 25)):
        L = int(SR * 0.012)
        clap = hp(rng.normal(0, 1, L), 1200, 2) * env_exp(L, 0.003)
        _place(y, clap * rng.uniform(0.4, 1.2), rng.integers(0, n))
    return y


def birds_loop(seconds=10.0):
    n = int(SR * seconds)
    y = periodic(lambda x: lp(x, 900, 2), n)(rng.normal(0, 1, n)) * 0.25   # листва
    for _ in range(14):
        f0 = rng.uniform(2500, 5000)
        reps = rng.integers(2, 5)
        pos = rng.integers(0, n)
        for r in range(reps):
            L = int(SR * rng.uniform(0.05, 0.13))
            t = np.arange(L) / SR
            sweep = f0 * (1 + rng.uniform(-0.35, 0.35) * t / t[-1])
            ph = 2 * np.pi * np.cumsum(sweep) / SR
            chirp = np.sin(ph + 0.6 * np.sin(2 * np.pi * rng.uniform(30, 80) * t)) * np.sin(np.pi * t / t[-1])
            _place(y, chirp * rng.uniform(0.3, 0.8), pos + int(r * SR * rng.uniform(0.12, 0.2)))
    return y


def crickets_loop(seconds=8.0):
    n = int(SR * seconds)
    t = np.arange(n) / SR
    y = periodic(lambda x: lp(x, 500, 2), n)(rng.normal(0, 1, n)) * 0.3
    for f, period, ph in ((4500, 0.5, 0.0), (5200, 0.62, 0.21), (3900, 0.44, 0.33)):
        k = max(1, round(seconds / period))
        per = seconds / k
        phase = ((t + ph) % per) / per
        gate = ((phase < 0.25) & (np.sin(2 * np.pi * 32 * t) > 0)).astype(float)
        gate = lp(np.tile(gate, 3), 300, 1)[n:2 * n]
        fc = round(f * seconds) / seconds
        y += np.sin(2 * np.pi * fc * t) * gate * 0.5
    return y


def city_loop(seconds=8.0):
    n = int(SR * seconds)
    t = np.arange(n) / SR
    drone = periodic(lambda x: lp(x, 180, 2), n)(rng.normal(0, 1, n))
    traffic = periodic(lambda x: bp(x, 250, 1400, 2), n)(rng.normal(0, 1, n))
    swell = 0.6 + 0.4 * np.sin(2 * np.pi * 2 * t / seconds) * np.sin(2 * np.pi * 3 * t / seconds + 1)
    y = drone / np.std(drone) + traffic / np.std(traffic) * swell * 0.5
    L = int(SR * 0.45)
    tt = np.arange(L) / SR
    horn = (np.sign(np.sin(2 * np.pi * 410 * tt)) + np.sign(np.sin(2 * np.pi * 515 * tt))) * np.minimum(1, (0.45 - tt) / 0.05) * np.minimum(1, tt / 0.02)
    _place(y, lp(horn, 1800, 2) * 0.25, int(n * 0.55))
    return y


def sea_loop(seconds=10.0):
    n = int(SR * seconds)
    t = np.arange(n) / SR
    noise = rng.normal(0, 1, n)
    surf = periodic(lambda x: lp(x, 1400, 2), n)(noise)
    hiss = periodic(lambda x: bp(x, 2000, 7000, 2), n)(noise)
    env = (0.5 - 0.5 * np.cos(2 * np.pi * 2 * t / seconds)) ** 1.5
    y = surf / np.std(surf) * (0.35 + env) + hiss / np.std(hiss) * env * 0.4
    for c in (0.2, 0.7):
        L = int(SR * 0.5)
        tt = np.arange(L) / SR
        f = 2300 - 1300 * tt / 0.5
        ph = 2 * np.pi * np.cumsum(f) / SR
        gull = (np.sin(ph) + 0.4 * np.sin(2 * ph)) * np.sin(np.pi * tt / 0.5) * (0.6 + 0.4 * np.sin(2 * np.pi * 9 * tt))
        _place(y, gull * 0.5, int(c * n))
    return y


def desert_wind_loop(seconds=10.0):
    n = int(SR * seconds)
    t = np.arange(n) / SR
    noise = rng.normal(0, 1, n)
    body = periodic(lambda x: bp(x, 150, 900, 2), n)(noise)
    whistle = periodic(lambda x: reso(x, 950, 25), n)(noise)
    gust = 0.45 + 0.55 * (0.5 - 0.5 * np.cos(2 * np.pi * 2 * t / seconds)) * (0.6 + 0.4 * np.sin(2 * np.pi * 3 * t / seconds))
    return (body / np.std(body) + whistle / np.std(whistle) * 0.25) * gust


def write_ogg(name, x, rms=0.2, q=1):
    """Сжатый ogg (для длинных петель атмосферы)."""
    tmp = os.path.join(OUT, "_tmp.wav")
    write_wav("_tmp.wav", x, rms=rms)
    os.system(f'ffmpeg -y -loglevel error -i "{tmp}" -ac 1 -c:a libvorbis -q:a {q} "{os.path.join(OUT, name)}"')
    os.remove(tmp)


def music(src_dir):
    """Музыка игрока: перекодирование в ogg с сильным сжатием."""
    mdir = os.path.join(OUT, "music")
    os.makedirs(mdir, exist_ok=True)
    files = sorted(f for f in os.listdir(src_dir) if f.lower().endswith((".mp3", ".ogg", ".wav", ".flac")))
    for i, f in enumerate(files):
        dst = os.path.join(mdir, f"track{i + 1}.ogg")
        os.system(f'ffmpeg -y -loglevel error -i "{os.path.join(src_dir, f)}" -vn -ac 2 -ar 44100 -c:a libvorbis -b:a 48k "{dst}"')
        print(f"  music {f} -> {os.path.basename(dst)} {os.path.getsize(dst) // 1024} КБ")


# ---------------------------------------------------------------- main

def main():
    import gen_engines
    os.makedirs(OUT, exist_ok=True)
    build = os.path.join(ROOT, "tools", ".build")
    db = {}
    for key, p in ENGINES.items():
        print(key, p["name"])
        ge = gen_engines.ENGINES[key]
        for layer in ("lo", "hi", "off"):
            src = os.path.join(build, f"eng_{key}_{layer}.wav")
            if not os.path.exists(src):
                raise SystemExit("нет %s — сначала запустите tools/gen_engines.py" % src)
            sr, x = wavfile.read(src)
            write_wav(f"eng_{key}_{layer}.wav", x / 32768.0, rms=0.17 if layer == "off" else 0.25)
        db[key] = dict(name=p["name"], lo_rpm=ge["lo"], hi_rpm=ge["hi"], off_rpm=ge["off"], idle=p["idle"],
                       redline=p["redline"], gears=p["gears"], turbo=p["turbo"], pops=p["pops"])
    for key, p in ALIASES.items():
        d = dict(db[p["base"]])
        d.update(name=p["name"], idle=p["idle"], redline=p["redline"], gears=p["gears"], turbo=p["turbo"], pops=p["pops"],
                 samples=p["base"])
        db[key] = d
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
    for k in range(5):
        write_wav(f"pop{k}.wav", pop(k))
    write_wav("screech.wav", screech_loop(), rms=0.22)
    write_wav("wind.wav", wind_loop(), rms=0.2)
    write_wav("hit.wav", hit())
    write_wav("shift.wav", shift(), peak=0.7)
    write_wav("beep.wav", beep(660, 0.25), peak=0.6)
    write_wav("go.wav", beep(1320, 0.7), peak=0.6)

    print("ambience")
    write_ogg("amb_crowd.ogg", crowd_loop(), rms=0.2)
    write_ogg("amb_birds.ogg", birds_loop(), rms=0.12)
    write_ogg("amb_crickets.ogg", crickets_loop(), rms=0.1)
    write_ogg("amb_city.ogg", city_loop(), rms=0.15)
    write_ogg("amb_sea.ogg", sea_loop(), rms=0.18)
    write_ogg("amb_wind.ogg", desert_wind_loop(), rms=0.15)

    music_src = os.environ.get("MUSIC_DIR")
    if music_src:
        print("music")
        music(music_src)

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
        smp = f'"samples": "{d["samples"]}", ' if "samples" in d else ""
        lines.append(
            f'\t"{key}": {{"name": "{d["name"]}", {smp}"lo_rpm": {d["lo_rpm"]:.1f}, "hi_rpm": {d["hi_rpm"]:.1f}, '
            f'"off_rpm": {d["off_rpm"]:.1f}, "idle": {float(d["idle"]):.1f}, "redline": {float(d["redline"]):.1f}, '
            f'"gears": {d["gears"]}, "turbo": {str(d["turbo"]).lower()}, "pops": {str(d["pops"]).lower()}}},')
    lines.append("}")
    lines.append("")
    with open(os.path.join(ROOT, "scripts", "data", "engine_db.gd"), "w") as f:
        f.write("\n".join(lines))
    print("engine_db.gd written")


if __name__ == "__main__":
    main()
