# Galaxies Solver

ILP solver for the **Galaxies** logic puzzle (project difficulty: 9/10).

## Game Rules

Partition a rectangular grid into connected regions ("galaxies") such that:

1. **One dot per galaxy** — each region contains exactly one dot.
2. **180° rotational symmetry** — each galaxy is symmetric about its dot.
3. **Connected region** — every galaxy forms a single connected group of cells.
4. **Full partition** — every cell belongs to exactly one galaxy.

Dots can sit at cell centres, edge midpoints, or grid corners (see *Instance Format* below).

## Mathematical Formulation

**Variable**

| Symbol | Domain | Meaning |
|--------|--------|---------|
| `x[i,j,k]` | `{0,1}` | cell `(i,j)` belongs to galaxy `k` |

**Constraints**

| ID | Name | Formula |
|----|------|---------|
| R1 | Partition | `Σ_k x[i,j,k] = 1`  ∀ `(i,j)` |
| R2 | Dot anchor | `x[c,k] = 1`  for every cell `c` touched by dot `k` |
| R3 | Symmetry | `x[i,j,k] = x[sym_k(i,j), k]`  ∀ `(i,j)`, ∀ `k` |
| R4 | Connectivity | lazy separator cuts (see below) |

**Objective:** pure feasibility — any solution satisfying all constraints is valid.

## Connectivity: Callback vs. Flow Variables

R4 (connectivity) cannot be expressed with a polynomial number of upfront
linear constraints. Two classical approaches exist:

### Option A — Flow variables (used in `range/`)
Introduce flow variables `f[c→c', k]` representing a commodity flowing from the
dot of galaxy `k` to every other cell in that galaxy. Flow conservation at each
cell forces reachability. This adds O(n·m·K) variables and constraints to the
model upfront.

### Option B — Lazy-constraint callback ✓ *(used here)*
R1–R3 are encoded upfront. Each time CPLEX finds an integer-feasible candidate,
a callback runs a BFS from each galaxy's dot anchor. If a galaxy has a
disconnected component `S`, the **separator cut** is added as a lazy constraint:

```
Σ_{c ∈ S} x[c,k]  +  Σ_{c ∈ N(S)} (1 − x[c,k])  ≥  1
```

This forces either `S` to break up or a bridge cell from `N(S)` to join
galaxy `k`, reconnecting the component. CPLEX discards the candidate and
continues branch-and-bound with the new cut.

**Why callbacks here?**  
The Galaxies puzzle has many galaxies (large `K`), making flow-variable models
very expensive. Callbacks keep the model compact and only add cuts where needed.

## Instance File Format

Dot positions use **double-grid coordinates**: cell `(i,j)` has its centre at
`(2i−1, 2j−1)`, giving coordinates in `1..2n−1` × `1..2m−1`.

| `dr` parity | `dc` parity | Dot sits at | Cells touched |
|-------------|-------------|-------------|---------------|
| odd  | odd  | cell centre | 1 |
| even | odd  | horizontal edge | 2 |
| odd  | even | vertical edge   | 2 |
| even | even | corner          | 4 |

**File layout:**
```
n_rows n_cols
dr1 dc1
dr2 dc2
...
```
Lines starting with `#` are ignored.

## Directory Structure

```
galaxies/
├── data/             ← instance files (.txt)
├── res/
│   ├── cplex/        ← CPLEX results (solveTime, isOptimal)
│   └── heuristique/  ← heuristic results
└── src/
    ├── io.jl         ← file I/O, grid/solution display, LaTeX table
    ├── generation.jl ← (TODO) random instance generator
    └── resolution.jl ← heuristic + ILP model + callback
```

## Usage

From the `galaxies/` directory:

```julia
julia test_galaxies.jl          # run all test instances
```

Or interactively from the Julia REPL:

```julia
cd("galaxies")
include("src/resolution.jl")

n, m, dots = readInputFile("data/instance_4x4_1.txt")
displayGrid(n, m, dots)

is_opt, t, assign = cplexSolve(n, m, dots)
is_opt && displaySolution(n, m, dots, assign)

solveDataSet()                  # solve all instances, write results
resultsArray("res/array.tex")   # generate LaTeX comparison table
```
