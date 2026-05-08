# =============================================================================
#  Galaxies Puzzle — Full Runner Script
#  Run from the galaxies/ directory:  julia run_full_galaxies.jl
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

# Check if data directory is empty, if so, generate dataset
dataFiles = filter(x -> occursin(".txt", x), readdir("../data/"))
if isempty(dataFiles)
    println("\nNo instances found. Generating dataset...")
    generateDataSet()
end

for file in sort(filter(x -> occursin(".txt", x), readdir("../data/")))
    println("\n── Instance: $file ──")
    grid, dots, _ = readInputFile("../data/" * file)
    n, m = grid
    println("  Grid size: $(n) rows × $(m) columns, $(length(dots)) galaxies")
    displayGrid(grid, dots)

    # Callback-based solver
    isOpt, t, sol = cplexSolve(grid, dots)
    println("  [Callback CPLEX] Optimal: $isOpt | Time: $(round(t, digits=4))s")

    # Show solution
    if isOpt
        displaySolution(grid, dots, sol)
        valid = verifySolution(grid, dots, sol)
        println("  Verification: ", valid ? "✓ VALID" : "✗ INVALID")
    else
        println("  ✗ No feasible solution found")
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
    grid, dots, _ = readInputFile("../data/" * file)

    startTime = time()
    isSolved = false
    sol = nothing
    attempts = 0

    while !isSolved && (time() - startTime) < 10.0
        isSolved, sol = heuristicSolve(grid, dots)
        attempts += 1
    end
    elapsed = time() - startTime

    println("  Solved: $isSolved | Attempts: $attempts | Time: $(round(elapsed, digits=4))s")
    if isSolved && sol !== nothing
        displaySolution(grid, dots, sol)
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
#  PART 4 — Batch Solve All Instances (Callback CPLEX + Heuristic)
# ═══════════════════════════════════════════════════════════════════════════════
println("\n\n" * "=" ^ 70)
println("  PART 4 — Batch Solve All Instances")
println("=" ^ 70)

println("\nSolving dataset with both methods...")
solveDataSet()

# ═══════════════════════════════════════════════════════════════════════════════
#  PART 5 — Output Final Tables & Summary
# ═══════════════════════════════════════════════════════════════════════════════
println("\n\n" * "=" ^ 70)
println("  PART 5 — Results Summary")
println("=" ^ 70)

resultsArray("../res/array.tex")

println("\n── Final solve counts ──")
for method in ["cplex", "heuristique"]
    resDir = "../res/$method/"
    if !isdir(resDir)
        continue
    end
    files = filter(x -> occursin(".txt", x), readdir(resDir))
    solved = 0
    for f in files
        for line in readlines(joinpath(resDir, f))
            if occursin("isOptimal = true", line)
                solved += 1
                break
            end
        end
    end
    println("  $method : $solved / $nFiles optimal")
end

println("\n" * "=" ^ 70)
println("  ALL COMPLETED SUCCESSFULLY")
println("=" ^ 70)
