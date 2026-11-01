#!/usr/bin/env julia
# Render data/contributions.json with UnicodePlots: a braille-dot terminal plot
# that is printed to stdout, then traced dot by dot into contrib-heatmap.svg and
# contrib-heatmap-light.svg, which the README swaps by GitHub theme (SMIL only,
# no <script>, no external CSS, so GitHub renders them from the README).
# Cells fade in on a diagonal wipe, then the stats footer fades in; every
# animation plays once and freezes.
#
# Usage:  julia --project=scripts scripts/render_heatmap.jl
# Env:
#   STATIC=1   emit the final frame with no SMIL animation
using JSON
using UnicodePlots

const ROOT = dirname(@__DIR__)
const SRC = joinpath(ROOT, "data", "contributions.json")
const ANIMATE = get(ENV, "STATIC", "") != "1"

# each contribution cell is 2 braille chars wide and 1 tall: 4x4 dots, of which
# the last row and column stay empty as the gap between cells
const CELL_DOTS = 4
const PITCH = 3.4                # px between dots
const RADIUS = 1.35              # dot radius, px
const CHAR_W = 2PITCH
const LINE_H = 4PITCH
const PAD_X, PAD_T = 16, 2
const FOOTER_H = 62

const FF = """font-family="JetBrains Mono,'Fira Code',ui-monospace,Consolas,monospace\""""

# GitHub canvases and greens; the faintest step is strengthened so single dots stay visible
const THEMES = (
    dark = (
        out = "contrib-heatmap.svg",
        bg = "#0d1117", border = "#30363d", fg = "#e6edf3", muted = "#8b949e", faint = "#6e7681",
        colors = Dict(
            0 => (0x30, 0x36, 0x3d),
            1 => (0x1f, 0x8a, 0x3a),
            2 => (0x26, 0xa6, 0x41),
            3 => (0x2e, 0xc0, 0x4a),
            4 => (0x39, 0xd3, 0x53),
        ),
    ),
    light = (
        out = "contrib-heatmap-light.svg",
        bg = "#ffffff", border = "#d0d7de", fg = "#1f2328", muted = "#59636e", faint = "#818b98",
        colors = Dict(
            0 => (0xd0, 0xd7, 0xde),
            1 => (0x40, 0xc4, 0x63),
            2 => (0x30, 0xa1, 0x4e),
            3 => (0x27, 0x87, 0x44),
            4 => (0x21, 0x6e, 0x39),
        ),
    ),
)
# dots lit inside a cell, more contributions -> denser cell
const CENTER = [(1, 1)]
const PLUS = [(1, 0), (0, 1), (1, 1), (2, 1), (1, 2)]
const FULL = [(x, y) for y in 0:2 for x in 0:2]
const PATTERNS = Dict(
    0 => CENTER,
    1 => CENTER,
    2 => PLUS,
    3 => [PLUS; (0, 0); (2, 2)],
    4 => FULL,
)

hex((r, g, b)) = "#" * join(string.((r, g, b); base = 16, pad = 2))

function text(x, y, size, fill, body; anchor = nothing)
    a = isnothing(anchor) ? "" : """ text-anchor="$anchor\""""
    return """<text x="$x" y="$y" $FF font-size="$size" fill="$fill"$a>$body</text>"""
end

function build_plot(weeks, month_labels, colors)
    ncols = max(length(weeks), 1)
    canvas = BrailleCanvas(7, ncols * CELL_DOTS ÷ 2; blend = false)
    for (c, column) in enumerate(weeks), (r, level) in enumerate(column)
        level < 0 && continue
        color = colors[level]
        for (dx, dy) in PATTERNS[level]
            UnicodePlots.pixel!(canvas, (c - 1) * CELL_DOTS + dx, (r - 1) * CELL_DOTS + dy; color)
        end
    end

    # month names live in the title: exactly canvas-wide, so centering is a no-op
    months = fill(' ', ncols * CELL_DOTS ÷ 2)
    for (col, label) in month_labels
        at = col * CELL_DOTS ÷ 2
        at + length(label) > length(months) && continue
        months[(at + 1):(at + length(label))] .= collect(label)
    end

    plot = Plot(canvas; title = String(months), border = :none, margin = 0, padding = 1)
    for (row, label) in ((2, "Mon"), (4, "Wed"), (6, "Fri"))
        label!(plot, :l, row, label)
    end
    return plot
end

# Walk the ANSI output of the plot: braille chars become dots, the rest text.
function parse_terminal(rendered)
    dots = Tuple{Int,Int,Int,Int,String}[]   # line, col, dot x, dot y, color
    labels = Tuple{Int,Int,String}[]         # line, col, text
    for (ln, line) in enumerate(split(rendered, '\n'))
        color, col, run_start, run = "", 0, 0, ""
        flush_run() = isempty(run) || push!(labels, (ln - 1, run_start, run))
        for m in eachmatch(r"\e\[([0-9;]*)m|(.)"s, line)
            if m[1] !== nothing
                codes = parse.(Int, filter(!isempty, split(m[1], ';')))
                if length(codes) == 5 && codes[1:2] == [38, 2]
                    color = hex(UInt8.(Tuple(codes[3:5])))
                end
                continue
            end
            ch = only(m[2])
            if ch == ' ' || '⠀' <= ch <= '⣿'
                flush_run()
                run = ""
            else
                isempty(run) && (run_start = col)
                run *= ch
            end
            if '⠀' < ch <= '⣿'
                bits = UInt32(ch) - 0x2800
                for (bit, dx, dy) in (
                        (0x01, 0, 0), (0x02, 0, 1), (0x04, 0, 2), (0x40, 0, 3),
                        (0x08, 1, 0), (0x10, 1, 1), (0x20, 1, 2), (0x80, 1, 3),
                    )
                    bits & bit != 0 && push!(dots, (ln - 1, col, dx, dy, color))
                end
            end
            col += 1
        end
        flush_run()
    end
    return dots, labels
