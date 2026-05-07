# io.jl
# Input/output utilities for the Galaxies puzzle:
# reading instance files, displaying grids and solutions, and generating LaTeX result tables.

# ─────────────────────────────────────────────────────────────────────────────
# Instance file format (double-grid coordinates)
# ─────────────────────────────────────────────────────────────────────────────
#
# A dot can sit at four kinds of positions in the grid. We encode them with a
# "double-grid": every cell (i,j) has its centre at double-grid point (2i-1, 2j-1),
# so the valid range is 1..2n-1 (rows) × 1..2m-1 (cols).
#
#   Position type    dr parity   dc parity   Cells touched
#   ─────────────────────────────────────────────────────
#   Cell centre      odd         odd         1  → (i,j)
#   Horizontal edge  even        odd         2  → (i,j) and (i+1,j)
#   Vertical edge    odd         even        2  → (i,j) and (i,j+1)
#   Corner           even        even        4  → (i,j),(i+1,j),(i,j+1),(i+1,j+1)
#
# File layout:
#   n_rows n_cols        ← header
#   dr1 dc1              ← one dot per line (double-grid coords, comments ignored)
#   dr2 dc2
#   ...

"""
    readInputFile(path) -> (n, m, dots)

Read a Galaxies instance from `path`.
Returns grid dimensions `n` (rows) and `m` (cols), and a `Vector{Tuple{Int,Int}}`
of dot positions in double-grid coordinates.
"""
function readInputFile(path::String)
    open(path) do f
        lines = filter(l -> !startswith(strip(l), "#") && !isempty(strip(l)),
                       readlines(f))
        n, m = parse.(Int, split(strip(lines[1])))
        dots = [(parse(Int, split(l)[1]), parse(Int, split(l)[2])) for l in lines[2:end]]
        return n, m, dots
    end
end


"""
    displayGrid(n, m, dots)

Print the empty Galaxies grid on the double-grid (size 2n-1 × 2m-1).
Dots are shown as ●. Row/column indices are printed along the border.
"""
function displayGrid(n::Int, m::Int, dots::Vector{Tuple{Int,Int}})
    R, C    = 2n - 1, 2m - 1
    dot_set = Set(dots)

    println("Galaxies grid  ($n × $m cells, double-grid $R × $C)")
    println()

    # column index header — two-digit friendly
    print("     ")
    for j in 1:C
        print(j % 10)
    end
    println()

    for i in 1:R
        print(lpad(i, 3), "  ")
        for j in 1:C
            if (i, j) in dot_set
                print("●")
            elseif iseven(i) && iseven(j)
                print("·")   # corner intersection
            elseif iseven(i)
                print("─")   # horizontal edge midpoint
            elseif iseven(j)
                print("│")   # vertical edge midpoint
            else
                print(" ")   # cell centre
            end
        end
        println()
    end
    println()
end


"""
    displaySolution(n, m, dots, assignment)

Print the solved grid. Each cell shows its galaxy label (A–Z, then numbers).
Full continuous borders are drawn around every cell; shared borders between
cells of the same galaxy are drawn as a thin interior line, while borders
between different galaxies are drawn as a thick separator.
"""
function displaySolution(n::Int, m::Int,
                         dots::Vector{Tuple{Int,Int}},
                         assignment::Matrix{Int})

    # Cell width (characters between vertical bars): label + padding
    CW = 3   # " A " — one space each side

    label(k) = k <= 26 ? string(Char('A' + k - 1)) : string(k)

    # ── helpers ──────────────────────────────────────────────────────────────

    # Full horizontal rule spanning all columns
    full_rule(ch) = "+" * repeat(ch ^ CW * "+", m)

    # Horizontal separator between row i and row i+1:
    # thick "═══" where galaxies differ, thin "───" where they are the same.
    function hsep(i)
        s = "+"
        for j in 1:m
            s *= (assignment[i,j] != assignment[i+1,j] ? "═" ^ CW : "─" ^ CW) * "+"
        end
        return s
    end

    # Vertical bar between cell (i,j) and (i,j+1):
    # thick "║" where galaxies differ, thin "│" where the same.
    function vbar(i, j)
        j == 0 && return "║"   # left border
        j == m && return "║"   # right border
        return assignment[i,j] != assignment[i,j+1] ? "║" : "│"
    end

    # ── print ─────────────────────────────────────────────────────────────────

    println("Galaxies solution:")
    println()
    println(full_rule("═"))

    for i in 1:n
        # Cell row
        row = ""
        for j in 1:m
            row *= vbar(i, j-1) * " $(label(assignment[i,j])) "
        end
        row *= vbar(i, m)
        println(row)

        # Separator row (skip after last row)
        i < n && println(hsep(i))
    end

    println(full_rule("═"))
    println()
end


"""
    resultsArray(outputFile)

Write a LaTeX table comparing solve times and optimality across all methods
found in `../res/` sub-directories.
"""
function resultsArray(outputFile::String)
    resultFolder = "../res/"
    folderName   = filter(f -> isdir(resultFolder * f), readdir(resultFolder))
    instances    = unique(vcat([filter(x -> endswith(x, ".txt"),
                                       readdir(resultFolder * f)) for f in folderName]...))

    open(outputFile, "w") do fout
        println(fout, "\\documentclass{article}\n\\usepackage{booktabs}\n\\begin{document}")
        println(fout, "\\begin{tabular}{l" * repeat("rr", length(folderName)) * "}")
        println(fout, "\\toprule")
        println(fout, "Instance" * join([" & \\multicolumn{2}{c}{$f}" for f in folderName]) * " \\\\")
        println(fout, join(["& Time (s) & Opt?" for _ in folderName]) * " \\\\\\midrule")

        for inst in instances
            row = replace(inst, "_" => "\\_")
            for method in folderName
                path = resultFolder * method * "/" * inst
                if isfile(path)
                    include(path)   # defines solveTime and isOptimal
                    row *= " & $(round(solveTime, digits=2)) & $(isOptimal ? "Y" : "N")"
                else
                    row *= " & -- & --"
                end
            end
            println(fout, row * " \\\\")
        end

        println(fout, "\\bottomrule\n\\end{tabular}\n\\end{document}")
    end
    println("LaTeX table written to $outputFile")
end
