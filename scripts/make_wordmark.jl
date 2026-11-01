#!/usr/bin/env julia
# Render the animated 3D-ASCII wordmark SVGs (SMIL reveal), one per GitHub theme;
# the README swaps them.
#
# Usage:  julia scripts/make_wordmark.jl [OUT_DIR]
# Env:
#   STATIC=1   emit the final frame with no animation
#
# The wordmark is static content -- regenerate it by hand when the text changes;
# the daily workflow does not touch it.
const OUT_DIR = length(ARGS) >= 1 ? ARGS[1] : dirname(@__DIR__)
const ANIMATE = get(ENV, "STATIC", "") != "1"

const TEXT = "nezzontli"
const LINES = split(
    """
███╗   ██╗███████╗███████╗███████╗ ██████╗ ███╗   ██╗████████╗██╗     ██╗
████╗  ██║██╔════╝╚══███╔╝╚══███╔╝██╔═══██╗████╗  ██║╚══██╔══╝██║     ██║
██╔██╗ ██║█████╗    ███╔╝   ███╔╝ ██║   ██║██╔██╗ ██║   ██║   ██║     ██║
██║╚██╗██║██╔══╝   ███╔╝   ███╔╝  ██║   ██║██║╚██╗██║   ██║   ██║     ██║
██║ ╚████║███████╗███████╗███████╗╚██████╔╝██║ ╚████║   ██║   ███████╗██║
╚═╝  ╚═══╝╚══════╝╚══════╝╚══════╝ ╚═════╝ ╚═╝  ╚═══╝   ╚═╝   ╚══════╝╚═╝
""", '\n'; keepempty = false
)

const FS = 13.0                 # font-size, px
const ADV = 7.82                # monospace advance width at FS, px
const LH = FS                   # line height, px (tight, so the ASCII blocks join)
const PAD = 20
const FF = """font-family="JetBrains Mono,'Fira Code','Cascadia Code',ui-monospace,Consolas,monospace\""""

const THEMES = (
    (
        out = "ascii-wordmark.svg", bg = "#0d1117", border = "#30363d",
        top = "#fe8019", bottom = "#fabd2f", cursor = "#8ec07c",
    ),
    (
        out = "ascii-wordmark-light.svg", bg = "#ffffff", border = "#d0d7de",
        top = "#af3a03", bottom = "#b57614", cursor = "#427b58",
    ),
)

function render(theme)
    cols = maximum(length, LINES)
    w = round(Int, PAD * 2 + cols * ADV)
    h = round(Int, PAD * 2 + length(LINES) * LH)

    out = String[
        """<svg width="$w" height="$h" viewBox="0 0 $w $h" """ *
            """xmlns="http://www.w3.org/2000/svg" role="img" aria-label="$TEXT">""",
        """<defs><linearGradient id="wm-g" x1="0" y1="0" x2="0" y2="1">""" *
            """<stop offset="0" stop-color="$(theme.top)"/>""" *
            """<stop offset="1" stop-color="$(theme.bottom)"/></linearGradient>""" *
            """<clipPath id="wm-card"><rect x="0" y="0" width="$w" height="$h" rx="10"/></clipPath></defs>""",
        """<g clip-path="url(#wm-card)">""",
        """<rect x="0" y="0" width="$w" height="$h" fill="$(theme.bg)"/>""",
    ]

    for (i, ln) in enumerate(LINES)
        y = round(PAD + i * LH - LH * 0.22; digits = 2)
        begin_at = round(0.15 + (i - 1) * 0.10; digits = 2)
        el = """<text x="$PAD" y="$y" $FF font-size="$FS" fill="url(#wm-g)" """ *
            """xml:space="preserve" opacity="$(ANIMATE ? 0 : 1)">"""
        if ANIMATE
            el *= """<animate attributeName="opacity" from="0" to="1" dur="0.28s" """ *
                """begin="$(begin_at)s" fill="freeze"/>""" *
                """<animate attributeName="x" from="$(PAD - 10)" to="$PAD" dur="0.28s" """ *
                """begin="$(begin_at)s" fill="freeze"/>"""
        end
        push!(out, el * ln * "</text>")
    end

    cur_x = round(PAD + cols * ADV + 4; digits = 1)
    cur_y = round(PAD + length(LINES) * LH - LH * 0.92; digits = 1)
    cursor = """<rect x="$cur_x" y="$cur_y" width="8" height="$FS" fill="$(theme.cursor)\""""
    if ANIMATE
        cursor *= """><animate attributeName="opacity" values="1;0;1" dur="1s" """ *
            """begin="$(round(0.15 + length(LINES) * 0.10; digits = 2))s" repeatCount="indefinite"/></rect>"""
    else
        cursor *= "/>"
    end
    push!(out, cursor)

    push!(
        out,
        """<rect x="0.5" y="0.5" width="$(w - 1)" height="$(h - 1)" rx="10" fill="none" stroke="$(theme.border)"/>""",
    )
    push!(out, "</g></svg>")

    path = joinpath(OUT_DIR, theme.out)
    write(path, join(out, "\n") * "\n")
    println("wrote $path ($(w)x$h, $(length(LINES)) lines)")
end

function main()
    foreach(render, THEMES)
    return 0
end

exit(main())
