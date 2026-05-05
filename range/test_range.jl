# Range Puzzle — Test Script
# Run from the range/ directory: julia test_range.jl

# --- Setup ---
include(joinpath(@__DIR__, "src", "resolution.jl"))
cd(joinpath(@__DIR__, "src"))

println("=" ^ 70)
println("  Range Solver — Testing on provided instances")
println("=" ^ 70)

for file in sort(filter(x -> occursin(".txt", x), readdir("../data/")))
    println("\n── Instance: $file ──")
    grid, expected = readInputFile("../data/" * file)
    n, m = size(grid)
    println("  Grid size: $(n) rows × $(m) columns")
    displayGrid(grid)

    println("  Solving with CPLEX...")
    isOpt, t, sol = cplexSolve(grid)
    println("  Optimal: $isOpt | Time: $(round(t, digits=4))s")

    if isOpt
        displaySolution(sol; grid=grid)

        # Verify solution
        valid = verifySolution(grid, sol)
        println("  Verification: ", valid ? "✓ VALID" : "✗ INVALID")

        # Compare to expected if available
        if all(expected .!= -1)
            if sol == expected
                println("  ✓ Solution matches expected answer")
            else
                println("  ✗ MISMATCH with expected answer!")
                println("  Expected:")
                displaySolution(expected; grid=grid)
            end
        end
    else
        println("  ✗ No feasible solution found")
    end
end

println("\n" * "=" ^ 70)
println("  ALL TESTS COMPLETE")
println("=" ^ 70)
