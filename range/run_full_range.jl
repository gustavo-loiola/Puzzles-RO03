# =============================================================================
#  Range Puzzle — Full Runner Script
#  Run from the range/ directory:  julia run_full_range.jl
# =============================================================================

# --- Setup ---
include(joinpath(@__DIR__, "src", "resolution.jl"))
cd(joinpath(@__DIR__, "src"))

# ═══════════════════════════════════════════════════════════════════════════════
#  PART 1 — CPLEX Resolution on Hand-Crafted Instances
# ═══════════════════════════════════════════════════════════════════════════════
println("=" ^ 70)
println("  PART 1 — CPLEX Resolution on Hand-Crafted Instances")
println("=" ^ 70)

for file in sort(filter(x -> occursin(".txt", x), readdir("../data/")))
    println("\n── Instance: $file ──")
    grid, expected = readInputFile("../data/" * file)
    n, m = size(grid)
    println("  Grid size: $(n) rows × $(m) columns")
    displayGrid(grid)

    isOpt, t, sol = cplexSolve(grid)
    println("  Optimal: $isOpt | Time: $(round(t, digits=4))s")

    if isOpt
        displaySolution(sol; grid=grid)

        valid = verifySolution(grid, sol)
        println("  Verification: ", valid ? "✓ VALID" : "✗ INVALID")

        if all(expected .!= -1)
            if sol == expected
                println("  ✓ Solution matches expected answer")
            else
                println("  ✗ MISMATCH with expected answer!")
            end
        end
    end
end

# ═══════════════════════════════════════════════════════════════════════════════
#  PART 2 — Heuristic Resolution on Hand-Crafted Instances
# ═══════════════════════════════════════════════════════════════════════════════
println("\n\n" * "=" ^ 70)
println("  PART 2 — Heuristic Resolution on Hand-Crafted Instances")
println("=" ^ 70)

for file in sort(filter(x -> occursin(".txt", x), readdir("../data/")))
    println("\n── Instance: $file ──")
    grid, _ = readInputFile("../data/" * file)

    startTime = time()
    isSolved = false
    sol = nothing
    attempts = 0

    while !isSolved && (time() - startTime) < 10.0
        isSolved, sol = heuristicSolve(grid)
        attempts += 1
    end
    elapsed = time() - startTime

    println("  Solved: $isSolved | Attempts: $attempts | Time: $(round(elapsed, digits=4))s")
    if isSolved && sol !== nothing
        displaySolution(sol; grid=grid)
    else
        println("  Heuristic could not solve this instance within 10s")
    end
end

# ═══════════════════════════════════════════════════════════════════════════════
#  PART 3 — Generate a Full Dataset
# ═══════════════════════════════════════════════════════════════════════════════
println("\n\n" * "=" ^ 70)
println("  PART 3 — Dataset Generation")
println("=" ^ 70)

generateDataSet()

nFiles = length(filter(x -> occursin(".txt", x), readdir("../data/")))
println("\nTotal instances in data/: $nFiles")

# ═══════════════════════════════════════════════════════════════════════════════
#  PART 4 — Batch Solve All Instances (CPLEX + Heuristic)
# ═══════════════════════════════════════════════════════════════════════════════
println("\n\n" * "=" ^ 70)
println("  PART 4 — Batch Solve (CPLEX + Heuristic)")
println("=" ^ 70)

solveDataSet()

# ═══════════════════════════════════════════════════════════════════════════════
#  PART 5 — Generate Results Report
# ═══════════════════════════════════════════════════════════════════════════════
println("\n\n" * "=" ^ 70)
println("  PART 5 — Results Report")
println("=" ^ 70)

resultsArray("../res/array.tex")
println("LaTeX results table written to res/array.tex")

try
    performanceDiagram("../res/performance.pdf")
    println("Performance diagram written to res/performance.pdf")
catch e
    println("Could not generate performance diagram: ", e)
end

# ═══════════════════════════════════════════════════════════════════════════════
#  Summary
# ═══════════════════════════════════════════════════════════════════════════════
println("\n\n" * "=" ^ 70)
println("  ALL DONE")
println("=" ^ 70)

nCplex = isdir("../res/cplex") ? count(f -> occursin("isOptimal = true", read(joinpath("../res/cplex", f), String)), filter(x -> occursin(".txt", x), readdir("../res/cplex"))) : 0
nHeur  = isdir("../res/heuristique") ? count(f -> occursin("isOptimal = true", read(joinpath("../res/heuristique", f), String)), filter(x -> occursin(".txt", x), readdir("../res/heuristique"))) : 0

println("  Instances in data/:           $nFiles")
println("  Solved by CPLEX:              $nCplex")
println("  Solved by Heuristic:          $nHeur")
println("  Results table:                res/array.tex")
