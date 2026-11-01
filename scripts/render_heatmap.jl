#!/usr/bin/env julia
# Render data/contributions.json into contrib-heatmap.svg and
# contrib-heatmap-light.svg, which the README swaps by GitHub theme (SMIL only,
# no <script>, no external CSS, so GitHub renders them from the README).
# Cells fade in on a diagonal wipe, then the stats footer fades in; every
# animation plays once and freezes.
#
# Usage:  julia --project=scripts scripts/render_heatmap.jl
# Env:
#   STATIC=1   emit the final frame with no SMIL animation
using JSON

const ROOT = dirname(@__DIR__)
const SRC = joinpath(ROOT, "data", "contributions.json")
const ANIMATE = get(ENV, "STATIC", "") != "1"

const CELL, GAP = 11, 3
const BLOCK = CELL + GAP
const PAD_L, PAD_R, PAD_T = 42, 16, 28
const GRID_H = 7 * BLOCK - GAP
const FOOTER_H = 62

const FF = """font-family="JetBrains Mono,'Fira Code',ui-monospace,Consolas,monospace\""""

# GitHub canvases and contribution greens
const THEMES = (
    (
        out = "contrib-heatmap.svg",
        bg = "#0d1117", border = "#30363d", fg = "#e6edf3", muted = "#8b949e", faint = "#6e7681",
        colors = Dict(0 => "#161b22", 1 => "#0e4429", 2 => "#006d32", 3 => "#26a641", 4 => "#39d353"),
    ),
    (
        out = "contrib-heatmap-light.svg",
        bg = "#ffffff", border = "#d0d7de", fg = "#1f2328", muted = "#59636e", faint = "#818b98",
        colors = Dict(0 => "#ebedf0", 1 => "#9be9a8", 2 => "#40c463", 3 => "#30a14e", 4 => "#216e39"),
    ),
)

function text(x, y, size, fill, body; anchor = nothing)
    a = isnothing(anchor) ? "" : """ text-anchor="$anchor\""""
    return """<text x="$x" y="$y" $FF font-size="$size" fill="$fill"$a>$body</text>"""
end

commas(n) = replace(string(n), r"(?<=\d)(?=(\d{3})+$)" => ",")

function render(data, theme)
    weeks = data["weeks"]
    stats = data["stats"]
    ncols = max(length(weeks), 1)

    width = PAD_L + ncols * BLOCK - GAP + PAD_R
    height = PAD_T + GRID_H + FOOTER_H
    grid_end = 0.2 + ncols * 0.02 + 6 * 0.055

    out = String[
        """<svg width="$width" height="$height" viewBox="0 0 $width $height" """ *
            """xmlns="http://www.w3.org/2000/svg" role="img" """ *
            """aria-label="GitHub contribution heatmap for $(data["user"])">""",
        """<defs><clipPath id="hm-card">""" *
            """<rect x="0" y="0" width="$width" height="$height" rx="10"/>""" *
            """</clipPath></defs>""",
        """<g clip-path="url(#hm-card)">""",
        """<rect width="$width" height="$height" fill="$(theme.bg)"/>""",
    ]

    for (col, label) in data["month_labels"]
        push!(out, text(PAD_L + col * BLOCK, PAD_T - 8, 10, theme.muted, label))
    end
    for (row, label) in ((1, "Mon"), (3, "Wed"), (5, "Fri"))
        push!(out, text(14, PAD_T + row * BLOCK + CELL - 2, 10, theme.muted, label))
    end

    for (c, column) in enumerate(weeks), (r, level) in enumerate(column)
        level < 0 && continue    # days that have not happened yet
        x = PAD_L + (c - 1) * BLOCK
        y = PAD_T + (r - 1) * BLOCK
        cell = """<rect x="$x" y="$y" width="$CELL" height="$CELL" rx="2" """ *
            """fill="$(theme.colors[level])" opacity="$(ANIMATE ? 0 : 1)">"""
        if ANIMATE
            begin_at = round(0.2 + (c - 1) * 0.02 + (r - 1) * 0.055; digits = 2)
            cell *= """<animate attributeName="opacity" from="0" to="1" """ *
                """dur="0.35s" begin="$(begin_at)s" fill="freeze"/>"""
        end
        push!(out, cell * "</rect>")
    end

    # footer: stats + legend
    fy = PAD_T + GRID_H + 22
    best = stats["best_day"]
    line1 = "$(commas(stats["total"])) contributions  ·  $(stats["active_days"]) active days"
    line2 = "current streak $(stats["current_streak"])d  ·  longest $(stats["longest_streak"])d"
    isnothing(best) || (line2 *= "  ·  best day $(best["count"]) ($(best["date"]))")

    if ANIMATE
        push!(
            out,
            """<g opacity="0"><animate attributeName="opacity" from="0" to="1" """ *
                """dur="0.5s" begin="$(round(grid_end + 0.4; digits = 2))s" fill="freeze"/>""",
        )
    else
        push!(out, """<g opacity="1">""")
    end
    push!(out, text(PAD_L, fy, 11, theme.fg, line1))
    push!(out, text(PAD_L, fy + 16, 11, theme.muted, line2))

    legend_x = width - PAD_R - 5 * (CELL + 2) - 34
    push!(out, text(legend_x - 6, fy, 10, theme.muted, "Less"; anchor = "end"))
    for level in 0:4
        push!(
            out,
            """<rect x="$(legend_x + level * (CELL + 2))" y="$(fy - 9)" width="$CELL" """ *
                """height="$CELL" rx="2" fill="$(theme.colors[level])"/>""",
        )
    end
    push!(out, text(legend_x + 5 * (CELL + 2) + 4, fy, 10, theme.muted, "More"))
    push!(out, "</g>")

    push!(out, text(width - PAD_R, height - 8, 9, theme.faint, "updated $(data["generated_at"])"; anchor = "end"))
    push!(
        out,
        """<rect x="0.5" y="0.5" width="$(width - 1)" height="$(height - 1)" rx="10" """ *
            """fill="none" stroke="$(theme.border)"/>""",
    )
    push!(out, "</g></svg>")

    path = joinpath(ROOT, theme.out)
    write(path, join(out, "\n") * "\n")
    println("wrote $path ($(width)x$height, $(length(weeks)) weeks)")
end

function main()
    data = JSON.parsefile(SRC)
    foreach(theme -> render(data, theme), THEMES)
    return 0
end

exit(main())
