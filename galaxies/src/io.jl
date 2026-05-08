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

Print the unsolved Galaxies grid in the same box-drawing style as `displaySolution`.
All cells are empty; galaxy centres (dots) are shown as ● at their exact position:
  - cell centre    → inside the cell
  - horizontal edge → on the ─── separator between two rows
  - vertical edge   → on the │ separator between two columns
  - corner          → on the + joint
"""
function displayGrid(n::Int, m::Int, dots::Vector{Tuple{Int,Int}})
    CW      = 3
    dot_set = Set(dots)

    # dot at double-grid (dr, dc)?
    is_dot(dr, dc) = (dr, dc) in dot_set

    # Joint character at grid corner (i,j), 0-indexed, double-grid (2i, 2j)
    joint(i, j)   = is_dot(2i, 2j) ? "●" : "+"

    # Horizontal edge segment for cell column j (1-indexed) on border row i (0-indexed)
    # double-grid position: (2i, 2j-1)
    function h_edge(i, j)
        is_dot(2i, 2j-1) ? "─●─" : "─"^CW
    end

    # Vertical bar on cell-column border j (0-indexed) for cell row i (1-indexed)
    # double-grid position: (2i-1, 2j)
    v_bar(i, j) = is_dot(2i-1, 2j) ? "●" : "│"

    # Cell interior for cell (i,j) — dot if centre matches, else blank
    # double-grid position: (2i-1, 2j-1)
    cell(i, j) = is_dot(2i-1, 2j-1) ? " ● " : " "^CW

    println("Galaxies grid  ($n × $m)")
    println()

    for i in 1:n+1
        # Horizontal rule above row i (or bottom border after last row)
        rule = join(joint(i-1, j-1) * h_edge(i-1, j) for j in 1:m) * joint(i-1, m)
        println(rule)

        if i <= n
            # Cell content row
            row = join(v_bar(i, j-1) * cell(i, j) for j in 1:m) * v_bar(i, m)
            println(row)
        end
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

    # Cell width: 2-char label + 1 space each side = 4 chars total
    CW = 3
    function label(k)
        k <= 26 && return string(Char('A' + k - 1)) * " "
        k -= 26
        suffix = string(div(k - 1, 26) + 1)
        string(Char('A' + (k - 1) % 26)) * suffix
    end

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
        row *= vbar(i, j-1) * " $(label(assignment[i,j]))"
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
    displayPartialSolution(n, m, dots, assignment)

Like `displaySolution` but tolerates unassigned cells (value 0), shown as `·`.
Borders between unassigned cells and any neighbour are drawn thin.
"""
function displayPartialSolution(n::Int, m::Int,
                                dots::Vector{Tuple{Int,Int}},
                                assignment::Matrix{Int})
    function label(k)
        k == 0  && return "· "
        k <= 26 && return string(Char('A' + k - 1)) * " "
        k -= 26
        suffix = string(div(k - 1, 26) + 1)
        string(Char('A' + (k - 1) % 26)) * suffix
    end

    CW = 3

    # thick border only between two *different assigned* galaxies
    function hsep(i)
        s = "+"
        for j in 1:m
            a, b = assignment[i,j], assignment[i+1,j]
            thick = a != 0 && b != 0 && a != b
            s *= (thick ? "═" : "─") ^ CW * "+"
        end
        return s
    end

    println("Heuristic partial solution:")
    println()
    println("+" * "─"^CW * ("+" * "─"^CW)^(m-1) * "+")
    for i in 1:n
        row = ""
        for j in 1:m
            a_left = j == 1 ? -1 : assignment[i, j-1]
            a_cur  = assignment[i, j]
            thick  = a_left != 0 && a_cur != 0 && a_left != a_cur
            row *= (j == 1 || j == m+1 ? "║" : (thick ? "║" : "│")) * " $(label(a_cur))"
        end
        row *= "║"
        println(row)
        i < n && println(hsep(i))
    end
    println("+" * "═"^CW * ("+" * "═"^CW)^(m-1) * "+")
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
