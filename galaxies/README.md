# Galaxies Solver

This directory contains the Integer Linear Programming (ILP) solver for the **Galaxies** logic puzzle (Difficulty: 9).

## Game Rules

You have a rectangular grid containing a number of dots (called *galaxies*). Your aim is to partition the grid into connected regions of squares such that:

1. **One dot per region** — each region contains exactly one dot.
2. **Rotational symmetry** — each region must be **180° rotationally symmetric** about its dot (the dot is the centre of symmetry).
3. **Connected regions** — every region must be a connected set of squares.
4. **Full partition** — every square belongs to exactly one region.

To enter a solution, you draw boundary lines along grid edges to separate squares belonging to different regions.

> This is the hardest puzzle in the project (difficulty 9). The symmetry + connectivity constraints are exponential in nature and **require CPLEX lazy-constraint callbacks** (see the Sudoku callback example in `sudoku/src/resolutionWithCallback.jl`).

### Why Callbacks Are Needed

The connectivity of each region cannot be fully encoded with a polynomial number of linear constraints. Instead, the approach is:

1. Encode the symmetry and assignment constraints directly in the ILP model.
2. Add a **callback** that checks each integer solution found by CPLEX for region connectivity.
3. If a region is disconnected, add a **lazy constraint** (separator cut) that rejects that solution, and let CPLEX continue.

---

## Mathematical Formulation

### Preliminary: Dot Positions and the Doubled Coordinate System

A key subtlety of Galaxies is that dots can be placed at three types of positions in the grid:

- **Cell centre** — the dot lies at the centre of a single cell.
- **Edge midpoint** — the dot lies on the shared edge of two adjacent cells (horizontally or vertically adjacent).
- **Corner point** — the dot lies at the corner shared by four cells.

To handle all three cases uniformly and avoid fractions, we use a **doubled coordinate system**: every cell $(i, j)$ (with $i \in [1, n]$, $j \in [1, m]$) is mapped to its centre at position $(2i,\, 2j)$ in the doubled grid of size $2n \times 2m$. In this system, all dot positions have **integer** coordinates:

| Dot placement | Doubled coordinates $(p_k, q_k)$ |
|---|---|
| Centre of cell $(i, j)$ | $(2i,\; 2j)$ — both even |
| Midpoint of horizontal edge between $(i,j)$ and $(i{+}1,j)$ | $(2i{+}1,\; 2j)$ — odd row, even col |
| Midpoint of vertical edge between $(i,j)$ and $(i,j{+}1)$ | $(2i,\; 2j{+}1)$ — even row, odd col |
| Corner shared by $(i,j)$, $(i{+}1,j)$, $(i,j{+}1)$, $(i{+}1,j{+}1)$ | $(2i{+}1,\; 2j{+}1)$ — both odd |

The **180° symmetric image** of cell $(i,j)$ with respect to dot $k$ at doubled position $(p_k, q_k)$ is then:

$$\sigma_k(i, j) = \left(\frac{p_k - (2i - p_k)}{2},\; \frac{q_k - (2j - q_k)}{2}\right) = \left(p_k - i,\; q_k - j\right)$$

computed in original (non-doubled) coordinates. We say $\sigma_k(i,j)$ is **valid** if $p_k - i \in [1, n]$ and $q_k - j \in [1, m]$.

### Sets and Indices

- Grid of size $n \times m$; cells indexed by $(i, j) \in [1,n] \times [1,m]$.
- $K$ — number of galaxies; galaxies indexed $k = 1, \ldots, K$.
- $(p_k, q_k)$ — doubled-coordinate position of dot $k$.
- $D_k$ — **anchor cells** of galaxy $k$: the set of grid cells that the dot $k$ lies on or touches:

$$D_k = \left\{(i,j) \;\middle|\; \left\lfloor\frac{p_k + 1}{2}\right\rfloor \leq i \leq \left\lceil\frac{p_k}{2}\right\rceil,\; \left\lfloor\frac{q_k + 1}{2}\right\rfloor \leq j \leq \left\lceil\frac{q_k}{2}\right\rceil \right\}$$

In practice $|D_k| \in \{1, 2, 4\}$ according to the dot placement type above.

- $\mathcal{N}(i, j)$ — the set of 4-adjacent neighbours of cell $(i,j)$.

