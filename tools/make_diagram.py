#!/usr/bin/env python3
"""Render a lab architecture diagram to SVG from a small JSON spec.

Layout model: vertical stages, each stage a rounded box holding a title and
zero or more body lines. Stages are connected top-to-bottom by arrows. A stage
may carry `side` notes rendered to the right, and stages may be `split` into
columns to show parallel paths.

Usage: make_diagram.py <spec.json> <out.svg>
"""
import json
import sys
from xml.sax.saxutils import escape

# Theme-neutral palette: readable on white and on light-grey renderers.
BG = "#ffffff"
BOX = "#f4f6f8"
BOX_ACCENT = "#e8f0fb"
BOX_RESULT = "#e6f4ea"
BOX_WARN = "#fdf0e3"
STROKE = "#40474f"
ACCENT = "#2b5fa8"
RESULT = "#1e7a45"
WARN = "#a5651a"
TEXT = "#1b1f23"
MUTED = "#5a636c"

W = 900
PAD = 24
COL_GAP = 20
TITLE_H = 26
LINE_H = 17
BOX_PAD_Y = 12
ARROW_H = 34

FILLS = {"plain": BOX, "accent": BOX_ACCENT, "result": BOX_RESULT, "warn": BOX_WARN}
EDGES = {"plain": STROKE, "accent": ACCENT, "result": RESULT, "warn": WARN}


def box_height(items):
    return TITLE_H + BOX_PAD_Y * 2 + LINE_H * len(items)


def render(spec, out):
    stages = spec["stages"]
    parts = []
    y = PAD

    # title
    parts.append(
        f'<text x="{PAD}" y="{y + 18}" font-family="Helvetica,Arial,sans-serif" '
        f'font-size="17" font-weight="700" fill="{TEXT}">{escape(spec["title"])}</text>'
    )
    y += 30
    if spec.get("subtitle"):
        parts.append(
            f'<text x="{PAD}" y="{y + 12}" font-family="Helvetica,Arial,sans-serif" '
            f'font-size="12" fill="{MUTED}">{escape(spec["subtitle"])}</text>'
        )
        y += 26

    for idx, stage in enumerate(stages):
        cols = stage.get("columns") or [stage]
        n = len(cols)
        avail = W - PAD * 2 - COL_GAP * (n - 1)
        cw = avail // n
        h = max(box_height(c.get("items", [])) for c in cols)

        for ci, col in enumerate(cols):
            x = PAD + ci * (cw + COL_GAP)
            kind = col.get("kind", "plain")
            parts.append(
                f'<rect x="{x}" y="{y}" width="{cw}" height="{h}" rx="7" '
                f'fill="{FILLS[kind]}" stroke="{EDGES[kind]}" stroke-width="1.4"/>'
            )
            parts.append(
                f'<text x="{x + 14}" y="{y + 21}" font-family="Helvetica,Arial,sans-serif" '
                f'font-size="13.5" font-weight="700" fill="{EDGES[kind]}">'
                f'{escape(col["label"])}</text>'
            )
            ty = y + TITLE_H + BOX_PAD_Y
            for line in col.get("items", []):
                mono = line.startswith("`")
                txt = line.replace("`", "")
                fam = ("ui-monospace,SFMono-Regular,Menlo,monospace"
                       if mono else "Helvetica,Arial,sans-serif")
                parts.append(
                    f'<text x="{x + 14}" y="{ty}" font-family="{fam}" font-size="11.5" '
                    f'fill="{TEXT if mono else MUTED}">{escape(txt)}</text>'
                )
                ty += LINE_H

        y += h
        if idx < len(stages) - 1:
            cx = W // 2
            lab = stages[idx + 1].get("via")
            parts.append(
                f'<line x1="{cx}" y1="{y + 4}" x2="{cx}" y2="{y + ARROW_H - 9}" '
                f'stroke="{STROKE}" stroke-width="1.6" marker-end="url(#a)"/>'
            )
            if lab:
                parts.append(
                    f'<text x="{cx + 12}" y="{y + ARROW_H // 2 + 2}" '
                    f'font-family="ui-monospace,SFMono-Regular,Menlo,monospace" '
                    f'font-size="11" fill="{ACCENT}">{escape(lab)}</text>'
                )
            y += ARROW_H

    # qlmanage (the macOS SVG rasteriser used to produce the PNGs) scales an SVG
    # to fit the target square by HEIGHT and clips any overflow on the right. A
    # canvas that is wider than it is tall therefore loses its right-hand column.
    # Padding the canvas to at least square makes the fit-by-height safe.
    content_h = y + PAD
    h_total = max(content_h, W)
    svg = (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{h_total}" '
        f'viewBox="0 0 {W} {h_total}">'
        f'<defs><marker id="a" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" '
        f'markerHeight="7" orient="auto-start-reverse">'
        f'<path d="M 0 0 L 10 5 L 0 10 z" fill="{STROKE}"/></marker></defs>'
        f'<rect width="{W}" height="{h_total}" fill="{BG}"/>'
        + "".join(parts)
        + "</svg>"
    )
    with open(out, "w") as fh:
        fh.write(svg)
    print(f"wrote {out} ({W}x{h_total}) CONTENT_H={content_h}")


if __name__ == "__main__":
    render(json.load(open(sys.argv[1])), sys.argv[2])
