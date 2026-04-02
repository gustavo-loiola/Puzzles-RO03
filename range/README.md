# Range Solver

This directory contains the Integer Linear Programming (ILP) solver for the **Range** logic puzzle (Difficulty: 5).

## Game Rules

You have a grid of squares; some squares contain numbers. Your job is to colour some of the squares black, such that:

1. **No numbered square is black** — squares with numbers must remain white.
2. **No two black squares are adjacent** — horizontally or vertically.
3. **White connectivity** — all white squares must form a single connected component (no isolated white regions).
4. **Visibility constraint** — each number $x$ indicates the total count of white squares visible from that cell, looking in all four cardinal directions (up, down, left, right) until hitting a wall or a black square. The cell itself is included in the count.

> [!NOTE]
> As a consequence of rules 3 and 4, no square can ever contain the number 1 (it would need all 4 neighbours to be black, isolating itself).

## Mathematical Formulation

*TODO — to be completed.*

## Instance File Format

*TODO — to be completed.*

## Directory Structure

* `data/` — Grid instances as `.txt` files.
* `res/cplex/` — CPLEX solving results (`solveTime` and `isOptimal`).
* `src/` — Julia source code:
    * `io.jl` — Read instances, display grid/solution, generate performance reports.
    * `generation.jl` — Generate random Range instances.
    * `resolution.jl` — JuMP/CPLEX model and heuristic solver.

## Usage

From the Julia REPL, navigate to the `range/` directory:

```julia
cd("src")
include("resolution.jl")

# Solve a single instance
grid = readInputFile("../data/instanceTest.txt")
displayGrid(grid)

isOptimal, solveTime, solution = cplexSolve(grid)
if isOptimal
    displaySolution(solution)
end

# Solve all instances in data/
solveDataSet()

# Generate results table
resultsArray("../res/array.tex")
```