### Decision Variables

For each cell $(i,j)$ and each galaxy $k$:

$$x_{i,j,k} \in \{0, 1\} \qquad \forall\, (i,j) \in [1,n]\times[1,m],\; k \in [1,K]$$

where $x_{i,j,k} = 1$ if and only if cell $(i,j)$ belongs to galaxy $k$.

### Objective Function

This is a feasibility problem:

$$\min\; 0$$

### Constraints

#### 1. Full Partition — each cell belongs to exactly one galaxy

$$\sum_{k=1}^{K} x_{i,j,k} = 1 \qquad \forall\, (i,j) \in [1,n] \times [1,m]$$

#### 2. Anchor Cells — each dot belongs to its own galaxy

Every cell touched by dot $k$ must be assigned to galaxy $k$:

$$x_{i,j,k} = 1 \qquad \forall\, k \in [1,K],\; (i,j) \in D_k$$

Combined with constraint (1), this also ensures that **no other galaxy** claims an anchor cell of $k$:

$$x_{i,j,k'} = 0 \qquad \forall\, k' \neq k,\; (i,j) \in D_k$$

#### 3. Rotational Symmetry — 180° about the dot

For each galaxy $k$ and each cell $(i,j)$, the cell and its symmetric image must receive the same assignment:

$$x_{i,j,k} = x_{\,\sigma_k(i,j),\; k} \qquad \forall\, k,\; (i,j) \text{ s.t. } \sigma_k(i,j) \text{ is valid}$$

If the symmetric image of $(i,j)$ falls **outside** the grid, then cell $(i,j)$ cannot belong to galaxy $k$:

$$x_{i,j,k} = 0 \qquad \forall\, k,\; (i,j) \text{ s.t. } \sigma_k(i,j) \notin [1,n]\times[1,m]$$

> **Remark on self-symmetric cells.** When a dot is at a cell centre, that cell satisfies $\sigma_k(i,j) = (i,j)$, so the symmetry constraint is trivially $x_{i,j,k} = x_{i,j,k}$ and can be dropped. When a dot is at an edge midpoint, its two anchor cells are each other's symmetric image; constraint (2) already forces both to 1, so constraint (3) is automatically satisfied for that pair.

> **Implementation note.** Since constraint (3) is symmetric ($(i,j) \leftrightarrow \sigma_k(i,j)$), only one constraint per canonical pair is needed in practice to avoid redundancy. We choose the representative with the smaller lexicographic index.

#### 4. Connectivity — enforced via Lazy-Constraint Callback

Connectivity of each galaxy's region **is not encoded as a static constraint**. Instead, it is enforced dynamically through a CPLEX callback. The full callback algorithm is described in the next section.

---

## Connectivity Callback

### Trigger

The callback is invoked every time CPLEX finds an **integer-feasible** candidate solution $\hat{x}$. It verifies connectivity of each galaxy and, if violated, submits separator cuts as lazy constraints.

### Connectivity Check

For each galaxy $k$, define the candidate region:

$$R_k(\hat{x}) = \{(i,j) \mid \hat{x}_{i,j,k} = 1\}$$

Pick any anchor cell $(a, b) \in D_k$ as the **BFS source**. Run a BFS through $R_k(\hat{x})$, traversing only cells in $R_k(\hat{x})$ via 4-adjacency. Let $A_k \subseteq R_k(\hat{x})$ be the set of cells reachable from $(a,b)$.

- If $A_k = R_k(\hat{x})$: galaxy $k$ is connected — no cut needed.
- If $A_k \subsetneq R_k(\hat{x})$: galaxy $k$ has at least one disconnected component.

### Separator Cut

For each maximal connected component $S \subseteq R_k(\hat{x}) \setminus A_k$ (i.e. a white component that does not contain the dot), compute its outer neighbourhood:

$$N(S) = \{(i,j) \notin S \mid \exists\, (i',j') \in S : (i,j) \in \mathcal{N}(i',j')\}$$

In the candidate $\hat{x}$, every cell of $S$ satisfies $\hat{x}_{i,j,k} = 1$ and every cell of $N(S)$ satisfies $\hat{x}_{i,j,k} = 0$ — otherwise $S$ would be reachable. The following **separator inequality** forbids this configuration:

$$\sum_{(i,j)\,\in\, S} (1 - x_{i,j,k}) \;+\; \sum_{(i,j)\,\in\, N(S)} x_{i,j,k} \;\geq\; 1$$

**Interpretation:** either some cell of $S$ leaves galaxy $k$ (first sum $\geq 1$), or some boundary cell enters galaxy $k$ (second sum $\geq 1$), opening a passage between $S$ and the dot.

**Validity:** in any feasible connected solution, this inequality always holds. If all cells of $S$ remain in galaxy $k$ and none of $N(S)$ enters, the region remains disconnected — a contradiction.

### Symmetry-Strengthened Cut

Since constraint (3) forces $x_{i,j,k} = x_{\sigma_k(i,j),k}$ in every feasible solution, the symmetric image of $S$:

$$S' = \sigma_k(S) = \{\sigma_k(i,j) \mid (i,j) \in S\}$$

is also a disconnected component in $\hat{x}$ (unless $S' = A_k$, which would imply $S$ is reachable — a contradiction). Therefore a **second cut for $S'$** can be submitted in the same callback invocation at no extra BFS cost, strengthening the bound:

$$\sum_{(i,j)\,\in\, S'} (1 - x_{i,j,k}) \;+\; \sum_{(i,j)\,\in\, N(S')} x_{i,j,k} \;\geq\; 1$$

### Full Callback Algorithm

```
On each integer candidate x̂:
  For each galaxy k = 1, ..., K:
    R_k ← { (i,j) : x̂[i,j,k] = 1 }
    A_k ← BFS from any (a,b) ∈ D_k, restricted to R_k
    If A_k = R_k: continue   ▷ galaxy k is connected

    For each component S ⊆ R_k \ A_k:
      Compute N(S)
      Submit separator cut for S
      Compute S' = σ_k(S)
      If S' ≠ A_k:
        Compute N(S')
        Submit separator cut for S'   ▷ symmetry-strengthened

  If no cut submitted: candidate is fully valid → accept
```

All disconnected components across all galaxies are processed in a **single callback invocation**, minimising round-trips to the solver.

---

### Complexity Note

| Component | Count |
|---|---|
| Binary variables $x_{i,j,k}$ | $O(n \cdot m \cdot K)$ |
| Partition constraints | $O(n \cdot m)$ |
| Anchor constraints | $O(K)$ |
| Symmetry constraints | $O(n \cdot m \cdot K)$ |
| Connectivity cuts (dynamic) | $O(2^{nm})$ worst case, few in practice |

No big-M coefficients appear anywhere in the model. The LP relaxation is therefore tight, and CPLEX typically requires very few separator cuts before finding the optimal solution. For typical instances (up to ~20×20 with ~15 galaxies) this is tractable.

---

## Instance File Format

```
<m_cols> <n_rows>
# dots
p1 q1         (doubled coordinates of each dot)
p2 q2
...
# solution                         (optional, for verification)
1 1 1 2 2 2 3 3                    (one galaxy index per cell, row by row)
1 1 2 2 3 3 3 3
...
```

Dot coordinates $(p_k, q_k)$ are given in the **doubled** coordinate system described above (both even = cell centre; one odd = edge midpoint; both odd = corner). For an $n \times m$ grid, valid doubled coordinates satisfy $p_k \in [1, 2n]$ and $q_k \in [1, 2m]$.

**Example** — a $4 \times 4$ grid with three galaxies:

```
4 4
# dots
2 2      (centre of cell (1,1))
4 5      (vertical edge midpoint between cells (2,2) and (2,3))
7 7      (corner shared by cells (3,3),(3,4),(4,3),(4,4))
# solution
1 1 2 2
1 1 2 2
1 3 3 2
3 3 3 2
```

---

## Directory Structure

```
galaxies/
├── data/                  # Grid instances (.txt files)
├── res/
│   ├── cplex/             # CPLEX solving results (solveTime, isOptimal)
│   └── heuristique/       # Heuristic solving results
└── src/
    ├── io.jl              # Read/write/display instances, performance reports
    ├── generation.jl      # Random Galaxies instance generation
    └── resolution.jl      # JuMP/CPLEX model with lazy-constraint callback
                           # and heuristic solver
```

---

## Usage

From the Julia REPL, navigate to the `galaxies/src/` directory:

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