end

fmt(x) = string(round(x; digits = 2))
commas(n) = replace(string(n), r"(?<=\d)(?=(\d{3})+$)" => ",")

function render(data, theme)
    weeks = data["weeks"]
    stats = data["stats"]
    ncols = max(length(weeks), 1)

    plot = build_plot(weeks, data["month_labels"], theme.colors)
    rendered = sprint(show, plot; context = :color => true)

    dots, labels = parse_terminal(rendered)
    # where the grid starts in the terminal output, past the labels and border
    x0, y0 = isempty(dots) ? (0, 0) : (minimum(d[2] for d in dots), minimum(d[1] for d in dots))

    width = round(Int, 2PAD_X + (x0 + ncols * CELL_DOTS ÷ 2) * CHAR_W)
    grid_h = 7 * LINE_H
    height = round(Int, PAD_T + y0 * LINE_H + grid_h + FOOTER_H)
    px(col, dx = 0) = PAD_X + (col + dx / 2) * CHAR_W + PITCH / 2
    py(line, dy = 0) = PAD_T + (line + dy / 4) * LINE_H + PITCH / 2
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

    for (line, col, body) in labels
        # the month row hugs the grid instead of leaving the plot's border line between
        y = fmt(PAD_T + (line < y0 ? y0 - 0.3 : line + 0.75) * LINE_H)
        push!(out, text(fmt(PAD_X + col * CHAR_W), y, 10, theme.muted, body))
    end

    cells = Dict{Tuple{Int,Int},Vector{eltype(dots)}}()
    for d in dots
        push!(get!(cells, ((d[2] - x0) ÷ 2, d[1] - y0), eltype(dots)[]), d)
    end
    for ((c, r), members) in sort!(collect(cells); by = first)
        cell = """<g fill="$(members[1][5])" opacity="$(ANIMATE ? 0 : 1)">"""
        if ANIMATE
            begin_at = round(0.2 + c * 0.02 + r * 0.055; digits = 2)
            cell *= """<animate attributeName="opacity" from="0" to="1" """ *
                """dur="0.35s" begin="$(begin_at)s" fill="freeze"/>"""
        end
        for (line, col, dx, dy, _) in members
            cell *= """<circle cx="$(fmt(px(col, dx)))" cy="$(fmt(py(line, dy)))" r="$RADIUS"/>"""
        end
        push!(out, cell * "</g>")
    end

    # footer: stats + legend
    fy = round(Int, PAD_T + y0 * LINE_H + grid_h + 16)
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
    left = fmt(PAD_X + x0 * CHAR_W)
    push!(out, text(left, fy, 11, theme.fg, line1))
    push!(out, text(left, fy + 16, 11, theme.muted, line2))

    step = CELL_DOTS * PITCH
    legend_x = width - PAD_X - 5step - 34
    push!(out, text(fmt(legend_x - 6), fy, 10, theme.muted, "Less"; anchor = "end"))
    for level in 0:4
        circles = join(
            """<circle cx="$(fmt(legend_x + level * step + (dx + 0.5) * PITCH))" """ *
                """cy="$(fmt(fy - 9 + (dy + 0.5) * PITCH))" r="$RADIUS"/>"""
                for (dx, dy) in PATTERNS[level]
        )
        push!(out, """<g fill="$(hex(theme.colors[level]))">$circles</g>""")
    end
    push!(out, text(fmt(legend_x + 5step + 2), fy, 10, theme.muted, "More"))
    push!(out, "</g>")

    push!(out, text(width - PAD_X, height - 8, 9, theme.faint, "updated $(data["generated_at"])"; anchor = "end"))
    push!(
        out,
        """<rect x="0.5" y="0.5" width="$(width - 1)" height="$(height - 1)" rx="10" """ *
            """fill="none" stroke="$(theme.border)"/>""",
    )
    push!(out, "</g></svg>")

    path = joinpath(ROOT, theme.out)
    write(path, join(out, "\n") * "\n")
    println("wrote $path ($(width)x$height, $(length(weeks)) weeks, $(length(dots)) dots)")
end

function main()
    data = JSON.parsefile(SRC)
    UnicodePlots.truecolors!()
    plot = build_plot(data["weeks"], data["month_labels"], THEMES.dark.colors)
    println(IOContext(stdout, :color => get(stdout, :color, false)), plot)
    foreach(theme -> render(data, theme), THEMES)
    return 0
end

exit(main())
