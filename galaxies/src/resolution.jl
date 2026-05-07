# resolution.jl
# ILP solver for the Galaxies puzzle using JuMP/CPLEX.
#
# ─────────────────────────────────────────────────────────────────────────────
# Connectivity strategy: lazy-constraint callback (NOT flow variables)
# ─────────────────────────────────────────────────────────────────────────────
#
# R1–R3 (partition, anchor, symmetry) are encoded upfront as standard linear
# constraints. R4 (connectivity) cannot be fully linearised with a polynomial
# number of constraints, so it is handled via a CPLEX lazy-constraint callback:
#
#   1. CPLEX finds an integer-feasible candidate (R1–R3 satisfied).
#   2. The callback runs a BFS on every galaxy k's assigned cells.
#   3. If a galaxy is disconnected, it identifies a component S that is cut off
#      from the dot anchor and adds the separator cut:
#
#          Σ_{c ∈ S} x[c,k]  +  Σ_{c ∈ N(S)} (1 − x[c,k])  ≥  1
#
#      This forces the solver to either break up S or open a connecting path.
#   4. CPLEX discards the candidate and continues branch-and-bound.
#
# Why not flow variables?
# Flow-based connectivity (as in the Range solver) introduces O(n·m·K) extra
# continuous variables and O(n·m·K) flow-conservation constraints, which
# becomes very expensive for large K. The callback approach adds cuts only
# when they are needed, keeping the model compact and leveraging CPLEX's
# branch-and-cut machinery.
#
# ─────────────────────────────────────────────────────────────────────────────
# Variable
#   x[i,j,k] ∈ {0,1}   1 iff cell (i,j) belongs to galaxy k
#
# Constraints
#   R1  Partition:      Σ_k x[i,j,k] = 1           ∀ (i,j)
#   R2  Dot anchor:     x[c,k] = 1                  ∀ c touched by dot k
#   R3  Symmetry:       x[i,j,k] = x[sym_k(i,j),k] ∀ (i,j), ∀ k
#       Infeasibility:  x[i,j,k] = 0                if sym_k(i,j) ∉ grid
#   R4  Connectivity:   lazy separator cuts (see callback below)
#
# Objective: pure feasibility (constant 0)
# ─────────────────────────────────────────────────────────────────────────────

using JuMP, CPLEX
include("io.jl")


# ─────────────────────────────────────────────────────────────────────────────
# Geometry helpers
# ─────────────────────────────────────────────────────────────────────────────

"""
    cells_touched_by_dot(dr, dc, n, m) -> Vector{Tuple{Int,Int}}

Return the grid cells (row, col) that a dot at double-grid position (dr, dc) touches.
The number of cells depends on the parity of dr and dc (see io.jl header).
"""
function cells_touched_by_dot(dr::Int, dc::Int, n::Int, m::Int)
    rows = iseven(dr) ? [dr÷2, dr÷2 + 1] : [(dr+1)÷2]
    cols = iseven(dc) ? [dc÷2, dc÷2 + 1] : [(dc+1)÷2]
    return [(r, c) for r in rows, c in cols if 1 <= r <= n && 1 <= c <= m]
end


"""
    sym_cell(i, j, dr, dc, n, m) -> Union{Tuple{Int,Int}, Nothing}

Return the 180°-symmetric cell of (i,j) about dot (dr, dc) in double-grid coords.
The centre of cell (i,j) is at double-grid (2i-1, 2j-1); its symmetric is
(2·dr − (2i-1),  2·dc − (2j-1)). Returns `nothing` if outside the grid.
"""
function sym_cell(i::Int, j::Int, dr::Int, dc::Int, n::Int, m::Int)
    si_d = 2dr - (2i - 1)
    sj_d = 2dc - (2j - 1)
    iseven(si_d) || iseven(sj_d) && return nothing   # not a cell centre
    si, sj = (si_d + 1) ÷ 2, (sj_d + 1) ÷ 2
    return (1 <= si <= n && 1 <= sj <= m) ? (si, sj) : nothing
