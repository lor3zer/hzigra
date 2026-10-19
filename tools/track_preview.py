#!/usr/bin/env python3
"""Превью и проверка трасс из scripts/data/track_db.gd (тот же сплайн, что в игре).

Печатает длину, минимальный радиус и минимальное расстояние между участками,
рисует PNG со схемой. Запуск: python3 tools/track_preview.py <папка для png>
"""
import math
import os
import re
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPACING = 3.0


def parse_tracks():
    src = open(os.path.join(ROOT, "scripts", "data", "track_db.gd"), encoding="utf-8").read()
    out = []
    for m in re.finditer(r'"id": "(\w+)".*?"width": ([\d.]+), "runoff": ([\d.]+).*?"points": \[(.*?)\],\n\t\}', src, re.S):
        pts = [(float(a), float(b)) for a, b in re.findall(r"Vector2\(([-\d.]+), ([-\d.]+)\)", m.group(4))]
        out.append((m.group(1), float(m.group(2)), float(m.group(3)), pts))
    return out


def cr(p0, p1, p2, p3, t):
    def d(a, b):
        return max(math.dist(a, b), 0.01) ** 0.5
    t0 = 0.0
    t1 = t0 + d(p0, p1)
    t2 = t1 + d(p1, p2)
    t3 = t2 + d(p2, p3)
    tt = t1 + (t2 - t1) * t

    def lerp(a, b, ta, tb):
        return tuple(a[i] * (tb - tt) / (tb - ta) + b[i] * (tt - ta) / (tb - ta) for i in range(2))
    a1 = lerp(p0, p1, t0, t1)
    a2 = lerp(p1, p2, t1, t2)
    a3 = lerp(p2, p3, t2, t3)
    b1 = lerp(a1, a2, t0, t2)
    b2 = lerp(a2, a3, t1, t3)
    return lerp(b1, b2, t1, t2)


def sample(cps):
    n = len(cps)
    dense = []
    for i in range(n):
        p0, p1, p2, p3 = cps[(i - 1) % n], cps[i], cps[(i + 1) % n], cps[(i + 2) % n]
        steps = max(4, math.ceil(math.dist(p1, p2)))
        for s in range(steps):
            dense.append(cr(p0, p1, p2, p3, s / steps))
    res = [dense[0]]
    acc = 0.0
    m = len(dense)
    for j in range(m):
        a = dense[j]
        b = dense[(j + 1) % m]
        seg = math.dist(a, b)
        while acc + seg >= SPACING:
            t = (SPACING - acc) / seg
            a = (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
            res.append(a)
            seg = math.dist(a, b)
            acc = 0.0
        acc += seg
    if math.dist(res[-1], res[0]) < SPACING * 0.5:
        res.pop()
    return res


def radius(pts, i):
    n = len(pts)
    a, b, c = pts[(i - 4) % n], pts[i], pts[(i + 4) % n]
    cross = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
    if abs(cross) < 1e-3:
        return 99999.0
    return math.dist(a, b) * math.dist(b, c) * math.dist(c, a) / (2 * abs(cross))


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "."
    ok = True
    for tid, width, runoff, cps in parse_tracks():
        pts = sample(cps)
        n = len(pts)
        wall = width / 2 + runoff
        rs = [radius(pts, i) for i in range(n)]
        gap = int(wall * 3 / SPACING) + 8
        min_sep = 1e9
        for i in range(0, n, 2):
            for j in range(i + gap, n, 2):
                if n - (j - i) < gap:
                    continue
                min_sep = min(min_sep, math.dist(pts[i], pts[j]))
        corners = sum(1 for i in range(n) if rs[i] < 80 and rs[i] <= min(rs[(i + k) % n] for k in range(-10, 11)))
        length = sum(math.dist(pts[i], pts[(i + 1) % n]) for i in range(n))
        bad = tid != "polygon" and (min(rs) < wall + 4 or min_sep < wall * 2 + 6)
        ok &= not bad
        print(f"{tid:8s} len={length:6.0f}m minR={min(rs):6.1f} (нужно >{wall + 4:.0f}) minSep={min_sep:6.1f} "
              f"(нужно >{wall * 2 + 6:.0f}) поворотов<80м={corners} {'ПЛОХО' if bad else 'ok'}")
        if bad:
            worst = sorted(range(n), key=lambda i: rs[i])
            seen = []
            for i in worst:
                if rs[i] >= wall + 4:
                    break
                if all(abs(i - j) > 15 for j in seen):
                    seen.append(i)
                    print(f"    острый поворот R={rs[i]:.1f} около ({pts[i][0]:.0f}, {pts[i][1]:.0f})")
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        sc = 700 / max(max(xs) - min(xs), max(ys) - min(ys))
        img = Image.new("RGB", (760, 760), (25, 30, 40))
        d = ImageDraw.Draw(img)
        P = [((x - min(xs)) * sc + 30, (y - min(ys)) * sc + 30) for x, y in pts]
        for i in range(n):
            r = rs[i]
            col = (255, 60, 60) if r < 50 else (255, 200, 60) if r < 100 else (200, 220, 255)
            d.line([P[i], P[(i + 1) % n]], fill=col, width=max(2, int(width * sc)))
        d.ellipse([P[0][0] - 6, P[0][1] - 6, P[0][0] + 6, P[0][1] + 6], fill=(60, 255, 60))
        d.text((10, 8), f"{tid} {length:.0f} m", fill=(255, 255, 255))
        img.save(os.path.join(out_dir, f"track_{tid}.png"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
