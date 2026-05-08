# io.jl
# Input/output utilities and coordinate-geometry helpers for the Galaxies puzzle:
# reading instance files, displaying grids and solutions, generating LaTeX result tables,
# and the doubled-coordinate helpers shared by generation.jl and resolution.jl.

using Plots
import GR

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




# ─────────────────────────────────────────────────────────────────────────────
# Coordinate-geometry helpers (doubled-grid, cell centre at (2i-1, 2j-1))
# ─────────────────────────────────────────────────────────────────────────────

"""
    cells_touched_by_dot(dr, dc, n, m) -> Vector{Tuple{Int,Int}}

Return the grid cells (row, col) that a dot at double-grid position (dr, dc) touches.
Touches 1, 2, or 4 cells depending on the parity of dr and dc.
"""
function cells_touched_by_dot(dr::Int, dc::Int, n::Int, m::Int)
    rows = iseven(dr) ? [dr÷2, dr÷2 + 1] : [(dr+1)÷2]
    cols = iseven(dc) ? [dc÷2, dc÷2 + 1] : [(dc+1)÷2]
    return [(r, c) for r in rows, c in cols if 1 <= r <= n && 1 <= c <= m]
end


"""
    sym_cell(i, j, dr, dc, n, m) -> Union{Tuple{Int,Int}, Nothing}

180°-symmetric image of cell (i,j) about dot (dr, dc). Cell (i,j)'s centre
is at double-grid (2i-1, 2j-1); the symmetric centre is (2dr-(2i-1), 2dc-(2j-1)),
i.e. cell (dr-i+1, dc-j+1). Returns `nothing` if the image is outside the grid.
"""
function sym_cell(i::Int, j::Int, dr::Int, dc::Int, n::Int, m::Int)
    si = dr - i + 1
    sj = dc - j + 1
    return (1 <= si <= n && 1 <= sj <= m) ? (si, sj) : nothing
end


"""
    grid_neighbors(i, j, n, m) -> Vector{Tuple{Int,Int}}

4-connected neighbours of (i,j) inside the grid.
"""
function grid_neighbors(i::Int, j::Int, n::Int, m::Int)
    nb = Tuple{Int,Int}[]
    i > 1 && push!(nb, (i-1, j))
    i < n && push!(nb, (i+1, j))
    j > 1 && push!(nb, (i, j-1))
    j < m && push!(nb, (i, j+1))
    return nb
end


# ─────────────────────────────────────────────────────────────────────────────
# Instance / solution writers
# ─────────────────────────────────────────────────────────────────────────────

"""
    saveInstance(path, n, m, dots)

Write a Galaxies instance (header + dots) to `path` in the project's standard format.
"""
function saveInstance(path::String, n::Int, m::Int, dots::Vector{Tuple{Int,Int}})
    open(path, "w") do f
        println(f, "# Double-grid coordinates: cell (i,j) has centre at (2i-1, 2j-1)")
        println(f, "$n $m")
        println(f, "# dots")
        for (dr, dc) in dots
            println(f, "$dr $dc")
        end
    end
end


"""
    writeSolution(fout, assignment)

Write a galaxy-assignment matrix (rows of integers, one row per line) to `fout`.
Used by `solveDataSet()` so that result files contain a recoverable solution
in addition to `solveTime` / `isOptimal`.
"""
function writeSolution(fout::IO, assignment::Matrix{Int})
    n, m = size(assignment)
    for i in 1:n
        println(fout, join(assignment[i, :], " "))
    end
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
        println(fout, raw"""\documentclass{article}
\usepackage[utf8]{inputenc}
\usepackage{booktabs}
\usepackage[a4paper, margin=2cm]{geometry}
\begin{document}""")
        println(fout, "\\begin{table}[h]")
        println(fout, "\\centering")
        println(fout, "\\begin{tabular}{l" * repeat("rr", length(folderName)) * "}")
        println(fout, "\\toprule")
        println(fout, "Instance" * join([" & \\multicolumn{2}{c}{$(f == "cplex" ? "CPLEX" : "Heuristic")}" for f in folderName]) * " \\\\")
        println(fout, "         " * join([" & Time (s) & $(f == "cplex" ? "Optimal?" : "Feasible?")" for f in folderName]) * " \\\\")
        println(fout, "\\midrule")

        for inst in instances
            row = replace(replace(inst, "_" => "\\_"), ".txt" => "")
            for method in folderName
                path = resultFolder * method * "/" * inst
                if isfile(path)
                    content = read(path, String)
                    st = parse(Float64, match(r"solveTime\s*=\s*([0-9.eE+\-]+)", content)[1])
                    io = strip(match(r"isOptimal\s*=\s*(\S+)", content)[1]) == "true"
                    row *= " & $(round(st, sigdigits=4)) & $(io ? "Y" : "N")"
                else
                    row *= " & -- & --"
                end
            end
            println(fout, row * " \\\\")
        end

        println(fout, "\\bottomrule")
        println(fout, "\\end{tabular}")
        println(fout, "\\label{tab:galaxies-results}")
        println(fout, "\\end{table}")
        println(fout, "\\end{document}")
    end
    println("LaTeX table written to $outputFile")
end


"""
    performanceDiagram(outputFile)

Plot a cumulative performance diagram across the methods found in `../res/`.
For each method one curve is drawn: x-axis is solve time, y-axis is the number
of instances that method has solved within that time budget.
"""
function performanceDiagram(outputFile::String)
    resultFolder = "../res/"
    methods = filter(f -> isdir(resultFolder * f), readdir(resultFolder))
    isempty(methods) && (println("No method subfolders in $resultFolder"); return)

    times_per_method = Dict{String, Vector{Float64}}()
    maxTime = 0.0

    for method in methods
        ts = Float64[]
        for f in filter(x -> endswith(x, ".txt"), readdir(resultFolder * method))
            content = read(joinpath(resultFolder, method, f), String)
            mo = match(r"isOptimal\s*=\s*(\S+)", content)
            mt = match(r"solveTime\s*=\s*([0-9.eE+\-]+)", content)
            (mo === nothing || mt === nothing) && continue
            strip(mo[1]) == "true" || continue
            t = parse(Float64, mt[1])
            push!(ts, t)
            t > maxTime && (maxTime = t)
        end
        sort!(ts)
        times_per_method[method] = ts
    end

    maxTime = max(maxTime, 1e-6)
    plt = plot(xaxis = "Time (s)", yaxis = "Solved instances",
               legend = :bottomright, xlim = (0, maxTime * 1.05))
    for method in methods
        ts = times_per_method[method]
        isempty(ts) && continue
        # Step curve: at each ts[i] the count jumps from i-1 to i
        x = Float64[0.0]
        y = Float64[0.0]
        for (i, t) in enumerate(ts)
            push!(x, t); push!(y, i - 1)   # vertical riser stays at previous count up to t
            push!(x, t); push!(y, i)       # then steps up to i
        end
        push!(x, maxTime); push!(y, length(ts))
        plot!(plt, x, y, label = method, linewidth = 3)
    end
    savefig(plt, outputFile)
    println("Performance diagram written to $outputFile")
end
