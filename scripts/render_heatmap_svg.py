#!/usr/bin/env python3
"""Render data/contributions.json into an animated contrib-heatmap.svg.

The SVG is self-contained (no <script>, no external CSS), so GitHub renders it
straight from the README. Cells fade in on a diagonal wipe, then the stats
footer fades in; every animation plays once and freezes.

Env:
  STATIC=1   emit the final frame with no SMIL animation
"""
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "data" / "contributions.json"
OUT = ROOT / "contrib-heatmap.svg"
ANIMATE = os.environ.get("STATIC") != "1"

CELL, GAP = 11, 3
BLOCK = CELL + GAP
PAD_L, PAD_R, PAD_T = 30, 16, 22
GRID_H = 7 * BLOCK - GAP
FOOTER_H = 56

# gruvbox-dark green ramp, matched to banner.svg
COLORS = {
    -1: "#32302f",
    0: "#3c3836",
    1: "#4e6a3f",
    2: "#689d6a",
    3: "#8ec07c",
    4: "#b8bb26",
}
FF = (
    'font-family="JetBrains Mono,\'Fira Code\',ui-monospace,'
    'Consolas,monospace"'
)


def text(x, y, size, fill, body, anchor=None):
    a = f' text-anchor="{anchor}"' if anchor else ""
    return f'<text x="{x}" y="{y}" {FF} font-size="{size}" fill="{fill}"{a}>{body}</text>'


def main() -> int:
    data = json.loads(SRC.read_text(encoding="utf-8"))
    weeks = data.get("weeks", [])
    months = data.get("month_labels", [])
    stats = data.get("stats", {})
    ncols = max(len(weeks), 1)

    width = PAD_L + ncols * BLOCK - GAP + PAD_R
    height = PAD_T + GRID_H + FOOTER_H
    grid_end = 0.2 + ncols * 0.02 + 6 * 0.055

    out = [
        f'<svg width="{width}" height="{height}" viewBox="0 0 {width} {height}" '
        f'xmlns="http://www.w3.org/2000/svg" role="img" '
        f'aria-label="GitHub contribution heatmap for {data.get("user", "")}">',
        f'<defs><clipPath id="hm-card">'
        f'<rect x="0" y="0" width="{width}" height="{height}" rx="10"/>'
        f'</clipPath></defs>',
        '<g clip-path="url(#hm-card)">',
        f'<rect width="{width}" height="{height}" fill="#282828"/>',
    ]

    for col, label in months:
        out.append(text(PAD_L + col * BLOCK, PAD_T - 8, 10, "#a89984", label))

    for row, label in ((1, "Mon"), (3, "Wed"), (5, "Fri")):
        out.append(text(0, PAD_T + row * BLOCK + CELL - 2, 10, "#a89984", label))

    for c, column in enumerate(weeks):
        x = PAD_L + c * BLOCK
        for r, level in enumerate(column):
            y = PAD_T + r * BLOCK
            fill = COLORS.get(level, COLORS[0])
            op = "0" if ANIMATE else "1"
            cell = (
                f'<rect x="{x}" y="{y}" width="{CELL}" height="{CELL}" rx="2" '
                f'fill="{fill}" opacity="{op}">'
            )
            if ANIMATE:
                begin = 0.2 + c * 0.02 + r * 0.055
                cell += (
                    f'<animate attributeName="opacity" from="0" to="1" '
                    f'dur="0.35s" begin="{begin:.2f}s" fill="freeze"/>'
                )
            out.append(cell + "</rect>")

    # footer: stats + legend
    fy = PAD_T + GRID_H + 22
    total = stats.get("total", 0)
    best = stats.get("best_day") or {}
    line1 = f"{total:,} contributions  ·  {stats.get('active_days', 0)} active days"
    line2 = (
        f"current streak {stats.get('current_streak', 0)}d  ·  "
        f"longest {stats.get('longest_streak', 0)}d"
    )
    if best:
        line2 += f"  ·  best day {best.get('count', 0)} ({best.get('date', '')})"

    if ANIMATE:
        out.append(
            f'<g opacity="0"><animate attributeName="opacity" from="0" to="1" '
            f'dur="0.5s" begin="{grid_end + 0.4:.2f}s" fill="freeze"/>'
        )
    else:
        out.append('<g opacity="1">')
    out.append(text(PAD_L, fy, 11, "#ebdbb2", line1))
    out.append(text(PAD_L, fy + 16, 11, "#a89984", line2))

    legend_x = width - PAD_R - 5 * (CELL + 2) - 34
    out.append(text(legend_x - 4, fy + 9, 10, "#a89984", "Less", anchor="end"))
    for i in range(5):
        out.append(
            f'<rect x="{legend_x + i * (CELL + 2)}" y="{fy}" width="{CELL}" '
            f'height="{CELL}" rx="2" fill="{COLORS[i]}"/>'
        )
    out.append(text(legend_x + 5 * (CELL + 2) + 4, fy + 9, 10, "#a89984", "More"))
    out.append("</g>")

    out.append(
        text(
            width - PAD_R,
            height - 8,
            9,
            "#665c54",
            f"updated {data.get('generated_at', '')}",
            anchor="end",
        )
    )
    out.append(
        f'<rect x="0.5" y="0.5" width="{width - 1}" height="{height - 1}" rx="10" '
        f'fill="none" stroke="#504945"/>'
    )
    out.append("</g></svg>")

    OUT.write_text("\n".join(out) + "\n", encoding="utf-8")
    print(f"wrote {OUT} ({width}x{height}, {len(weeks)} weeks)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
