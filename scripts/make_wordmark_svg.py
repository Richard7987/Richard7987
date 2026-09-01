#!/usr/bin/env python3
"""Render an animated 3D-ASCII wordmark SVG (figlet -> SVG, SMIL reveal).

Usage:  python scripts/make_wordmark_svg.py [TEXT] [OUT]
Env:
  STATIC=1        emit the final frame with no animation
  WORDMARK_FONT   pyfiglet font name (default: "ansi_shadow")

The wordmark is static content -- regenerate it by hand when the text or font
changes; the daily workflow does not touch it.
"""
import html
import os
import sys
from pathlib import Path

from pyfiglet import Figlet

TEXT = sys.argv[1] if len(sys.argv) > 1 else "nezzontli"
OUT = (
    Path(sys.argv[2])
    if len(sys.argv) > 2
    else Path(__file__).resolve().parent.parent / "ascii-wordmark.svg"
)
FONT = os.environ.get("WORDMARK_FONT", "ansi_shadow")
ANIMATE = os.environ.get("STATIC") != "1"

FS = 13.0                 # font-size, px
ADV = 7.82                # monospace advance width at FS, px
LH = FS * 1.0            # line height, px (tight, so the ASCII blocks join)
PAD = 20
FF = (
    "font-family=\"JetBrains Mono,'Fira Code','Cascadia Code',"
    "ui-monospace,Consolas,monospace\""
)


def esc(s: str) -> str:
    return html.escape(s, quote=False)


def main() -> int:
    fig = Figlet(font=FONT)
    lines = [ln.rstrip() for ln in fig.renderText(TEXT).split("\n")]
    while lines and not lines[0].strip():
        lines.pop(0)
    while lines and not lines[-1].strip():
        lines.pop()
    if not lines:
        print("empty render", file=sys.stderr)
        return 1

    cols = max(len(ln) for ln in lines)
    w = round(PAD * 2 + cols * ADV)
    h = round(PAD * 2 + len(lines) * LH)

    out = [
        f'<svg width="{w}" height="{h}" viewBox="0 0 {w} {h}" '
        f'xmlns="http://www.w3.org/2000/svg" role="img" '
        f'aria-label="{esc(TEXT)}">',
        '<defs>'
        '<linearGradient id="wm-g" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#fe8019"/>'
        '<stop offset="1" stop-color="#fabd2f"/>'
        '</linearGradient>'
        f'<clipPath id="wm-card">'
        f'<rect x="0" y="0" width="{w}" height="{h}" rx="10"/></clipPath>'
        '</defs>',
        '<g clip-path="url(#wm-card)">',
        f'<rect x="0" y="0" width="{w}" height="{h}" fill="#282828"/>',
    ]

    for i, ln in enumerate(lines):
        x = PAD
        y = round(PAD + (i + 1) * LH - LH * 0.22, 2)
        begin = 0.15 + i * 0.10
        op = "0" if ANIMATE else "1"
        text = (
            f'<text x="{x}" y="{y}" {FF} font-size="{FS}" fill="url(#wm-g)" '
            f'xml:space="preserve" opacity="{op}">'
        )
        if ANIMATE:
            text += (
                f'<animate attributeName="opacity" from="0" to="1" dur="0.28s" '
                f'begin="{begin:.2f}s" fill="freeze"/>'
                f'<animate attributeName="x" from="{x - 10}" to="{x}" dur="0.28s" '
                f'begin="{begin:.2f}s" fill="freeze"/>'
            )
        text += esc(ln) + "</text>"
        out.append(text)

    cur_x = PAD + cols * ADV + 4
    cur_y = round(PAD + len(lines) * LH - LH * 0.92, 2)
    cursor = (
        f'<rect x="{cur_x:.1f}" y="{cur_y:.1f}" width="8" height="{FS}" '
        f'fill="#8ec07c"'
    )
    if ANIMATE:
        cursor += (
            f'><animate attributeName="opacity" values="1;0;1" dur="1s" '
            f'begin="{0.15 + len(lines) * 0.10:.2f}s" repeatCount="indefinite"/>'
            f'</rect>'
        )
    else:
        cursor += "/>"
    out.append(cursor)

    out.append(
        f'<rect x="0.5" y="0.5" width="{w - 1}" height="{h - 1}" rx="10" '
        f'fill="none" stroke="#504945"/>'
    )
    out.append("</g></svg>")

    OUT.write_text("\n".join(out) + "\n", encoding="utf-8")
    print(f"wrote {OUT} ({w}x{h}, {len(lines)} lines, font={FONT!r})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
