#!/usr/bin/env bash
# render.sh <spec.json> <out.svg>  — writes the SVG and a PNG beside it.
#
# Rasterising note: the only SVG rasteriser available on the authoring machine was
# macOS `qlmanage`, which always emits a square thumbnail and scales the SVG to fit
# by HEIGHT, clipping anything wider. make_diagram.py therefore pads every canvas to
# at least square. `sips --cropToHeightWidth` would trim the resulting bottom
# whitespace, but it crops from the CENTRE and ignores --cropOffset, which decapitates
# the diagram title — so the padding is left in place deliberately.
set -euo pipefail
spec="$1"; svg="$2"; dir=$(dirname "$svg"); base=$(basename "$svg")
python3 "$(dirname "$0")/make_diagram.py" "$spec" "$svg"
cd "$dir"
rm -f "${base%.svg}.png"
qlmanage -t -s 1800 -o . "$base" >/dev/null 2>&1
mv "$base.png" "${base%.svg}.png"
sips -g pixelWidth -g pixelHeight "${base%.svg}.png" | awk '/pixel/{printf "%s ", $2} END{print ""}'
