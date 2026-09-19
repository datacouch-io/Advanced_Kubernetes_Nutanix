#!/usr/bin/env python3
"""Render a scale knee-point line chart to SVG from measurement data.

Input lines: "<replicas> <seconds> <ready> <pending>" (header + rows + DONE).
Usage: scale_chart.py <results.txt> <out.svg>

Plots time-to-ready (Y) vs replicas requested (X). The "knee" is the first step
where Pods could not all schedule (pending > 0): it is drawn in the warn colour
and labelled, because that is the capacity degradation point.
"""
import sys

BG = "#ffffff"; AXIS = "#40474f"; GRID = "#e3e7eb"; TEXT = "#1b1f23"; MUTED = "#5a636c"
LINE = "#2b5fa8"; DOT = "#2b5fa8"; KNEE = "#a5651a"; KNEEFILL = "#fdf0e3"; OK = "#1e7a45"

def main():
    src, out = sys.argv[1], sys.argv[2]
    rows = []
    for ln in open(src):
        p = ln.split()
        if len(p) == 4 and p[0].isdigit():
            rows.append((int(p[0]), int(p[1]), int(p[2]), int(p[3])))
    if not rows:
        sys.exit("no data rows")

    W, H = 900, 520
    ML, MR, MT, MB = 90, 40, 64, 84
    pw, ph = W - ML - MR, H - MT - MB
    xs = [r[0] for r in rows]; ys = [r[1] for r in rows]
    xmin, xmax = 0, max(xs)
    ymax = max(ys) * 1.18 + 1

    def px(x): return ML + (x - xmin) / (xmax - xmin) * pw
    def py(y): return MT + ph - (y - 0) / (ymax - 0) * ph

    knee_i = next((i for i, r in enumerate(rows) if r[3] > 0), None)

    s = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" font-family="-apple-system,Segoe UI,Roboto,sans-serif">']
    s.append(f'<rect width="{W}" height="{H}" fill="{BG}"/>')
    s.append(f'<text x="{ML}" y="32" font-size="19" font-weight="700" fill="{TEXT}">Cluster scale knee-point: time-to-ready vs replicas (fixed 2-node cluster)</text>')

    for i in range(6):
        yv = ymax * i / 5
        y = py(yv)
        s.append(f'<line x1="{ML}" y1="{y:.1f}" x2="{ML+pw}" y2="{y:.1f}" stroke="{GRID}"/>')
        s.append(f'<text x="{ML-10}" y="{y+4:.1f}" font-size="13" fill="{MUTED}" text-anchor="end">{yv:.0f}s</text>')
    for (x, sec, r, pend) in rows:
        s.append(f'<text x="{px(x):.1f}" y="{MT+ph+24}" font-size="13" fill="{MUTED}" text-anchor="middle">{x}</text>')
    s.append(f'<text x="{ML+pw/2:.1f}" y="{H-30}" font-size="14" fill="{TEXT}" text-anchor="middle">replicas requested (each Pod requests 50m CPU)</text>')
    s.append(f'<text x="24" y="{MT+ph/2:.1f}" font-size="14" fill="{TEXT}" text-anchor="middle" transform="rotate(-90 24 {MT+ph/2:.1f})">time until all Ready (capped at 20s = did not converge)</text>')

    s.append(f'<line x1="{ML}" y1="{MT}" x2="{ML}" y2="{MT+ph}" stroke="{AXIS}" stroke-width="1.5"/>')
    s.append(f'<line x1="{ML}" y1="{MT+ph}" x2="{ML+pw}" y2="{MT+ph}" stroke="{AXIS}" stroke-width="1.5"/>')

    pts = " ".join(f"{px(x):.1f},{py(sec):.1f}" for (x, sec, r, pend) in rows)
    s.append(f'<polyline points="{pts}" fill="none" stroke="{LINE}" stroke-width="2.5"/>')

    for i, (x, sec, r, pend) in enumerate(rows):
        cx, cy = px(x), py(sec)
        if i == knee_i:
            s.append(f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="7.5" fill="{KNEEFILL}" stroke="{KNEE}" stroke-width="2.5"/>')
            s.append(f'<text x="{cx:.1f}" y="{cy-16:.1f}" font-size="12.5" font-weight="700" fill="{KNEE}" text-anchor="middle">knee: {pend} Pod(s) Pending</text>')
            s.append(f'<text x="{cx:.1f}" y="{cy-32:.1f}" font-size="11" fill="{KNEE}" text-anchor="middle">capacity exceeded</text>')
        else:
            col = OK if pend == 0 else KNEE
            s.append(f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="5" fill="{col}"/>')
            s.append(f'<text x="{cx:.1f}" y="{cy-10:.1f}" font-size="11" fill="{MUTED}" text-anchor="middle">{sec}s</text>')

    if knee_i is not None:
        kx = px(rows[knee_i][0])
        s.append(f'<line x1="{kx:.1f}" y1="{MT}" x2="{kx:.1f}" y2="{MT+ph}" stroke="{KNEE}" stroke-width="1" stroke-dasharray="4 4" opacity="0.6"/>')

    s.append('</svg>')
    open(out, "w").write("\n".join(s))
    print(f"wrote {out} ({len(rows)} points, knee at index {knee_i})")

if __name__ == "__main__":
    main()
