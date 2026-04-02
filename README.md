# Logic Puzzles Optimization Solver

This repository contains mathematical models and solvers for logic puzzles from [Simon Tatham's Portable Puzzle Collection](https://www.chiark.greenend.org.uk/~sgtatham/puzzles/). The project is implemented in **Julia** using the **JuMP.jl** modeling language and the **CPLEX** solver, applying Integer Linear Programming (ILP) and Graph Theory concepts.

## Project Overview

The primary objective is to modelize and solve complex logic puzzles. The project includes solvers for the following puzzles:

* **Mosaic** (Difficulty: 1) — Localized constraint satisfaction: colour cells black/white so that each clue equals the count of black cells in its 3×3 neighbourhood.
* **Range** (Difficulty: 5) — Visibility and connectivity: place black cells so that each number sees exactly that many white cells, with all white cells connected.
* **Galaxies** (Difficulty: 9) — Central symmetry and region partitioning: divide the grid into 180°-symmetric regions around given dots, using CPLEX Callbacks (Lazy Constraints).

A complete **Sudoku** solver is also provided as a reference implementation by the course instructor.

## Repository Structure

```text
.
├── docs/               # Project documentation & LaTeX report
├── galaxies/           # Solver for the Galaxies puzzle
├── mosaic/             # Solver for the Mosaic puzzle
├── range/              # Solver for the Range puzzle
├── sudoku/             # Reference Sudoku solver (provided by instructor)
├── projet_sujet.md     # Full assignment specification
├── Projet_sujet.pdf    # Assignment specification (PDF)
└── README.md           # This file
```

Each puzzle directory follows a uniform structure:

```text
puzzle_name/
├── README.md           # Rules, mathematical formulation, usage
├── data/               # Input instances (.txt files)
├── res/                # Results output (cplex/, heuristic/)
└── src/
    ├── io.jl           # Read/write/display instances
    ├── generation.jl   # Random instance generation
    └── resolution.jl   # ILP model + heuristic solver
```

## Dependencies & Setup

1.  **Install Julia**: Download via [juliaup](https://github.com/JuliaLang/juliaup).
2.  **Install CPLEX**: Requires IBM ILOG CPLEX Optimization Studio.
3.  **Install Julia Packages**: Open the Julia REPL, press `]` to enter the package manager, and run:
    ```julia
    add JuMP
    add CPLEX
    add Plots
    ```

## Quick Start

Each puzzle can be solved by navigating to its `src/` directory and running Julia:

```julia
# Example: Solve a Mosaic instance
cd("mosaic/src")
include("resolution.jl")

grid, _ = readInputFile("../data/mosaic_5x5_1.txt")
displayGrid(grid)

isOptimal, solveTime, solution = cplexSolve(grid)
if isOptimal
    displaySolution(solution)
end
```

To solve all instances in a puzzle's `data/` folder:

```julia
include("resolution.jl")
solveDataSet()
```

## General Execution

Please refer to the specific `README.md` inside each puzzle's folder for detailed rules, mathematical formulations, and execution commands.