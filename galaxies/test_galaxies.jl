# Galaxies Puzzle — Test Script
# Run from the galaxies/ directory: julia test_galaxies.jl

# --- Setup ---
include(joinpath(@__DIR__, "src", "resolution.jl"))
cd(joinpath(@__DIR__, "src"))

println("=" ^ 70)
println("  Galaxies Solver — Testing")
println("=" ^ 70)

# ── Generate dataset if empty ────────────────────────────────────────────────
dataFiles = filter(x -> occursin(".txt", x), readdir("../data/"))
if isempty(dataFiles)
    println("\nNo instances found. Generating dataset...")
    generateDataSet()
    dataFiles = sort(filter(x -> occursin(".txt", x), readdir("../data/")))
end

# ── Solve each instance ──────────────────────────────────────────────────────
for file in sort(dataFiles)
    println("\n── Instance: $file ──")
    grid, dots, expected = readInputFile("../data/" * file)
    n, m = grid
    println("  Grid size: $(n) rows × $(m) columns, $(length(dots)) galaxies")
    displayGrid(grid, dots)

    println("  Solving with CPLEX...")
    isOpt, t, sol = cplexSolve(grid, dots)
    println("  Optimal: $isOpt | Time: $(round(t, digits=4))s")

    if isOpt
        displaySolution(grid, dots, sol)
        valid = verifySolution(grid, dots, sol)
        println("  Verification: ", valid ? "✓ VALID" : "✗ INVALID")
    else
        println("  ✗ No feasible solution found")
    end
end

println("\n" * "=" ^ 70)
println("  ALL TESTS COMPLETE")
println("=" ^ 70)