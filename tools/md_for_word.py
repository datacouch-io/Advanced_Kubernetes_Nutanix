#!/usr/bin/env python3
"""Prepare a lab markdown file for conversion to .docx.

Word has no equivalent of a few things these documents use, so they are
rewritten rather than silently dropped by the converter:

  * <details>/<summary> collapsible blocks  -> a bold "spoiler" heading plus the
    content, with an explicit warning line, since Word cannot collapse.
  * links to sibling .md files              -> links to the .docx equivalents.
  * the emoji check/cross marks in tables   -> plain words, which render
    consistently in Word on Windows.

Usage: md_for_word.py <in.md> <out.md>
"""
import re
import sys


def convert(text):
    # <details><summary>X</summary> ... </details>
    def details(m):
        summary = re.sub(r"<[^>]+>", "", m.group(1)).strip()
        body = m.group(2)
        return (f"\n> **Collapsed section in the original — {summary}**\n"
                f">\n> In Word this cannot be hidden, so it is shown in full below.\n"
                f"> Skip past it if you are attempting the exercise unaided.\n\n"
                f"{body}\n")

    text = re.sub(r"<details>\s*<summary>(.*?)</summary>(.*?)</details>",
                  details, text, flags=re.S)

    # Sibling .md links -> .docx, in both the target AND the visible label,
    # so a reader is not told to open a file that is not in the Word bundle.
    text = re.sub(r"\((?!http)([0-9A-Za-z._/-]+)\.md(#[^)]*)?\)",
                  lambda m: f"({m.group(1)}.docx)", text)
    text = re.sub(r"\[`?([0-9A-Za-z._/-]+)\.md`?(\s[^\]]*)?\]\(",
                  lambda m: f"[`{m.group(1)}.docx`{m.group(2) or ''}](", text)

    # Emoji that render inconsistently in Word
    text = text.replace("✅", "YES —").replace("❌", "NO —")

    # The document title is supplied as pandoc metadata (which also sets the
    # Word document properties), so drop the markdown H1 to avoid printing the
    # same title twice on page one.
    lines = text.split("\n")
    for i, line in enumerate(lines):
        if line.startswith("# "):
            del lines[i]
            break
    text = "\n".join(lines)
    return text


if __name__ == "__main__":
    src, dst = sys.argv[1], sys.argv[2]
    with open(src) as fh:
        out = convert(fh.read())
    with open(dst, "w") as fh:
        fh.write(out)
    print(f"prepared {dst}")
