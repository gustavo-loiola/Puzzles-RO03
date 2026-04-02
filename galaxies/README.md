# Galaxies Solver

This directory contains the Integer Linear Programming (ILP) solver for the **Galaxies** logic puzzle (Difficulty: 9).

## Game Rules

You have a rectangular grid containing a number of dots (called *galaxies*). Your aim is to partition the grid into connected regions of squares such that:

1. **One dot per region** — each region contains exactly one dot.
2. **Rotational symmetry** — each region must be **180° rotationally symmetric** about its dot (the dot is the centre of symmetry).
3. **Connected regions** — every region must be a connected set of squares.
4. **Full partition** — every square belongs to exactly one region.

To enter a solution, you draw boundary lines along grid edges to separate squares belonging to different regions.

> [!IMPORTANT]
> This is the hardest puzzle in the project (difficulty 9). The symmetry + connectivity constraints are exponential in nature and **require CPLEX lazy-constraint callbacks** (see the Sudoku callback example in `sudoku/src/resolutionWithCallback.jl`).

### Why Callbacks Are Needed

The connectivity of each region cannot be fully encoded with a polynomial number of linear constraints. Instead, the approach is:
1. Encode the symmetry and assignment constraints directly in the ILP model.
2. Add a **callback** that checks each integer solution found by CPLEX for region connectivity.
3. If a region is disconnected, add a **lazy constraint** (subtour elimination cut) that rejects that solution, and let CPLEX continue.

## Mathematical Formulation

*TODO — to be completed.*

## Instance File Format

*TODO — to be completed.*

## Directory Structure

* `data/` — Grid instances as `.txt` files.
* `res/cplex/` — CPLEX solving results (`solveTime` and `isOptimal`).
* `src/` — Julia source code:
    * `io.jl` — Read instances, display grid/solution, generate performance reports.
    * `generation.jl` — Generate random Galaxies instances.
    * `resolution.jl` — JuMP/CPLEX model with callback and heuristic solver.

## Usage

From the Julia REPL, navigate to the `galaxies/` directory:

```julia
cd("src")
include("resolution.jl")

# Solve a single instance
grid, dots = readInputFile("../data/instanceTest.txt")
displayGrid(grid, dots)

isOptimal, solveTime, solution = cplexSolve(grid, dots)
if isOptimal
    displaySolution(solution)
end

# Solve all instances in data/
solveDataSet()

# Generate results table
resultsArray("../res/array.tex")
```
