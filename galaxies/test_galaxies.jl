# test_galaxies.jl
# Run from the galaxies/ directory:  julia test_galaxies.jl

cd(@__DIR__)
include("src/resolution.jl")

function run_instance(label, path; time_limit=120.0)
    println("\n── $label")
    n, m, dots = readInputFile(path)
    displayGrid(n, m, dots)

    is_opt, t, assign, h_assign, _ = cplexSolve(n, m, dots; time_limit)

    displayPartialSolution(n, m, dots, h_assign)

    println("  CPLEX optimal: $is_opt  ($(round(t, sigdigits=4))s)")
    is_opt && displaySolution(n, m, dots, assign)
end

println("=" ^ 60)
println("GALAXIES SOLVER — TEST")
println("=" ^ 60)

run_instance("4×4 instance",   "data/instance_4x4_1.txt";  time_limit=60.0)
run_instance("5×5 instance",   "data/instance_5x5_1.txt";  time_limit=120.0)
run_instance("7×7 instance",   "data/instance_7x7_1.txt";  time_limit=120.0)
run_instance("10×10 instance", "data/instance_10x10_1.txt"; time_limit=300.0)
run_instance("15×15 instance", "data/instance_15x15_1.txt"; time_limit=480.0)
