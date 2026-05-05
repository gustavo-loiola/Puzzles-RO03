# Range Solver

This directory contains the Integer Linear Programming (ILP) solver for the **Range** logic puzzle (Difficulty: 5)

## Game Rules

You have a grid of squares; some squares contain numbers. Your job is to colour some of the squares black, such that:

1. **No numbered square is black** — squares with numbers must remain white.
2. **No two black squares are adjacent** — horizontally or vertically.
3. **White connectivity** — all white squares must form a single connected component (no isolated white regions).
4. **Visibility constraint** — each number $x$ indicates the total count of white squares visible from that cell, looking in all four cardinal directions (up, down, left, right) until hitting a wall or a black square. The cell itself is included in the count.


> As a consequence of rules 3 and 4, no square can ever contain the number 1 (it would need all 4 neighbours to be black, isolating itself).

## Mathematical Formulation

This problem is modeled as a binary linear program with auxiliary continuous flow variables for connectivity.

### Sets and Indices

- Grid of size $n \times m$.
- $\mathcal{C} = \{(i,j) \mid \text{cell } (i,j) \text{ contains a clue number}\}$, with clue value $v_{i,j}$
- $\mathcal{N}(i,j)$ = set of 4-adjacent neighbours (up, down, left, right) of cell $(i,j)$
- $s = (s_r, s_c)$ = any fixed cell in $\mathcal{C}$, chosen as the flow source (it is guaranteed to be white by Rule 1)

### Decision Variables

**Primary variable:**

$$b_{i,j} \in \{0, 1\} \quad \forall\, (i,j) \in [1,n] \times [1,m]$$

where $b_{i,j} = 1$ if the cell is **black**, $0$ if **white**.

**Visibility variables** (one per clue cell, per direction, per distance):

For each clue cell $(r,c) \in \mathcal{C}$, define binary variables capturing whether each cell along each ray is visible:

- $\text{vis}^R_{r,c,d} \in \{0,1\}$ — cell $(r, c+d)$ is visible looking **right**, for $d = 1, \ldots, m - c$
- $\text{vis}^L_{r,c,d} \in \{0,1\}$ — cell $(r, c-d)$ is visible looking **left**, for $d = 1, \ldots, c - 1$
- $\text{vis}^D_{r,c,d} \in \{0,1\}$ — cell $(r+d, c)$ is visible looking **down**, for $d = 1, \ldots, n - r$
- $\text{vis}^U_{r,c,d} \in \{0,1\}$ — cell $(r-d, c)$ is visible looking **up**, for $d = 1, \ldots, r - 1$

A cell at distance $d$ is visible iff **all** cells between it and the clue are white.

**Flow variables** (for white connectivity):

$$f_{(i,j) \to (i',j')} \geq 0 \quad \forall\, (i',j') \in \mathcal{N}(i,j)$$

Directed flow on each edge of the grid (both directions).

### Objective Function

This is a feasibility problem — we use a constant objective:

$$\min\ 0$$

### Constraints

**1. Numbered cells are white:**

$$b_{i,j} = 0 \qquad \forall\, (i,j) \in \mathcal{C}$$

**2. No two adjacent black cells:**

$$b_{i,j} + b_{i,j+1} \leq 1 \qquad \forall\, i \in [1,n],\; j \in [1, m-1]$$

$$b_{i,j} + b_{i+1,j} \leq 1 \qquad \forall\, i \in [1, n-1],\; j \in [1,m]$$

**3. Visibility constraints:**

For each clue cell $(r,c) \in \mathcal{C}$ with value $v_{r,c}$:

**(a) Line-of-sight definition** — a cell at distance $d$ is visible iff every cell in between is white. Example for the **right** direction ($d = 1, \ldots, m - c$):

$$\text{vis}^R_{r,c,d} \leq 1 - b_{r,\, c+k} \qquad \forall\, k = 1, \ldots, d$$

$$\text{vis}^R_{r,c,d} \geq 1 - \sum_{k=1}^{d} b_{r,\, c+k}$$

The first set of constraints ensures that if *any* cell on the ray is black, visibility is 0. The second constraint ensures that if *all* cells are white, visibility is 1. Analogous constraints hold for left ($b_{r,c-k}$), down ($b_{r+k,c}$), and up ($b_{r-k,c}$).

**(b) Total visibility equals clue value:**

$$1 + \sum_{d=1}^{m-c} \text{vis}^R_{r,c,d} + \sum_{d=1}^{c-1} \text{vis}^L_{r,c,d} + \sum_{d=1}^{n-r} \text{vis}^D_{r,c,d} + \sum_{d=1}^{r-1} \text{vis}^U_{r,c,d} = v_{r,c}$$

The leading $1$ accounts for the cell seeing itself.

**4. White connectivity (single-commodity network flow):**

We route flow from the source $s$ to every other white cell. Each white cell (other than $s$) must receive exactly 1 unit.

**(a) Flow conservation at the source $s$:**

$$\sum_{(i',j') \in \mathcal{N}(s)} f_{s \to (i',j')} - \sum_{(i',j') \in \mathcal{N}(s)} f_{(i',j') \to s} = \sum_{\substack{(i,j) \neq s}} (1 - b_{i,j})$$

The source produces one unit of flow for every other white cell.

**(b) Flow conservation at every other cell $(i,j) \neq s$:**

$$\sum_{(i',j') \in \mathcal{N}(i,j)} f_{(i',j') \to (i,j)} - \sum_{(i',j') \in \mathcal{N}(i,j)} f_{(i,j) \to (i',j')} = 1 - b_{i,j}$$

White cells consume 1 unit; black cells consume 0 (no flow passes through them).

**(c) Flow capacity — flow only through white cells:**

$$f_{(i,j) \to (i',j')} \leq n \cdot m \cdot (1 - b_{i,j})$$

$$f_{(i,j) \to (i',j')} \leq n \cdot m \cdot (1 - b_{i',j'})$$

These ensure no flow enters or leaves a black cell.

### Complexity Note

The model has $O(nm)$ primary variables, $O(|\mathcal{C}| \cdot (n+m))$ visibility variables, and $O(nm)$ flow variables. The number of constraints is $O(|\mathcal{C}| \cdot (n+m)^2 + nm)$. For moderate grid sizes (up to ~20×20), this is tractable for CPLEX.

## Instance File Format

```
<m_cols> <n_rows>
# grid
. .  .  .  . .  6 . .      (. = no clue, numbers = clue values)
. 12 . 10  . 12 . . .
. .  5  .  6 .  . . 4
7 .  .  .  9 . 11 . .
. .  .  6  . 6  . 5 .
. .  4  .  . .  . . .
# solution                   (optional section for verification)
0 1 0 0 0 1 0 1 0           (0 = white, 1 = black)
0 0 0 0 0 0 0 0 0
...
```

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