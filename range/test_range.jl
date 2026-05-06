# Range Puzzle — Test Script
# Run from the range/ directory: julia test_range.jl

# --- Setup ---
include(joinpath(@__DIR__, "src", "resolutionWithCallback.jl"))
cd(joinpath(@__DIR__, "src"))

println("=" ^ 70)
println("  Range Solver — Comparing Flow vs Callback on provided instances")
println("=" ^ 70)

for file in sort(filter(x -> occursin(".txt", x), readdir("../data/")))
    println("\n── Instance: $file ──")
    grid, expected = readInputFile("../data/" * file)
    n, m = size(grid)
    println("  Grid size: $(n) rows × $(m) columns")
    displayGrid(grid)

    # ── Flow-based CPLEX ──
    println("  Solving with CPLEX (flow)...")
    isOpt1, t1, sol1 = cplexSolve(grid)
    println("  Optimal: $isOpt1 | Time: $(round(t1, digits=4))s")
    if isOpt1
        valid1 = verifySolution(grid, sol1)
        println("  Verification: ", valid1 ? "✓ VALID" : "✗ INVALID")
    end

    # ── Callback-based CPLEX ──
    println("  Solving with CPLEX (callback)...")
    isOpt2, t2, sol2 = cplexSolveWithCallback(grid)
    println("  Optimal: $isOpt2 | Time: $(round(t2, digits=4))s")
    if isOpt2
        valid2 = verifySolution(grid, sol2)
        println("  Verification: ", valid2 ? "✓ VALID" : "✗ INVALID")
    end

    # ── Speedup ──
    if isOpt1 && isOpt2 && t1 > 0 && t2 > 0
        ratio = t1 / t2
        if ratio > 1
            println("  → Callback is $(round(ratio, digits=2))× faster")
        else
            println("  → Flow is $(round(1/ratio, digits=2))× faster")
        end
    end

    # ── Display solution & compare to expected ──
    sol = isOpt2 ? sol2 : sol1
    if isOpt2 || isOpt1
        displaySolution(sol; grid=grid)
        if all(expected .!= -1)
            println("  vs. expected: ", sol == expected ? "✓ MATCH" : "✗ MISMATCH")
        end
    else
        println("  ✗ No feasible solution found by either solver")
    end
end

println("\n" * "=" ^ 70)
println("  ALL TESTS COMPLETE")
println("=" ^ 70)
