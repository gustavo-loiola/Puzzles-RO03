# ─────────────────────────────────────────────────────────────────────────────
#  io.jl — I/O, display and reporting utilities for the Galaxies puzzle
# ─────────────────────────────────────────────────────────────────────────────

"""
Read a Galaxies instance from a text file.

Expected format:
    m n                       ← grid dimensions (columns, rows)
    p1 q1                     ← dot positions in doubled coordinates
    p2 q2
    ...
    # solution                ← optional section
    k11 k12 k13 ...          ← galaxy index per cell, row by row
    k21 k22 k23 ...
    ...

Returns:
- grid:     tuple (n, m) — number of rows and columns
- dots:     Vector{Tuple{Int,Int}} — dot positions (p, q) in doubled coords
- solution: n×m Matrix{Int} of galaxy indices, or `nothing` if absent
"""
function readInputFile(path::String)

    lines = readlines(path)
    idx = 1

    # Skip leading blanks / comments
    while idx <= length(lines) &&
          (isempty(strip(lines[idx])) || startswith(strip(lines[idx]), "#"))
        idx += 1
    end

    # ── Dimensions ───────────────────────────────────────────────────────
    parts = split(strip(lines[idx]))
    m_cols = parse(Int, parts[1])
    n_rows = parse(Int, parts[2])
    idx += 1

    # ── Dot positions ────────────────────────────────────────────────────
    dots = Tuple{Int,Int}[]
    while idx <= length(lines)
        line = strip(lines[idx])
        if isempty(line) || startswith(line, "#")
            idx += 1
            # If we hit "# solution", break to read it next
            if startswith(line, "# solution")
                break
            end
            continue
        end
        tokens = split(line)
        if length(tokens) == 2
            p = parse(Int, tokens[1])
            q = parse(Int, tokens[2])
            push!(dots, (p, q))
            idx += 1
        else
            break   # more than 2 tokens → probably solution section
        end
    end

    # ── Optional solution ────────────────────────────────────────────────
    solution = nothing

    # Advance past blank lines / "# solution" header
    while idx <= length(lines) &&
          (isempty(strip(lines[idx])) || startswith(strip(lines[idx]), "#"))
        idx += 1
    end

    if idx <= length(lines)
        solution = fill(0, n_rows, m_cols)
        row = 1
        while idx <= length(lines) && row <= n_rows
            line = strip(lines[idx])
            if isempty(line) || startswith(line, "#")
                idx += 1
                continue
            end
            tokens = split(line)
            for j in 1:m_cols
                solution[row, j] = parse(Int, tokens[j])
            end
            row += 1
            idx += 1
        end
        if row <= n_rows
            solution = nothing      # incomplete solution data
        end
    end

    return (n_rows, m_cols), dots, solution
end


"""
Display the grid with dot positions in a text representation.

Uses a (2n+1) × (2m+1) character grid. Cell interiors are shown as ` `,
dots as `●` (or `o` if stdout does not support Unicode).
"""
function displayGrid(grid, dots)

    n, m = grid
    # Build a character canvas: rows 0..2n, cols 0..2m
    # Even rows/cols = cell boundaries, odd rows/cols = cell interiors
    rows = 2n + 1
    cols = 2m + 1

    canvas = fill(' ', rows, cols)

    # Draw grid lines
    for r in 1:rows
        for c in 1:cols
            if r % 2 == 1 && c % 2 == 1
                canvas[r, c] = '+'
            elseif r % 2 == 1
                canvas[r, c] = '-'
            elseif c % 2 == 1
                canvas[r, c] = '|'
            end
        end
    end

    # Place dots — convert doubled coords (p, q) to canvas coords
    # Cell (i,j) centre in canvas = (2i, 2j).  Doubled coord (p,q) maps
    # directly to canvas position (p, q) since canvas rows/cols go 1..2n+1
    # and doubled coords go 1..2n.
    for (p, q) in dots
        if 1 <= p <= 2n && 1 <= q <= 2m
            canvas[p, q] = 'o'
        end
    end

    println("Grid $(n)×$(m) with $(length(dots)) galaxies:")
    for r in 1:rows
        println(String(canvas[r, :]))
    end
    println()
end


"""
Display a solved grid, colouring each cell with its galaxy index.
"""
function displaySolution(grid, dots, solution)

    n, m = grid

    println("Solution:")
    # Determine column width based on max galaxy index
    maxIdx = maximum(solution)
    w = max(2, length(string(maxIdx)) + 1)

    for i in 1:n
        for j in 1:m
            print(lpad(string(solution[i, j]), w))
        end
        println()
    end
    println()
end


"""
Write a solution matrix to an open IO stream (one row per line).
"""
function writeSolution(fout::IO, solution::Matrix{Int})
    n, m = size(solution)
    for i in 1:n
        println(fout, join(solution[i, :], " "))
    end
end


"""
Generate a LaTeX performance‐comparison table from the result files
in `../res/cplex/`.
"""
function resultsArray(outputFile::String)

    resFolder  = "../res/cplex/"
    dataFolder = "../data/"

    if !isdir(resFolder)
        println("No results folder found at $resFolder")
        return
    end

    fout = open(outputFile, "w")
    println(fout, raw"\begin{tabular}{|l|c|c|}")
    println(fout, raw"\hline")
    println(fout, raw"Instance & Optimal & Time (s) \\")
    println(fout, raw"\hline")

    for file in sort(filter(x -> occursin(".txt", x), readdir(resFolder)))
        # Read result file
        isOptimal = false
        solveTime = -1.0
        for line in readlines(resFolder * file)
            if startswith(line, "solveTime")
                solveTime = parse(Float64, split(line, "=")[2])
            elseif startswith(line, "isOptimal")
                isOptimal = parse(Bool, strip(split(line, "=")[2]))
            end
        end
        name = replace(file, ".txt" => "")
        opt  = isOptimal ? "Yes" : "No"
        t    = round(solveTime, sigdigits = 3)
        println(fout, "$name & $opt & $t \\\\")
    end

    println(fout, raw"\hline")
    println(fout, raw"\end{tabular}")
    close(fout)
    println("LaTeX table written to $outputFile")
end