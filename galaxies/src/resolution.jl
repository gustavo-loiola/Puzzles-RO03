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
# Pre-computation
# ─────────────────────────────────────────────────────────────────────────────

"""
    precompute(n, m, dots) -> (dot_cells, sym_pairs, eligible)

Compute once all the per-galaxy and per-cell data needed by the model and callback.

Returns
-------
- `dot_cells[k]`   : cells (row,col) touched by dot k
- `sym_pairs[k]`   : unique symmetric pairs (i,j,si,sj) for galaxy k,
                     kept with (si,sj) ≥ (i,j) to avoid duplicates in R3
- `eligible[i,j]`  : galaxy indices k for which sym_k(i,j) is inside the grid
                     (i.e. x[i,j,k] is allowed to be 1)
"""
function precompute(n::Int, m::Int, dots::Vector{Tuple{Int,Int}})
    K = length(dots)

    dot_cells = [cells_touched_by_dot(dots[k][1], dots[k][2], n, m) for k in 1:K]

    sym_pairs = [Tuple{Int,Int,Int,Int}[] for _ in 1:K]
    eligible  = [Int[] for _ in 1:n*m]   # flattened: index = (i-1)*m + j

    for i in 1:n, j in 1:m
        idx = (i-1)*m + j
        for k in 1:K
            dr, dc = dots[k]
            sc = sym_cell(i, j, dr, dc, n, m)
            if sc !== nothing
                push!(eligible[idx], k)
                si, sj = sc
                # Add pair only once (canonical: (si,sj) >= (i,j))
                if si > i || (si == i && sj >= j)
                    push!(sym_pairs[k], (i, j, si, sj))
                end
            end
        end
    end

    # Constraint propagation: if a cell has only one eligible galaxy, fix it,
    # then force its symmetric image to the same galaxy, then remove that galaxy
    # from all other cells that share the symmetric image — and repeat until stable.
    changed = true
    while changed
        changed = false
        for i in 1:n, j in 1:m
            idx  = (i-1)*m + j
            elig = eligible[idx]
            length(elig) == 1 || continue
            k      = elig[1]
            dr, dc = dots[k]
            sc     = sym_cell(i, j, dr, dc, n, m)
            sc === nothing && continue
            si, sj = sc
            sidx   = (si-1)*m + sj
            # Force symmetric cell to galaxy k
            if eligible[sidx] != [k]
                eligible[sidx] = [k]
                changed = true
            end
            # Remove k from every other cell that was competing with (si,sj)
            # — not needed here since (si,sj) is now fixed; but removing k
            # from cells whose only option was k would be wrong, so we just
            # re-trigger the loop to propagate the newly fixed (si,sj).
        end
        # Also propagate: if (si,sj) just got fixed to k, remove k's
        # "forced" status from any cell where it was the only option but
        # now its symmetric is taken by another galaxy.
        for i in 1:n, j in 1:m
            idx  = (i-1)*m + j
            elig = eligible[idx]
            # Remove galaxies whose symmetric image for (i,j) is now fixed to a different galaxy
            new_elig = filter(elig) do k
                dr, dc = dots[k]
                sc = sym_cell(i, j, dr, dc, n, m)
                sc === nothing && return false
                si, sj  = sc
                sidx    = (si-1)*m + sj
                s_fixed = eligible[sidx]
                # Allow k only if the symmetric cell is either unfixed or fixed to k
                return length(s_fixed) != 1 || s_fixed[1] == k
            end
            if length(new_elig) < length(elig)
                eligible[idx] = new_elig
                changed = true
            end
        end
    end

    # Rebuild sym_pairs from the (possibly reduced) eligible sets
    sym_pairs = [Tuple{Int,Int,Int,Int}[] for _ in 1:K]
    for i in 1:n, j in 1:m
        idx = (i-1)*m + j
        for k in eligible[idx]
            dr, dc = dots[k]
            sc = sym_cell(i, j, dr, dc, n, m)
            sc === nothing && continue
            si, sj = sc
            if si > i || (si == i && sj >= j)
                push!(sym_pairs[k], (i, j, si, sj))
            end
        end
    end

    return dot_cells, sym_pairs, eligible
end


# ─────────────────────────────────────────────────────────────────────────────
# Heuristic pre-solver
# ─────────────────────────────────────────────────────────────────────────────