end


"""
    grid_neighbors(i, j, n, m) -> Vector{Tuple{Int,Int}}

4-connected neighbours of cell (i,j) within an n×m grid.
"""
function grid_neighbors(i::Int, j::Int, n::Int, m::Int)
    nb = Tuple{Int,Int}[]
    i > 1 && push!(nb, (i-1, j))
    i < n && push!(nb, (i+1, j))
    j > 1 && push!(nb, (i, j-1))
    j < m && push!(nb, (i, j+1))
    return nb
end


# ─────────────────────────────────────────────────────────────────────────────
# Heuristic pre-solver
# ─────────────────────────────────────────────────────────────────────────────

"""
    heuristicSolve(n, m, dots) -> (feasible::Bool, assignment::Matrix{Int})

Greedy heuristic that produces a warm-start solution for CPLEX.

Algorithm
---------
1. Anchor each galaxy's dot cell(s); also anchor their symmetric images.
2. BFS frontier expansion: repeatedly grow every galaxy outward, always
   assigning a cell together with its symmetric counterpart.
3. Final sweep: assign any remaining unassigned cells to the first galaxy
   whose symmetry constraint they satisfy.

Returns `(true, assignment)` if all cells are covered, `(false, ...)` otherwise.
"""
function heuristicSolve(n::Int, m::Int, dots::Vector{Tuple{Int,Int}})
    K          = length(dots)
    assignment = zeros(Int, n, m)   # 0 = unassigned

    # Assign cell (i,j) to galaxy k and its symmetric image simultaneously.
    # Returns false if either cell is already owned by a different galaxy,
    # or if the symmetric image lies outside the grid.
    function try_assign!(i, j, k)
        dr, dc = dots[k]
        sc = sym_cell(i, j, dr, dc, n, m)
        sc === nothing && return false
        si, sj = sc
        (assignment[i,j]  ∉ (0, k)) && return false
        (assignment[si,sj] ∉ (0, k)) && return false
        assignment[i,j]  = k
        assignment[si,sj] = k
        return true
    end

    # Step 1 — anchor dot cells
    for k in 1:K
        dr, dc = dots[k]
        for (ci, cj) in cells_touched_by_dot(dr, dc, n, m)
            assignment[ci, cj] = k
            sc = sym_cell(ci, cj, dr, dc, n, m)
            sc !== nothing && (assignment[sc[1], sc[2]] = k)
        end
    end

    # Step 2 — BFS frontier expansion
    changed = true
    while changed
        changed = false
        for k in 1:K, i in 1:n, j in 1:m
            if assignment[i,j] == k
                for (ni, nj) in grid_neighbors(i, j, n, m)
                    assignment[ni,nj] == 0 && try_assign!(ni, nj, k) && (changed = true)
                end
            end
        end
    end

    # Step 3 — final sweep for any remaining unassigned cells
    for i in 1:n, j in 1:m
        if assignment[i,j] == 0
            for k in 1:K
                try_assign!(i, j, k) && break
            end
        end
    end

    return all(assignment[i,j] != 0 for i in 1:n, j in 1:m), assignment
end


# ─────────────────────────────────────────────────────────────────────────────
# ILP solver
# ─────────────────────────────────────────────────────────────────────────────

