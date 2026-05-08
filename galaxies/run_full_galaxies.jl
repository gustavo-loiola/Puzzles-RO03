# =============================================================================
#  Galaxies Puzzle — Full Runner Script
#  Run from the galaxies/ directory:  julia run_full_galaxies.jl
# =============================================================================

# --- Setup ---
include(joinpath(@__DIR__, "src", "resolution.jl"))
cd(joinpath(@__DIR__, "src"))

# ═════════════════════════════════════════════════════════════════════════════
#  PART 1 — CPLEX Resolution on Hand-Crafted Instances
# ═════════════════════════════════════════════════════════════════════════════
println("=" ^ 70)
println("  PART 1 — CPLEX Resolution on Hand-Crafted Instances")
println("=" ^ 70)

# If data/ is empty, generate first
dataFiles = filter(x -> occursin(".txt", x), readdir("../data/"))
if isempty(dataFiles)
    println("\nNo instances found. Generating dataset...")
    generateDataSet()
end

for file in sort(filter(x -> occursin(".txt", x), readdir("../data/")))
    println("\n── Instance: $file ──")
    n, m, dots = readInputFile("../data/" * file)
    println("  Grid size: $(n) rows × $(m) columns, $(length(dots)) galaxies")
    displayGrid(n, m, dots)

    is_opt, t, sol, _, ncuts = cplexSolve(n, m, dots; time_limit = 120.0)
    println("  Lazy cuts added: $ncuts")
    println("  CPLEX  Optimal: $is_opt | Time: $(round(t, digits=4))s")

    if is_opt
        displaySolution(n, m, dots, sol)
        valid = verifySolution(n, m, dots, sol)
        println("  Verification: ", valid ? "✓ VALID" : "✗ INVALID")
    else
        println("  ✗ No feasible solution found within the time limit")
    end
end

# ═════════════════════════════════════════════════════════════════════════════
#  PART 2 — Heuristic Resolution on Hand-Crafted Instances
# ═════════════════════════════════════════════════════════════════════════════
println("\n\n" * "=" ^ 70)
println("  PART 2 — Heuristic Resolution on Hand-Crafted Instances")
println("=" ^ 70)

for file in sort(filter(x -> occursin(".txt", x), readdir("../data/")))
    println("\n── Instance: $file ──")
    n, m, dots = readInputFile("../data/" * file)

    _, _, eligible = precompute(n, m, dots)
    startTime = time()
    isSolved = false
    sol = nothing
    attempts = 0

    while !isSolved && (time() - startTime) < 10.0
        isSolved, sol = heuristicSolve(n, m, dots, eligible)
        attempts += 1
    end
    elapsed = time() - startTime

    println("  Solved: $isSolved | Attempts: $attempts | Time: $(round(elapsed, digits=4))s")
    if isSolved && sol !== nothing
        displaySolution(n, m, dots, sol)
        valid = verifySolution(n, m, dots, sol)
        println("  Verification: ", valid ? "✓ VALID" : "✗ INVALID")
    else
        println("  Heuristic could not solve this instance within 10s")
    end
end

# ═════════════════════════════════════════════════════════════════════════════
#  PART 3 — Generate a Full Dataset
# ═════════════════════════════════════════════════════════════════════════════
println("\n\n" * "=" ^ 70)
println("  PART 3 — Dataset Generation")
println("=" ^ 70)

generateDataSet()

nFiles = length(filter(x -> occursin(".txt", x), readdir("../data/")))
println("\nTotal instances in data/: $nFiles")

# ═════════════════════════════════════════════════════════════════════════════
#  PART 4 — Batch Solve All Instances (CPLEX + Heuristic)
# ═════════════════════════════════════════════════════════════════════════════
println("\n\n" * "=" ^ 70)
println("  PART 4 — Batch Solve (CPLEX + Heuristic)")
println("=" ^ 70)

solveDataSet()

# ═════════════════════════════════════════════════════════════════════════════
#  PART 5 — Generate Results Report
# ═════════════════════════════════════════════════════════════════════════════
println("\n\n" * "=" ^ 70)
println("  PART 5 — Results Report")
println("=" ^ 70)

resultsArray("../res/array.tex")
println("LaTeX results table written to res/array.tex")

try
    performanceDiagram("../res/performance.pdf")
catch e
    println("Could not generate performance diagram: ", e)
end

# ═════════════════════════════════════════════════════════════════════════════
#  Summary
# ═════════════════════════════════════════════════════════════════════════════
println("\n\n" * "=" ^ 70)
println("  ALL DONE")
println("=" ^ 70)

function countSolved(folder)
    !isdir(folder) && return 0
    return count(
        f -> occursin("isOptimal = true", read(joinpath(folder, f), String)),
        filter(x -> occursin(".txt", x), readdir(folder))
    )
end

nCplex = countSolved("../res/cplex")
nHeur  = countSolved("../res/heuristique")

println("  Instances in data/:       $nFiles")
println("  Solved by CPLEX:          $nCplex / $nFiles")
println("  Solved by Heuristic:      $nHeur / $nFiles")
println("  Results table:            res/array.tex")
