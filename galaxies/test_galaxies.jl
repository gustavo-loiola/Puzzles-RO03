# test_galaxies.jl
# Smoke-test for the Galaxies solver.
# Run from the galaxies/ directory:
#   julia test_galaxies.jl

cd(@__DIR__)
include("src/resolution.jl")

function run_instance(label, path; time_limit=120.0)
    println("\n── $label")
    n, m, dots = readInputFile(path)
    displayGrid(n, m, dots)

    println("  Heuristic…")
    h_ok, h_assign = heuristicSolve(n, m, dots)
    println("  Heuristic feasible: $h_ok")
    h_ok && displaySolution(n, m, dots, h_assign)

    println("  CPLEX…")
    is_opt, t, assign = cplexSolve(n, m, dots; time_limit)
    println("  CPLEX optimal: $is_opt  ($(round(t, sigdigits=4))s)")
    is_opt && displaySolution(n, m, dots, assign)
end

println("=" ^ 60)
println("GALAXIES SOLVER — TEST")
println("=" ^ 60)

run_instance("4×4 instance (3 galaxies)",  "data/instance_4x4_1.txt"; time_limit=60.0)
run_instance("5×5 instance (4 galaxies)",  "data/instance_5x5_1.txt"; time_limit=120.0)
run_instance("7×7 instance",               "data/instance_7x7_1.txt"; time_limit=120.0)