"""
    cplexSolve(n, m, dots; time_limit, use_heuristic_start)
        -> (isOptimal::Bool, solveTime::Float64, assignment::Matrix{Int})

Solve a Galaxies instance with JuMP/CPLEX.
Constraints R1–R3 are encoded upfront; R4 (connectivity) is enforced via
lazy separator cuts added inside a CPLEX callback (see file header).

Keyword arguments
-----------------
- `time_limit`          : CPLEX time limit in seconds (default 300).
- `use_heuristic_start` : if true, warm-start CPLEX with the heuristic solution.
"""
function cplexSolve(n::Int, m::Int, dots::Vector{Tuple{Int,Int}};
                    time_limit::Float64      = 300.0,
                    use_heuristic_start::Bool = true)

    K = length(dots)

    # Pre-compute per-galaxy dot cells (used in R2 and in the callback)
    dot_cells = [cells_touched_by_dot(dots[k][1], dots[k][2], n, m) for k in 1:K]

    # Pre-compute unique symmetric pairs per galaxy (used in R3)
    # Keep only (i,j,si,sj) with (si,sj) ≥ (i,j) to avoid adding each pair twice.
    sym_pairs = [Tuple{Int,Int,Int,Int}[] for _ in 1:K]
    for k in 1:K
        dr, dc = dots[k]
        for i in 1:n, j in 1:m
            sc = sym_cell(i, j, dr, dc, n, m)
            if sc !== nothing
                si, sj = sc
                if si > i || (si == i && sj >= j)
                    push!(sym_pairs[k], (i, j, si, sj))
                end
            end
        end
    end

    # ── Build model ──────────────────────────────────────────────────────────
    model = Model(CPLEX.Optimizer)
    set_optimizer_attribute(model, "CPX_PARAM_TILIM",  time_limit)
    set_optimizer_attribute(model, "CPX_PARAM_SCRIND", 0)           # silent
    MOI.set(model, MOI.NumberOfThreads(), 1)                        # required for lazy callbacks

    @variable(model, x[1:n, 1:m, 1:K], Bin)

    # R1 — every cell belongs to exactly one galaxy
    @constraint(model, [i in 1:n, j in 1:m],
        sum(x[i, j, k] for k in 1:K) == 1)

    # R2 — cells touched by dot k are assigned to galaxy k
    for k in 1:K, (ci, cj) in dot_cells[k]
        @constraint(model, x[ci, cj, k] == 1)
    end

    # R3 — symmetry: cell and its image must belong to the same galaxy
    for k in 1:K, (i, j, si, sj) in sym_pairs[k]
        (i, j) != (si, sj) && @constraint(model, x[i, j, k] == x[si, sj, k])
    end

    # R3 (infeasibility) — if the symmetric image is outside the grid, forbid assignment
    for k in 1:K
        dr, dc = dots[k]
        for i in 1:n, j in 1:m
            sym_cell(i, j, dr, dc, n, m) === nothing && @constraint(model, x[i, j, k] == 0)
        end
    end

    @objective(model, Min, 0)

    # ── Warm start ───────────────────────────────────────────────────────────
    if use_heuristic_start
        h_ok, h_assign = heuristicSolve(n, m, dots)
        if h_ok
            for i in 1:n, j in 1:m, k in 1:K
                set_start_value(x[i, j, k], h_assign[i, j] == k ? 1.0 : 0.0)
            end
            println("  Heuristic warm start: feasible")
        else
            println("  Heuristic warm start: no complete solution found")
        end
    end

    # ── Lazy-constraint callback (R4 — connectivity) ─────────────────────────
    #
    # Fires on every integer-feasible candidate. For each galaxy k, a BFS
    # from the dot anchor checks whether all assigned cells are reachable.
    # Any disconnected component S triggers a separator cut.
    function connectivity_callback(cb_data)
        callback_node_status(cb_data, model) != MOI.CALLBACK_NODE_STATUS_INTEGER && return

        x_val   = [callback_value(cb_data, x[i, j, k]) for i in 1:n, j in 1:m, k in 1:K]
        x_round = round.(Int, x_val)

        for k in 1:K
            galaxy_cells = [(i, j) for i in 1:n, j in 1:m if x_round[i, j, k] == 1]
            isempty(galaxy_cells) && continue

            # BFS from the dot anchor
            anchor    = dot_cells[k][1]
            reachable = Set{Tuple{Int,Int}}([anchor])
            queue     = [anchor]
            while !isempty(queue)
                ci, cj = popfirst!(queue)
                for (ni, nj) in grid_neighbors(ci, cj, n, m)
                    if (ni, nj) ∉ reachable && x_round[ni, nj, k] == 1
                        push!(reachable, (ni, nj))
                        push!(queue, (ni, nj))
                    end
                end
            end

            # Find disconnected components and add a separator cut for each
            visited = copy(reachable)
            for start_cell in galaxy_cells
                start_cell ∈ visited && continue

                # BFS to collect the disconnected component S
                S     = Set{Tuple{Int,Int}}([start_cell])
                queue = [start_cell]
                push!(visited, start_cell)
                while !isempty(queue)
                    ci, cj = popfirst!(queue)
                    for (ni, nj) in grid_neighbors(ci, cj, n, m)
                        if (ni, nj) ∉ visited && x_round[ni, nj, k] == 1
                            push!(S, (ni, nj)); push!(visited, (ni, nj)); push!(queue, (ni, nj))
                        end
                    end
                end

                # N(S): all cells neighbouring S (regardless of assignment)
                NS = Set(nb for (ci, cj) in S for nb in grid_neighbors(ci, cj, n, m) if nb ∉ S)

                # Separator cut: S must shrink or a bridge cell in N(S) must join galaxy k
                cut = @build_constraint(
                    sum(x[ci, cj, k] for (ci, cj) in S) +
                    sum(1 - x[ni, nj, k] for (ni, nj) in NS) >= 1
                )
                MOI.submit(model, MOI.LazyConstraint(cb_data), cut)
            end
        end
    end

    set_attribute(model, MOI.LazyConstraintCallback(), connectivity_callback)

    # ── Solve ────────────────────────────────────────────────────────────────
    t0 = time()
    optimize!(model)
    elapsed = time() - t0

    is_optimal = primal_status(model) == MOI.FEASIBLE_POINT

    assignment = zeros(Int, n, m)
    if is_optimal
        x_sol = round.(Int, value.(x))
        for i in 1:n, j in 1:m, k in 1:K
            x_sol[i, j, k] == 1 && (assignment[i, j] = k)
        end
    end

    return is_optimal, elapsed, assignment
