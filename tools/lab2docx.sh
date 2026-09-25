#!/bin/bash
# lab2docx.sh <lab-file.md> "<Title>"
# Builds <lab-dir>/<lab>.docx: renders the one Mermaid block to a PNG (via Kroki),
# swaps it into a temp copy, runs md_for_word.py, then pandoc -> docx.
set -e
cd "$(dirname "$0")/.."
md="$1"; title="$2"
src_dir=$(dirname "$md")
base=$(basename "${md%.md}")
labid=$(echo "$base" | sed -E 's/^(lab-[0-9]+[a-z]?|lab-[A-Za-z]).*/\1/')
mkdir -p build "artifacts/$labid/diagrams"

# extract the mermaid block (if any)
python3 - "$md" "build/$base.mmd" <<'PY'
import sys,re
t=open(sys.argv[1]).read()
m=re.search(r"```mermaid\n(.*?)```",t,re.S)
open(sys.argv[2],"w").write(m.group(1) if m else "")
PY

img=""
if [ -s "build/$base.mmd" ]; then
  curl -s -X POST "https://kroki.io/mermaid/png" --data-binary "@build/$base.mmd" \
    -o "artifacts/$labid/diagrams/diagram.png" --max-time 60
  # sanity: must be a PNG
  if file "artifacts/$labid/diagrams/diagram.png" | grep -q 'PNG image'; then
    img="artifacts/$labid/diagrams/diagram.png"
  else
    echo "WARN: mermaid render failed for $base (keeping code block)"; img=""
  fi
fi

# swap the mermaid fence for the rendered image
python3 - "$md" "build/$base.step1.md" "$img" <<'PY'
import sys,re
md,out,img=sys.argv[1],sys.argv[2],sys.argv[3]
t=open(md).read()
if img:
    t=re.sub(r"```mermaid.*?```", f"![Architecture diagram]({img})", t, count=1, flags=re.S)
open(out,"w").write(t)
PY

python3 tools/md_for_word.py "build/$base.step1.md" "build/$base.for-word.md" >/dev/null
REF=""; [ -f build/reference-styled.docx ] && REF="--reference-doc=build/reference-styled.docx"
pandoc "build/$base.for-word.md" --from gfm --to docx --resource-path="$src_dir:.:artifacts" --toc --toc-depth=2 $REF \
  --metadata title="$title" --metadata author="DataCouch — Advanced Kubernetes (Nutanix)" \
  -o "$src_dir/$base.docx"
echo "built $src_dir/$base.docx ($(unzip -l "$src_dir/$base.docx" 2>/dev/null | grep -c 'word/media/') images)"
