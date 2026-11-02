import os, sys
# Aufruf: python3 Erzeuge-Symbol.py <Zielordner>
# Endgueltiges Atlas-Symbol (Entwurf G1a): massives A, Schwung vorne, unterer Bogen verjuengt.
# Die Freistellung um den oberen Bogen ist eine echte Aussparung (Maske), damit sie auf jedem Grund transparent bleibt.
OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)
THEMES = {"hell": ("#1C2340", "#D9692A"), "dunkel": ("#E8EBF4", "#F29A4A")}
A = "M8 52 L26 4 L38 4 L56 52 L45 52 L32 17 L19 52 Z"
SW1 = "M50.5 50 C55 59.5 46 62 32 61 C14 60 3 55 5 48"
SW2 = "M5 48 C7 41 28 37.5 50 34.5"

import math

def _cubic(p0, p1, p2, p3, n):
    pts = []
    for i in range(n + 1):
        t = i / n
        mt = 1 - t
        x = mt**3*p0[0] + 3*mt*mt*t*p1[0] + 3*mt*t*t*p2[0] + t**3*p3[0]
        y = mt**3*p0[1] + 3*mt*mt*t*p1[1] + 3*mt*t*t*p2[1] + t**3*p3[1]
        pts.append((x, y))
    return pts

def taper(w):
    """Unterer Bogen als Flaeche, die vom Fuss (duenn) zum Anschluss links (volle Breite) anwaechst."""
    pts = _cubic((50.5, 50), (55, 59.5), (46, 62), (32, 61), 60)[:-1] + _cubic((32, 61), (14, 60), (3, 55), (5, 48), 60)
    # Bogenlaenge fuer gleichmaessigen Verlauf
    acc_len = [0.0]
    for a, b in zip(pts, pts[1:]):
        acc_len.append(acc_len[-1] + math.dist(a, b))
    total = acc_len[-1]
    left, right = [], []
    for i, (x, y) in enumerate(pts):
        a = pts[max(i - 1, 0)]; b = pts[min(i + 1, len(pts) - 1)]
        dx, dy = b[0] - a[0], b[1] - a[1]
        l = math.hypot(dx, dy) or 1
        nx, ny = -dy / l, dx / l
        t = acc_len[i] / total
        half = w * (0.2 + 0.8 * t ** 1.3) / 2
        left.append((x + nx * half, y + ny * half))
        right.append((x - nx * half, y - ny * half))
    poly = left + right[::-1]
    d = "M" + " L".join(f"{x:.2f} {y:.2f}" for x, y in poly) + " Z"
    return d

def body(ink, acc, small):
    w = 5 if small else 3.6
    halo = w + (3 if small else 3.2)
    tail = f'<path d="{taper(w)}" fill="{acc}"/><circle cx="5" cy="48" r="{w/2}" fill="{acc}"/>'
    dot = "" if small else f'<circle cx="55.5" cy="33.8" r="4" fill="{acc}"/>'
    return f'''<defs><mask id="atlasFrei" maskUnits="userSpaceOnUse" x="0" y="0" width="64" height="64"><rect width="64" height="64" fill="#fff"/><path d="{SW2}" fill="none" stroke="#000" stroke-width="{halo}"/></mask></defs>
<g mask="url(#atlasFrei)"><path d="{A}" fill="{ink}"/>
{tail}</g>
<path d="{SW2}" fill="none" stroke="{acc}" stroke-width="{w}" stroke-linecap="round"/>
{dot}'''

for th, (ink, acc) in THEMES.items():
    for small, suf in [(False, ""), (True, "-klein")]:
        open(f"{OUT}/atlas-symbol-{th}{suf}.svg", "w").write(
            f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">\n{body(ink, acc, small)}\n</svg>\n')