end


# ─────────────────────────────────────────────────────────────────────────────
# Batch runner
# ─────────────────────────────────────────────────────────────────────────────

"""
    solveDataSet()

Solve every .txt instance in `../data/` with both the heuristic and CPLEX.
Results are written to `../res/heuristique/` and `../res/cplex/`.
"""
function solveDataSet()
    dataFolder = "../data/"
    resFolder  = "../res/"

    for method in ["cplex", "heuristique"]
        dir = resFolder * method
        isdir(dir) || mkdir(dir)
    end

    for file in filter(x -> endswith(x, ".txt"), readdir(dataFolder))
        println("\n── $file")
        n, m, dots = readInputFile(dataFolder * file)
        displayGrid(n, m, dots)

        # Heuristic
        h_path = resFolder * "heuristique/" * file
        if !isfile(h_path)
            t0 = time()
            h_ok, h_assign = heuristicSolve(n, m, dots)
            h_time = time() - t0
            open(h_path, "w") do f
                println(f, "solveTime = $h_time\nisOptimal = $h_ok")
            end
            println("  Heuristic: $(h_ok ? "✓" : "✗")  $(round(h_time, sigdigits=3))s")
            h_ok && displaySolution(n, m, dots, h_assign)
        end

        # CPLEX
        c_path = resFolder * "cplex/" * file
        if !isfile(c_path)
            is_opt, c_time, c_assign = cplexSolve(n, m, dots)
            open(c_path, "w") do f
                println(f, "solveTime = $c_time\nisOptimal = $is_opt")
            end
            println("  CPLEX:     $(is_opt ? "✓" : "✗")  $(round(c_time, sigdigits=3))s")
            is_opt && displaySolution(n, m, dots, c_assign)
        end
    end
end