"""
    heuristicSolve(n, m, dots, eligible) -> (feasible::Bool, assignment::Matrix{Int})

Greedy heuristic that produces a (possibly partial) warm-start for CPLEX.

Algorithm
---------
1. Propagation seed: cells with only one eligible galaxy are immediately fixed
   (these come directly from the precomputed `eligible` after constraint propagation).
   This is much stronger than just anchoring dot cells — edge/corner cells near
   grid boundaries are often forced because their symmetric image would fall outside
   the grid for all but one galaxy.
2. BFS frontier expansion: grow every galaxy outward, always assigning a cell
   together with its symmetric counterpart (maintaining R3 at every step).
3. Final sweep: assign any remaining free cells to the first eligible galaxy.

Returns `(feasible, assignment)` where `assignment[i,j] = 0` means unassigned.
"""
function heuristicSolve(n::Int, m::Int, dots::Vector{Tuple{Int,Int}},
                        eligible::Vector{Vector{Int}})
    K          = length(dots)
    assignment = zeros(Int, n, m)

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

    # Step 1 — seed from propagation: fix all cells with a single eligible galaxy
    for i in 1:n, j in 1:m
        elig = eligible[(i-1)*m+j]
        length(elig) == 1 && try_assign!(i, j, elig[1])
    end

    # Step 2 — BFS frontier expansion
    changed = true
    while changed
        changed = false
        for k in 1:K, i in 1:n, j in 1:m
            if assignment[i,j] == k
                for (ni, nj) in grid_neighbors(i, j, n, m)
                    if assignment[ni,nj] == 0 && k ∈ eligible[(ni-1)*m+nj]
                        try_assign!(ni, nj, k) && (changed = true)
                    end
                end
            end
        end
    end

    # Step 3 — final sweep
    for i in 1:n, j in 1:m
        if assignment[i,j] == 0
            for k in eligible[(i-1)*m+j]
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
    dot_cells, sym_pairs, eligible = precompute(n, m, dots)

    # ── Build model ──────────────────────────────────────────────────────────
    model = Model(CPLEX.Optimizer)
    set_optimizer_attribute(model, "CPX_PARAM_TILIM",  time_limit)
    set_optimizer_attribute(model, "CPX_PARAM_SCRIND", 0)
    MOI.set(model, MOI.NumberOfThreads(), 1)   # required for lazy callbacks

    # Sparse variable creation: only create x[i,j,k] when k ∈ eligible[i,j].
    # Cells with a single eligible galaxy are immediately fixed to 1 for that galaxy.
    x = Dict{Tuple{Int,Int,Int}, VariableRef}()
    for i in 1:n, j in 1:m
        idx  = (i-1)*m + j
        elig = eligible[idx]
        if length(elig) == 1
            # Forced assignment — no variable needed, encode as a fixed variable
            k = elig[1]
            x[(i,j,k)] = @variable(model, binary=true)
            @constraint(model, x[(i,j,k)] == 1)
        else
            for k in elig
                x[(i,j,k)] = @variable(model, binary=true)
            end
        end
    end

    # R1 — every cell belongs to exactly one galaxy
    for i in 1:n, j in 1:m
        idx  = (i-1)*m + j
        elig = eligible[idx]
        @constraint(model, sum(x[(i,j,k)] for k in elig) == 1)
    end

    # R2 — cells touched by dot k are assigned to galaxy k
    for k in 1:K, (ci, cj) in dot_cells[k]
        if haskey(x, (ci, cj, k))
            @constraint(model, x[(ci,cj,k)] == 1)
        end
    end

    # R3 — symmetry: paired cells must share the same galaxy assignment
    for k in 1:K, (i, j, si, sj) in sym_pairs[k]
        if (i,j) != (si,sj) && haskey(x,(i,j,k)) && haskey(x,(si,sj,k))
            @constraint(model, x[(i,j,k)] == x[(si,sj,k)])
        end
    end

    # Minimize total galaxy perimeter as a tiebreaker (linear).
    # b[i,j,dir] = 1 if cell (i,j) and its neighbour in direction dir belong to
    # different galaxies. Encoded as: b >= x[i,j,k] - x[ni,nj,k] and
    # b >= x[ni,nj,k] - x[i,j,k] for all shared eligible k, so b=1 whenever
    # the two cells differ. This biases CPLEX toward compact galaxies and breaks
    # ties between equally-valid assignments, helping find a feasible point faster.
    border_vars = Dict{Tuple{Int,Int,Int,Int}, VariableRef}()
    perimeter_cost = AffExpr()
    for i in 1:n, j in 1:m
        for (ni, nj) in grid_neighbors(i, j, n, m)
            ni > i || (ni == i && nj > j) || continue   # each edge once
            shared_k = intersect(eligible[(i-1)*m+j], eligible[(ni-1)*m+nj])
            isempty(shared_k) && continue
            b = @variable(model, binary=true)
            border_vars[(i,j,ni,nj)] = b
            add_to_expression!(perimeter_cost, b)
            for k in shared_k
                @constraint(model,  b >= x[(i,j,k)] - x[(ni,nj,k)])
                @constraint(model,  b >= x[(ni,nj,k)] - x[(i,j,k)])
            end
        end
    end
    @objective(model, Min, perimeter_cost)

    h_assign = zeros(Int, n, m)   # partial heuristic assignment (may be empty)

    # ── Warm start ───────────────────────────────────────────────────────────
    if use_heuristic_start
        h_ok, h_assign = heuristicSolve(n, m, dots, eligible)
        assigned = count(h_assign[i,j] != 0 for i in 1:n, j in 1:m)
        println("  Heuristic warm start: $(h_ok ? "feasible" : "$assigned/$(n*m) cells assigned")")
        # Always feed whatever was assigned — CPLEX accepts partial MIP starts
        for i in 1:n, j in 1:m
            h_assign[i,j] == 0 && continue
            for k in eligible[(i-1)*m+j]
                set_start_value(x[(i,j,k)], h_assign[i,j] == k ? 1.0 : 0.0)
            end
        end
    end

    # ── Lazy-constraint callback (R4 — connectivity) ─────────────────────────
    #
    # Fires on every integer-feasible candidate. For each galaxy k, a BFS
    # from the dot anchor checks whether all assigned cells are reachable.
    # Any disconnected component S triggers a separator cut.
    #
    # Optimization: we only read x values for (i,j,k) pairs that exist,
    # skipping the ~68% of (cell, galaxy) pairs that are ineligible.
    function connectivity_callback(cb_data)
        callback_node_status(cb_data, model) != MOI.CALLBACK_NODE_STATUS_INTEGER && return

        # Read only eligible x values, store as galaxy → assigned cells
        galaxy_cells = [Tuple{Int,Int}[] for _ in 1:K]
        for i in 1:n, j in 1:m
            for k in eligible[(i-1)*m+j]
                if round(Int, callback_value(cb_data, x[(i,j,k)])) == 1
                    push!(galaxy_cells[k], (i,j))
                end
            end
        end

        for k in 1:K
            gcells = galaxy_cells[k]
            isempty(gcells) && continue

            # BFS from the dot anchor
            anchor    = dot_cells[k][1]
            reachable = Set{Tuple{Int,Int}}([anchor])
            queue     = [anchor]
            while !isempty(queue)
                ci, cj = popfirst!(queue)
                for (ni, nj) in grid_neighbors(ci, cj, n, m)
                    if (ni, nj) ∉ reachable && (ni,nj) in gcells
                        push!(reachable, (ni, nj))
                        push!(queue, (ni, nj))
                    end
                end
            end

            all(c ∈ reachable for c in gcells) && continue   # already connected

            # Find each disconnected component and add a separator cut
            gcells_set = Set(gcells)
            visited    = copy(reachable)
            for start_cell in gcells
                start_cell ∈ visited && continue

                # BFS to collect the disconnected component S
                S     = Set{Tuple{Int,Int}}([start_cell])
                queue = [start_cell]
                push!(visited, start_cell)
                while !isempty(queue)
                    ci, cj = popfirst!(queue)
                    for (ni, nj) in grid_neighbors(ci, cj, n, m)
                        if (ni, nj) ∉ visited && (ni,nj) ∈ gcells_set
                            push!(S, (ni,nj)); push!(visited, (ni,nj)); push!(queue, (ni,nj))
                        end
                    end
                end

                # N(S): all grid cells neighbouring S, outside S
                NS = Set(nb for (ci,cj) in S
                            for nb in grid_neighbors(ci, cj, n, m)
                            if nb ∉ S)

                # Separator cut: S must shrink or a bridge from N(S) must join galaxy k
                cut = @build_constraint(
                    sum(x[(ci,cj,k)]   for (ci,cj) in S  if haskey(x,(ci,cj,k))) +
                    sum(1-x[(ni,nj,k)] for (ni,nj) in NS if haskey(x,(ni,nj,k))) >= 1
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
        for i in 1:n, j in 1:m
            for k in eligible[(i-1)*m+j]
                if round(Int, value(x[(i,j,k)])) == 1
                    assignment[i,j] = k
                    break
                end
            end
        end
    end

    return is_optimal, elapsed, assignment, h_assign
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
            is_opt, c_time, c_assign, h_assign = cplexSolve(n, m, dots)
            open(c_path, "w") do f
                println(f, "solveTime = $c_time\nisOptimal = $is_opt")
            end
            println("  CPLEX:     $(is_opt ? "✓" : "✗")  $(round(c_time, sigdigits=3))s")
            is_opt && displaySolution(n, m, dots, c_assign)
        end
    end
end
