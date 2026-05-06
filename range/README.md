# Range Solver

This directory contains the Integer Linear Programming (ILP) solver for the **Range** logic puzzle (Difficulty: 5)

## Game Rules

You have a grid of squares; some squares contain numbers. Your job is to colour some of the squares black, such that:

1. **No numbered square is black** — squares with numbers must remain white.
2. **No two black squares are adjacent** — horizontally or vertically.
3. **White connectivity** — all white squares must form a single connected component (no isolated white regions).
4. **Visibility constraint** — each number $x$ indicates the total count of white squares visible from that cell, looking in all four cardinal directions (up, down, left, right) until hitting a wall or a black square. The cell itself is included in the count.

> As a consequence of rules 3 and 4, no square can ever contain the number 1 (it would need all 4 neighbours to be black, isolating itself).

---

## Mathematical Formulation

This problem is modeled as a binary linear program. Two solver strategies are implemented, differing only in how they enforce **white connectivity** (Rule 3). Rules 1, 2 and 4 are identical in both.

### Sets and Indices

- Grid of size $n \times m$.
- $\mathcal{C} = \{(i,j) \mid \text{cell } (i,j) \text{ contains a clue number}\}$, with clue value $v_{i,j}$
- $\mathcal{N}(i,j)$ = set of 4-adjacent neighbours (up, down, left, right) of cell $(i,j)$
- $s = (s_r, s_c)$ = any fixed cell in $\mathcal{C}$, chosen as the connectivity reference (it is guaranteed white by Rule 1)

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

A cell at distance $d$ is visible if and only if **all** cells between it and the clue are white.

### Objective Function

This is a feasibility problem — we use a constant objective:

$$\min\ 0$$

### Shared Constraints (both solvers)

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

---

## Connectivity Strategy 1 — Single-Commodity Network Flow

> Implemented in `resolution.jl` → `cplexSolve`

**Additional variables:**

$$f_{(i,j) \to (i',j')} \geq 0 \quad \forall\, (i',j') \in \mathcal{N}(i,j)$$

Directed flow on each edge of the grid (both directions).

**Flow constraints:**

**(a) Flow conservation at the source $s$:**

$$\sum_{(i',j') \in \mathcal{N}(s)} f_{s \to (i',j')} - \sum_{(i',j') \in \mathcal{N}(s)} f_{(i',j') \to s} = \sum_{\substack{(i,j) \neq s}} (1 - b_{i,j})$$

The source produces one unit of flow for every other white cell.

**(b) Flow conservation at every other cell $(i,j) \neq s$:**

$$\sum_{(i',j') \in \mathcal{N}(i,j)} f_{(i',j') \to (i,j)} - \sum_{(i',j') \in \mathcal{N}(i,j)} f_{(i,j) \to (i',j')} = 1 - b_{i,j}$$

White cells consume 1 unit; black cells consume 0 (no flow passes through them).

**(c) Flow capacity — flow only through white cells:**

$$f_{(i,j) \to (i',j')} \leq n \cdot m \cdot (1 - b_{i,j})$$

$$f_{(i,j) \to (i',j')} \leq n \cdot m \cdot (1 - b_{i',j'})$$

These ensure no flow enters or leaves a black cell. The big-M constant $n \cdot m$ is an upper bound on the total number of white cells.

**Complexity:** $O(nm)$ additional continuous flow variables; $O(nm)$ additional constraints. Big-M coefficients weaken the LP relaxation.

---

## Connectivity Strategy 2 — Lazy Constraint Callbacks (Separator Cuts)

> Implemented in `resolutionWithCallback.jl` → `cplexSolveWithCallback`

Instead of adding flow variables upfront, connectivity is enforced **dynamically**: every time CPLEX finds an integer-feasible candidate $\hat{b}$, a callback runs a BFS from the source $s$ through white cells. If a disconnected white component is found, a **separator cut** is generated and added as a lazy constraint.

**No additional variables** are introduced in the model.

### Separator Inequality

Let $\hat{b}$ be the current integer candidate. A connected component $S$ of white cells in $\hat{b}$ is **disconnected** if $s \notin S$. Define its outer neighbourhood:

