#!/usr/bin/env python3
"""Процедурные бесшовные текстуры (numpy + Pillow) -> textures/*.jpg / *.png.

Шум строится через обратное БПФ случайного спектра, поэтому все текстуры
повторяются без швов. Размеры маленькие (128–512), JPG со сжатием —
весь набор занимает несколько сотен килобайт.

Запуск: python3 tools/gen_textures.py
"""
import os

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "textures")
rng = np.random.default_rng(42)


def noise(n, beta=2.0, m=None):
    """Бесшовный шум 1/f^beta, нормированный в 0..1."""
    m = m or n
    fx = np.fft.fftfreq(m)[None, :]
    fy = np.fft.fftfreq(n)[:, None]
    f = np.sqrt(fx * fx + fy * fy)
    f[0, 0] = 1.0
    spec = (rng.normal(size=(n, m)) + 1j * rng.normal(size=(n, m))) / f ** (beta * 0.5)
    spec[0, 0] = 0
    x = np.real(np.fft.ifft2(spec))
    x -= x.min()
    return x / (x.max() + 1e-9)


def speckle(n, density, m=None):
    m = m or n
    return (rng.random((n, m)) < density).astype(float)


def blur(x, r=1):
    y = x.copy()
    for _ in range(r):
        y = (y + np.roll(y, 1, 0) + np.roll(y, -1, 0) + np.roll(y, 1, 1) + np.roll(y, -1, 1)) / 5.0
    return y


def save(name, rgb, q=82):
    img = Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8))
    path = os.path.join(OUT, name)
    if name.endswith(".jpg"):
        img.save(path, quality=q, optimize=True)
    else:
        img.save(path, optimize=True)
    print(f"  {name:16s} {img.size[0]}x{img.size[1]} {os.path.getsize(path) // 1024} КБ")


def gray_to_rgb(g, tint):
    return g[..., None] * np.array(tint)[None, None, :]


def asphalt():
    n = 512
    base = 0.62 + 0.18 * noise(n, 2.2) + 0.12 * noise(n, 1.0)
    grains = blur(speckle(n, 0.08), 1) * 0.5 - blur(speckle(n, 0.06), 1) * 0.5
    g = base + grains * 0.35
    # следы шин — чуть темнее и глаже вдоль полосы движения (u — поперёк дороги)
    u = np.linspace(0, 1, n)[None, :]
    wear = sum(np.exp(-((u - c) / 0.06) ** 2) for c in (0.18, 0.36, 0.64, 0.82))
    g = g * (1.0 - 0.1 * wear)
    # трещины
    cracks = noise(n, 2.6)
    g -= np.clip(1.0 - np.abs(cracks - 0.5) * 60.0, 0, 1) * 0.25
    save("asphalt.jpg", gray_to_rgb(np.clip(g, 0, 1), (0.98, 0.98, 1.0)))


def grass():
    n = 512
    g = 0.55 + 0.3 * noise(n, 2.4) + 0.15 * noise(n, 1.2)
    blades = blur(speckle(n, 0.25), 1)
    col = np.stack([0.75 * g, 1.0 * g, 0.55 * g], -1)
    col += (blades[..., None] - 0.25) * np.array([0.12, 0.22, 0.08])
    dry = noise(n, 3.0)
    col += np.clip(dry - 0.65, 0, 1)[..., None] * np.array([0.6, 0.35, 0.05])
    save("grass.jpg", col * 0.52)


def sand():
    n = 512
    y, x = np.mgrid[0:n, 0:n] / n
    warp = noise(n, 2.6) * 2.0
    ripples = 0.5 + 0.5 * np.sin(2 * np.pi * (y * 12 + warp * 2.0))
    g = 0.7 + 0.12 * ripples + 0.14 * noise(n, 2.0) + 0.08 * blur(speckle(n, 0.2), 1)
    save("sand.jpg", gray_to_rgb(g * 0.88, (1.0, 0.84, 0.6)))


def snow():
    n = 256
    g = 0.86 + 0.1 * noise(n, 2.4) + 0.04 * noise(n, 1.0)
    sparkle = speckle(n, 0.004) * 0.3
    save("snow.jpg", gray_to_rgb(np.clip(g + sparkle, 0, 1), (0.95, 0.97, 1.0)))


def gravel():
    n = 256
    g = 0.5 + 0.25 * noise(n, 1.4) + 0.25 * blur(speckle(n, 0.3), 1)
    col = np.stack([g * 0.85, g * 0.8, g * 0.72], -1)
    save("gravel.jpg", col * 0.72)


def concrete():
    n = 256
    g = 0.7 + 0.15 * noise(n, 2.0) + 0.06 * noise(n, 1.0)
    g -= np.clip(noise(n, 3.0) - 0.7, 0, 1) * 0.4  # пятна
    g[:, :2] *= 0.6                                 # шов между плитами
    g[:2, :] *= 0.7
    save("concrete.jpg", gray_to_rgb(g * 0.9, (0.98, 0.97, 0.95)))


def wood():
    n = 256
    y, x = np.mgrid[0:n, 0:n] / n
    planks = 8
    py = (y * planks) % 1.0
    grain = 0.5 + 0.5 * np.sin((x * 30 + noise(n, 2.5) * 6) * np.pi * 2)
    g = 0.55 + 0.15 * grain + 0.15 * noise(n, 2.0)
    g *= np.where((py < 0.06) | (py > 0.96), 0.45, 1.0)
    save("wood.jpg", np.stack([g * 0.75, g * 0.52, g * 0.32], -1))


