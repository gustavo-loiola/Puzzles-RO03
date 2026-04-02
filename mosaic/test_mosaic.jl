# Change to the src directory since all paths inside the scripts 
# (like "../data/" and "../res/") are relative to the src/ directory
cd(joinpath(@__DIR__, "src"))

include("src/resolution.jl")

println("--- Solving Single Instance ---")
# Solve a single instance
grid, expected_solution = readInputFile("../data/mosaic_5x5_1.txt")
displayGrid(grid)

isOptimal, solveTime, solution = cplexSolve(grid)
if isOptimal
    println("Solved in $(round(solveTime, digits=3))s")
    displaySolution(solution)
end

println("\n--- Solving All Instances in data/ ---")
# Solve all instances in data/
solveDataSet()

println("\n--- Generating Results Table ---")
# Generate results table
resultsArray("../res/array.tex")