$$N(S) = \{(i,j) \notin S \mid \exists\, (i',j') \in S : (i,j) \in \mathcal{N}(i',j')\}$$

In the candidate $\hat{b}$, every cell in $S$ is white ($\hat{b} = 0$) and every cell in $N(S)$ is black ($\hat{b} = 1$) — otherwise $S$ would be reachable from $s$. The following inequality forbids precisely this pattern:

$$\sum_{(i,j) \in S} b_{i,j} \;+\; \sum_{(i,j) \in N(S)} (1 - b_{i,j}) \;\geq\; 1$$

**Interpretation:** the next feasible solution must either turn at least one cell of $S$ black (destroying the isolated component) or turn at least one cell of $N(S)$ white (opening a passage to the rest of the grid). Both outcomes restore connectivity.

**Validity:** the inequality is always satisfiable. If $S$ becomes entirely black, the left-hand side's first sum equals $|S| \geq 1$. If any neighbour becomes white, the second sum contributes at least 1. In all valid connected solutions, the inequality holds trivially.

### Callback Algorithm

```
On each integer candidate b̂:
  1. BFS from s through white cells  →  reachable set A
  2. For each white cell w ∉ A not yet processed:
       a. BFS to enumerate its full component S
       b. Compute N(S)
       c. Submit the separator cut for S
  3. If no cut submitted → candidate is connected → accept
```

All disconnected components are cut in a **single callback invocation**, minimising round-trips to the solver.

**Complexity:** no additional variables; cuts are added on demand. The LP relaxation is tighter than the flow formulation (no big-M). In the worst case, exponentially many cuts may be needed, but in practice very few are required for Range instances.

---

## Comparison of Connectivity Strategies

| Property | Flow (Strategy 1) | Callbacks (Strategy 2) |
|---|---|---|
| Additional variables | $O(nm)$ continuous | None |
| Constraints added upfront | $O(nm)$ | None |
| Constraints added dynamically | None | One per disconnected component found |
| Big-M coefficients | Yes ($n \cdot m$) | No |
| LP relaxation quality | Weaker | Stronger |
| Implementation complexity | Low | Medium |
| Best suited for | Small grids | Medium/large grids |

---

### Complexity Note

Both models share $O(nm)$ primary binary variables and $O(|\mathcal{C}| \cdot (n+m))$ visibility variables. The number of shared constraints is $O(|\mathcal{C}| \cdot (n+m)^2 + nm)$. For moderate grid sizes (up to ~20×20), both strategies are tractable for CPLEX.

---

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

---

## Directory Structure

```
range/
├── data/                    # Grid instances (.txt files)
├── res/
│   ├── cplex/               # Results from the flow-based solver
│   ├── cplex_callback/      # Results from the callback-based solver
│   └── heuristique/         # Results from the heuristic solver
└── src/
    ├── io.jl                # Read/write/display instances, performance reports
    ├── generation.jl        # Random instance generation
    ├── resolution.jl        # Flow-based ILP + heuristic solver
    └── resolutionWithCallback.jl  # Callback-based ILP solver
```

---

## Usage

From the Julia REPL, navigate to the `range/src/` directory.

### Flow-based solver (Strategy 1)

```julia
include("resolution.jl")

# Solve a single instance
grid, _ = readInputFile("../data/instanceTest.txt")
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

### Callback-based solver (Strategy 2)

```julia
include("resolutionWithCallback.jl")

# Solve a single instance
grid, _ = readInputFile("../data/instanceTest.txt")
displayGrid(grid)

isOptimal, solveTime, solution = cplexSolveWithCallback(grid)
if isOptimal
    displaySolution(solution)
end

# Solve all instances in data/ (writes to ../res/cplex_callback/)
solveDataSetWithCallback()
```

### Comparing both strategies

```julia
include("resolutionWithCallback.jl")   # also loads resolution.jl

grid, _ = readInputFile("../data/instanceTest.txt")

isOpt1, t1, sol1 = cplexSolve(grid)
isOpt2, t2, sol2 = cplexSolveWithCallback(grid)

println("Flow     — optimal: $isOpt1  time: $(round(t1, sigdigits=3))s")
println("Callback — optimal: $isOpt2  time: $(round(t2, sigdigits=3))s")
```