def plaster():
    n = 256
    g = 0.82 + 0.1 * noise(n, 2.2) + 0.06 * blur(speckle(n, 0.3), 1)
    g -= np.clip(noise(n, 3.0) - 0.75, 0, 1) * 0.35
    save("plaster.jpg", gray_to_rgb(g, (1.0, 0.98, 0.95)))


def roof():
    n = 256
    y, x = np.mgrid[0:n, 0:n] / n
    rows = 10
    ry = (y * rows) % 1.0
    shift = (np.floor(y * rows) % 2) * 0.5
    rx = (x * 8 + shift) % 1.0
    g = 0.65 + 0.25 * ry - 0.25 * (rx < 0.06) - 0.3 * (ry > 0.92) + 0.1 * noise(n, 2.0)
    save("roof.jpg", gray_to_rgb(np.clip(g, 0, 1), (1.0, 1.0, 1.0)))


def facade():
    n = 256
    y, x = np.mgrid[0:n, 0:n] / n
    cols, rows = 6, 8
    cx = (x * cols) % 1.0
    cy = (y * rows) % 1.0
    win = (cx > 0.18) & (cx < 0.82) & (cy > 0.2) & (cy < 0.8)
    g = 0.55 + 0.1 * noise(n, 2.0)
    col = gray_to_rgb(g, (0.9, 0.9, 0.95))
    glass = np.array([0.2, 0.26, 0.35])
    col[win] = glass * (0.8 + 0.4 * (1 - cy[win]))[:, None]
    save("facade.jpg", col)
    # маска окон для ночной подсветки: часть окон горит
    lit = rng.random((rows, cols)) < 0.55
    li = lit[np.clip((y * rows).astype(int), 0, rows - 1), np.clip((x * cols).astype(int), 0, cols - 1)]
    em = np.zeros((n, n, 3))
    warm = np.array([1.0, 0.82, 0.5])
    em[win & li] = warm
    save("facade_emit.jpg", em)


def foliage():
    n = 128
    g = 0.5 + 0.35 * noise(n, 1.6) + 0.15 * blur(speckle(n, 0.35), 1)
    save("foliage.jpg", gray_to_rgb(g * 0.85, (1.0, 1.0, 1.0)))


def bark():
    n = 128
    y, x = np.mgrid[0:n, 0:n] / n
    g = 0.5 + 0.25 * np.sin((x * 14 + noise(n, 2.5) * 3) * np.pi * 2) * 0.5 + 0.25 * noise(n, 1.8)
    save("bark.jpg", gray_to_rgb(g, (0.62, 0.48, 0.36)))


def rock():
    n = 128
    g = 0.5 + 0.35 * noise(n, 1.8) + 0.15 * noise(n, 1.0)
    save("rock.jpg", gray_to_rgb(g * 0.8, (0.9, 0.88, 0.85)))


def tire():
    # протектор: u — по окружности, v — поперёк шины
    w, h = 256, 64
    y, x = np.mgrid[0:h, 0:w]
    u = x / w
    v = y / h
    g = np.full((h, w), 0.25)
    groove = (np.abs(v - 0.5) < 0.03) | (np.abs(v - 0.3) < 0.025) | (np.abs(v - 0.7) < 0.025)
    sipes = (((u * 64 + v * 2) % 1.0) < 0.12) & (np.abs(v - 0.5) < 0.42)
    g[groove | sipes] = 0.08
    side = (v < 0.1) | (v > 0.9)
    g[side] = 0.18
    g += rng.normal(0, 0.015, g.shape)
    save("tire.png", gray_to_rgb(np.clip(g, 0, 1), (1, 1, 1)))


def carbon():
    n = 64
    y, x = np.mgrid[0:n, 0:n]
    cell = 8
    tx = (x // cell + y // cell) % 2
    fx = (x % cell) / cell
    fy = (y % cell) / cell
    shade = np.where(tx == 0, 0.5 + 0.5 * np.sin(fx * np.pi), 0.5 + 0.5 * np.sin(fy * np.pi))
    g = 0.08 + 0.12 * shade
    save("carbon.png", gray_to_rgb(g, (1, 1, 1.05)))


def grille():
    n = 64
    y, x = np.mgrid[0:n, 0:n] / n
    hx = (x * 8 + (np.floor(y * 8) % 2) * 0.5) % 1.0
    hy = (y * 8) % 1.0
    hole = (np.abs(hx - 0.5) < 0.32) & (np.abs(hy - 0.5) < 0.3)
    g = np.where(hole, 0.02, 0.22)
    save("grille.png", gray_to_rgb(g, (1, 1, 1)))


def headlight():
    n = 64
    y, x = np.mgrid[0:n, 0:n] / n
    g = 0.75 + 0.25 * np.exp(-(((x - 0.3) ** 2 + (y - 0.5) ** 2) / 0.02)) + 0.25 * np.exp(-(((x - 0.72) ** 2 + (y - 0.5) ** 2) / 0.015))
    ring = np.abs(np.sqrt((x - 0.3) ** 2 + (y - 0.5) ** 2) - 0.2) < 0.02
    g[ring] = 0.55
    save("headlight.png", gray_to_rgb(np.clip(g, 0, 1), (1, 1, 1)))


def taillight():
    n = 64
    y, x = np.mgrid[0:n, 0:n] / n
    led = ((x * 10) % 1.0 < 0.6) & ((y * 4) % 1.0 < 0.7)
    g = np.where(led, 1.0, 0.45)
    save("taillight.png", gray_to_rgb(g, (1, 1, 1)))


def main():
    os.makedirs(OUT, exist_ok=True)
    for fn in (asphalt, grass, sand, snow, gravel, concrete, wood, plaster, roof, facade, foliage, bark, rock,
               tire, carbon, grille, headlight, taillight):
        fn()


if __name__ == "__main__":
    main()
