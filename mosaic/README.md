# Mosaic Solver

This directory contains the Integer Linear Programming (ILP) solver for the **Mosaic** logic puzzle.

## Game Rules

You are given a grid of squares, which you must colour either black or white.

Some squares contain clue numbers. Each clue tells you the number of black squares in the 3×3 region surrounding the clue — including the clue square itself.

*Note: This game is variously known as ArtMosaico, Fill-a-Pix, Majipiku, Voisimage, etc.*

## Mathematical Formulation

This problem is modeled as a binary linear program.

**Decision Variables:**
Let $x_{i,j} \in \{0, 1\}$ where:
* $x_{i,j} = 1$ if the square at row $i$, column $j$ is **black**.
* $x_{i,j} = 0$ if the square at row $i$, column $j$ is **white**.

**Objective Function:**
Mosaic is a pure feasibility problem. We use a constant objective:
$$\min\ 0$$

**Constraints:**
For every square $(i,j)$ that contains a clue $v_{i,j}$, the sum of the black squares in its neighbourhood must equal $v_{i,j}$:

$$\sum_{k = \max(1, i-1)}^{\min(n, i+1)} \sum_{l = \max(1, j-1)}^{\min(m, j+1)} x_{k,l} = v_{i,j}$$

## Instance File Format

```
<n_rows> <n_cols>
# grid
. 5 6 . 4      (. = no clue, numbers = clue values)
. . . . .
4 5 . 5 .
. . 4 4 .
. 0 . . .
# solution       (optional section for verification)
0 1 1 1 1       (0 = white, 1 = black)
1 1 1 1 1
...
```

## Directory Structure

* `data/` — Grid instances as `.txt` files.
* `res/cplex/` — CPLEX solving results (`solveTime` and `isOptimal`).
* `src/` — Julia source code:
    * `io.jl` — Read instances, display grid/solution, generate performance reports.
    * `generation.jl` — Generate random Mosaic instances.
    * `resolution.jl` — JuMP/CPLEX model and heuristic solver.

## Usage

From the Julia REPL, navigate to the `mosaic/` directory:

```julia
cd("src")
include("resolution.jl")

# Solve a single instance
grid, expected_solution = readInputFile("../data/mosaic_5x5_1.txt")
displayGrid(grid)

isOptimal, solveTime, solution = cplexSolve(grid)
if isOptimal
    println("Solved in $(round(solveTime, digits=3))s")
    displaySolution(solution)
end

# Solve all instances in data/
solveDataSet()

# Generate results table
resultsArray("../res/array.tex")
```