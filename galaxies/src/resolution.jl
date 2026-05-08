# ─────────────────────────────────────────────────────────────────────────────
#  resolution.jl — Galaxies ILP solver (CPLEX + lazy callbacks) and heuristic
#
#  Mathematical model (see README.md for full formulation):
#    (C1) Partition    — each cell belongs to exactly one galaxy
#    (C2) Anchors      — dot cells are pre-assigned to their galaxy
#    (C3) Symmetry     — x[i,j,k] = x[σ_k(i,j), k]; = 0 if σ_k outside grid
#    (C4) Connectivity — enforced via lazy separator cuts in a callback
# ─────────────────────────────────────────────────────────────────────────────

using CPLEX
using JuMP

include("generation.jl")

TOL = 0.00001


# ═════════════════════════════════════════════════════════════════════════════
#  BFS / connectivity helpers  (used by callback and verification)
# ═════════════════════════════════════════════════════════════════════════════

const NEIGHBOUR_OFFSETS = ((-1, 0), (1, 0), (0, -1), (0, 1))

"""
BFS from `source` visiting only cells in `region_set`.
Returns the `Set` of cells reachable from `source`.
"""
function bfsReachable(source::Tuple{Int,Int},
                      region_set::Set{Tuple{Int,Int}},
                      n::Int, m::Int)

    reachable = Set{Tuple{Int,Int}}()
    if !(source in region_set)
        return reachable
    end

    push!(reachable, source)
    queue = [source]

    while !isempty(queue)
        i, j = popfirst!(queue)
        for (di, dj) in NEIGHBOUR_OFFSETS
            ni, nj = i + di, j + dj
            if 1 <= ni <= n && 1 <= nj <= m &&
               (ni, nj) in region_set && !((ni, nj) in reachable)
                push!(reachable, (ni, nj))
                push!(queue, (ni, nj))
            end
        end
    end
    return reachable
end


"""
Find every connected component of `region_set` that is NOT reachable
from `source`.  Each component is returned as a `Vector{Tuple{Int,Int}}`.
"""
function findDisconnectedComponents(region_set::Set{Tuple{Int,Int}},
                                    source::Tuple{Int,Int},
                                    n::Int, m::Int)

    reachable  = bfsReachable(source, region_set, n, m)
    unreached  = setdiff(region_set, reachable)
    visited    = Set{Tuple{Int,Int}}()
    components = Vector{Vector{Tuple{Int,Int}}}()

    for cell in unreached
        cell in visited && continue

        comp  = Tuple{Int,Int}[]
        queue = [cell]
        push!(visited, cell)

        while !isempty(queue)
            ci, cj = popfirst!(queue)
            push!(comp, (ci, cj))
            for (di, dj) in NEIGHBOUR_OFFSETS
                ni, nj = ci + di, cj + dj
                if (ni, nj) in unreached && !((ni, nj) in visited)
                    push!(visited, (ni, nj))
                    push!(queue, (ni, nj))
                end
            end
        end
        push!(components, comp)
    end
    return components
end


"""
Compute N(S) — cells outside S that are 4-adjacent to some cell of S.
"""
function getNeighbourhood(S::Vector{Tuple{Int,Int}}, n::Int, m::Int)
    S_set = Set(S)
    NS = Set{Tuple{Int,Int}}()
    for (i, j) in S
        for (di, dj) in NEIGHBOUR_OFFSETS
            ni, nj = i + di, j + dj
            if 1 <= ni <= n && 1 <= nj <= m && !((ni, nj) in S_set)
                push!(NS, (ni, nj))
            end
        end
    end
    return collect(NS)
end


# ═════════════════════════════════════════════════════════════════════════════
#  CPLEX solver with lazy-constraint callback
# ═════════════════════════════════════════════════════════════════════════════

"""
Solve a Galaxies instance with CPLEX.

Constraints (C1)–(C3) are added statically; connectivity (C4) is enforced
through a lazy-constraint callback that adds separator cuts on the fly.

Arguments:
- grid: tuple (n, m) — grid dimensions
- dots: Vector{Tuple{Int,Int}} — dot positions in doubled coordinates

Returns:
- isOptimal:  true if a feasible solution was found
- solveTime:  wall-clock solving time (seconds)
- solution:   n×m Matrix{Int} where entry k means "belongs to galaxy k"
"""
function cplexSolve(grid, dots)

    n, m = grid
    K = length(dots)

    if K == 0
        return false, 0.0, fill(-1, n, m)
    end

    # ─────────────────────────────────────────────────────────────────────
    #  Precomputation
    # ─────────────────────────────────────────────────────────────────────

    # Anchor cells per galaxy
    anchors = [getAnchorCells(dots[k][1], dots[k][2], n, m) for k in 1:K]

    # canBelong[i,j,k]  = true iff σ_k(i,j) is inside the grid
    # symOf[i,j,k]      = (si, sj) — the symmetric image (valid only if canBelong)
    canBelong = falses(n, m, K)
    symOf     = Array{Tuple{Int,Int}}(undef, n, m, K)

    for k in 1:K
        p, q = dots[k]
        for i in 1:n, j in 1:m
            img = symmetricImage(i, j, p, q, n, m)
            if img !== nothing
                canBelong[i, j, k] = true
                symOf[i, j, k] = img
            end
        end
    end

    # ─────────────────────────────────────────────────────────────────────
    #  Build the model
    # ─────────────────────────────────────────────────────────────────────

    model = Model(CPLEX.Optimizer)
    set_silent(model)
    set_time_limit_sec(model, 120.0)

    # ── Decision variables ───────────────────────────────────────────────
    @variable(model, x[1:n, 1:m, 1:K], Bin)

    # Fix x[i,j,k] = 0 when cell cannot belong to galaxy k (σ_k outside grid)
    for k in 1:K, i in 1:n, j in 1:m
        if !canBelong[i, j, k]
            @constraint(model, x[i, j, k] == 0)
        end
    end

    # ── (C1) Full partition — each cell assigned to exactly one galaxy ───
    for i in 1:n, j in 1:m
        @constraint(model, sum(x[i, j, k] for k in 1:K) == 1)
    end

    # ── (C2) Anchor cells — dot cells belong to their galaxy ─────────────
    for k in 1:K
        for (ai, aj) in anchors[k]
            @constraint(model, x[ai, aj, k] == 1)
        end
    end

    # ── (C3) 180° rotational symmetry ────────────────────────────────────
    # For each feasible (i,j,k) pair with (i,j) < σ_k(i,j) lexicographically,
    # enforce x[i,j,k] = x[σ_k(i,j), k].  Self-symmetric cells are skipped.
    for k in 1:K
        for i in 1:n, j in 1:m
            if !canBelong[i, j, k]
                continue
            end
            si, sj = symOf[i, j, k]
            # Only add for the canonical representative of each pair
            if (i, j) < (si, sj)
                @constraint(model, x[i, j, k] == x[si, sj, k])
            end
        end
    end

    # ── (C4) Connectivity — lazy-constraint callback ─────────────────────

    function connectivityCallback(cb_data)

        # Only process integer-feasible candidates
        status = callback_node_status(cb_data, model)
        if status != MOI.CALLBACK_NODE_STATUS_INTEGER
            return
        end

        # Read candidate assignment for each galaxy
        for k in 1:K
            region_set = Set{Tuple{Int,Int}}()
            for i in 1:n, j in 1:m
                if callback_value(cb_data, x[i, j, k]) > 0.5
                    push!(region_set, (i, j))
                end
            end

            isempty(region_set) && continue

            # BFS from the first anchor cell (guaranteed to be in region)
            source = anchors[k][1]
            components = findDisconnectedComponents(region_set, source, n, m)

            isempty(components) && continue   # galaxy k is connected

            # Submit separator cuts
            p, q = dots[k]
            for S in components
                NS = getNeighbourhood(S, n, m)

                # Primary cut for S
                con = @build_constraint(
                    sum(1 - x[ci, cj, k] for (ci, cj) in S) +
                    sum(x[ni, nj, k] for (ni, nj) in NS) >= 1
                )
                MOI.submit(model, MOI.LazyConstraint(cb_data), con)

                # ── Symmetry-strengthened cut for σ_k(S) ─────────────
                S_sym = Tuple{Int,Int}[]
                all_valid = true
                for (ci, cj) in S
                    img = symmetricImage(ci, cj, p, q, n, m)
                    if img === nothing
                        all_valid = false
                        break
                    end
                    push!(S_sym, img)
                end

                if all_valid && !isempty(S_sym) && Set(S_sym) != Set(S)
                    NS_sym = getNeighbourhood(S_sym, n, m)
                    con_sym = @build_constraint(
                        sum(1 - x[ci, cj, k] for (ci, cj) in S_sym) +
                        sum(x[ni, nj, k] for (ni, nj) in NS_sym) >= 1
                    )
                    MOI.submit(model, MOI.LazyConstraint(cb_data), con_sym)
                end
            end
        end
    end

    set_attribute(model, MOI.LazyConstraintCallback(), connectivityCallback)

    # ── Objective: feasibility ───────────────────────────────────────────
    @objective(model, Min, 0)

    # ── Solve ────────────────────────────────────────────────────────────
    start = time()
    optimize!(model)
    solveTime = time() - start

    # ── Extract solution ─────────────────────────────────────────────────
    isOptimal = primal_status(model) == MOI.FEASIBLE_POINT

    solution = fill(-1, n, m)
    if isOptimal
        for i in 1:n, j in 1:m
            for k in 1:K
                if JuMP.value(x[i, j, k]) > TOL
                    solution[i, j] = k
                    break
                end
            end
        end
    end

    return isOptimal, solveTime, solution
end


# ═════════════════════════════════════════════════════════════════════════════
#  Solution verification
# ═════════════════════════════════════════════════════════════════════════════

"""
Verify that `solution` satisfies all four Galaxies rules.

Returns `true` if valid, `false` otherwise.
"""
function verifySolution(grid, dots, solution::Matrix{Int})

    n, m = grid
    K = length(dots)

    # ── Every cell must be assigned to a valid galaxy ────────────────────
    for i in 1:n, j in 1:m
        if solution[i, j] < 1 || solution[i, j] > K
            return false
        end
    end

    # ── Anchor cells must belong to their galaxy ─────────────────────────
    for k in 1:K
        for (ai, aj) in getAnchorCells(dots[k][1], dots[k][2], n, m)
            if solution[ai, aj] != k
                return false
            end
        end
    end

    # ── 180° rotational symmetry ─────────────────────────────────────────
    for k in 1:K
        p, q = dots[k]
        for i in 1:n, j in 1:m
            if solution[i, j] != k
                continue
            end
            img = symmetricImage(i, j, p, q, n, m)
            if img === nothing || solution[img[1], img[2]] != k
                return false
            end
        end
    end

    # ── Connectivity of each galaxy ──────────────────────────────────────
    for k in 1:K
        region = Set{Tuple{Int,Int}}()
        for i in 1:n, j in 1:m
            if solution[i, j] == k
                push!(region, (i, j))
            end
        end
        if isempty(region)
            return false
        end
        reachable = bfsReachable(first(region), region, n, m)
        if length(reachable) != length(region)
            return false
        end
    end

    return true
end


# ═════════════════════════════════════════════════════════════════════════════
#  Heuristic solver
# ═════════════════════════════════════════════════════════════════════════════

"""
Heuristically solve a Galaxies instance via constraint propagation.

Strategy:
1. Assign anchor cells.
2. Propagate: if a cell's symmetric image is already taken by another
   galaxy, eliminate that galaxy from the cell's candidates.
3. If only one candidate remains, assign the cell (and its symmetric pair).
4. If stuck, greedily assign the cell with fewest candidates.
5. Repeat until solved or contradiction.

Returns:
- isSolved: true if a valid complete solution was found
- solution: n×m Matrix{Int}
"""
function heuristicSolve(grid, dots)

    n, m = grid
    K = length(dots)
    solution = zeros(Int, n, m)

    # Candidate sets: which galaxies each cell could belong to
    candidates = [Set{Int}() for _ in 1:n, _ in 1:m]
    for k in 1:K
        p, q = dots[k]
        for i in 1:n, j in 1:m
            if symmetricImage(i, j, p, q, n, m) !== nothing
                push!(candidates[i, j], k)
            end
        end
    end

    # ── Step 1: assign anchor cells ──────────────────────────────────────
    for k in 1:K
        for (ai, aj) in getAnchorCells(dots[k][1], dots[k][2], n, m)
            solution[ai, aj] = k
            candidates[ai, aj] = Set([k])
        end
    end

    # ── Step 2 & 3: propagation loop ─────────────────────────────────────
    maxIter = n * m * 10
    for _ in 1:maxIter
        changed = false

        for i in 1:n, j in 1:m
            if solution[i, j] != 0
                continue
            end

            # Remove galaxies whose symmetric image is already taken
            for k in collect(candidates[i, j])
                p, q = dots[k]
                img = symmetricImage(i, j, p, q, n, m)
                if img === nothing
                    delete!(candidates[i, j], k)
                    changed = true
                    continue
                end
                si, sj = img
                # If the symmetric cell is assigned to a different galaxy
                if solution[si, sj] != 0 && solution[si, sj] != k
                    delete!(candidates[i, j], k)
                    changed = true
                end
            end

            # Forced assignment: only one candidate left
            if length(candidates[i, j]) == 1
                k = first(candidates[i, j])
                solution[i, j] = k
                changed = true

                # Also assign the symmetric cell
                p, q = dots[k]
                img = symmetricImage(i, j, p, q, n, m)
                if img !== nothing
                    si, sj = img
                    if solution[si, sj] == 0
                        solution[si, sj] = k
                        candidates[si, sj] = Set([k])
                        changed = true
                    end
                end

            elseif isempty(candidates[i, j])
                # Contradiction — no valid galaxy for this cell
                return false, solution
            end
        end

        if !changed
            break
        end
    end

    # ── Step 4: greedy assignment for remaining cells ────────────────────
    unassigned = [(i, j) for i in 1:n, j in 1:m if solution[i, j] == 0]

    # Sort by fewest candidates first (most constrained)
    sort!(unassigned, by = c -> length(candidates[c[1], c[2]]))

    for (i, j) in unassigned
        if solution[i, j] != 0
            continue
        end

        for k in candidates[i, j]
            p, q = dots[k]
            img = symmetricImage(i, j, p, q, n, m)
            if img === nothing
                continue
            end
            si, sj = img

            # Can we assign both the cell and its symmetric image?
            canAssign = (solution[si, sj] == 0 || solution[si, sj] == k)
            canAssign = canAssign && (solution[i, j] == 0 || solution[i, j] == k)

            if canAssign
                solution[i, j] = k
                solution[si, sj] = k
                candidates[i, j] = Set([k])
                candidates[si, sj] = Set([k])
                break
            end
        end
    end

    isSolved = verifySolution(grid, dots, solution)
    return isSolved, solution
end


# ═════════════════════════════════════════════════════════════════════════════
#  Batch dataset solver
# ═════════════════════════════════════════════════════════════════════════════

"""
Solve every instance in `../data/` with both CPLEX and the heuristic.

Results are written to `../res/cplex/` and `../res/heuristique/`.
Already-solved instances are skipped.
"""
function solveDataSet()

    dataFolder = "../data/"
    resFolder  = "../res/"

    resolutionMethod = ["cplex", "heuristique"]
    resolutionFolder = resFolder .* resolutionMethod

    for folder in resolutionFolder
        if !isdir(folder)
            mkpath(folder)
        end
    end

    global isOptimal = false
    global solveTime = -1

    for file in filter(x -> occursin(".txt", x), readdir(dataFolder))

        println("-- Resolution of ", file)
        grid, dots, _ = readInputFile(dataFolder * file)

        for methodId in 1:length(resolutionMethod)

            outputFile = resolutionFolder[methodId] * "/" * file

            if !isfile(outputFile)
                fout = open(outputFile, "w")

                resolutionTime = -1.0
                isOptimal = false

                if resolutionMethod[methodId] == "cplex"

                    isOptimal, resolutionTime, sol = cplexSolve(grid, dots)

                    if isOptimal
                        writeSolution(fout, sol)
                    end

                else
                    # Heuristic: retry until solved or 100 s elapsed
                    startingTime = time()
                    resolutionTime = 0.0
                    sol = nothing

                    while !isOptimal && resolutionTime < 10.0
                        isOptimal, sol = heuristicSolve(grid, dots)
                        resolutionTime = time() - startingTime
                    end

                    if isOptimal && sol !== nothing
                        writeSolution(fout, sol)
                    end
                end

                println(fout, "solveTime = ", resolutionTime)
                println(fout, "isOptimal = ", isOptimal)
                close(fout)
            else
                # Read results from existing file
                isOptimal = false
                resolutionTime = -1.0
                for line in readlines(outputFile)
                    if startswith(line, "solveTime")
                        resolutionTime = parse(Float64, split(line, "=")[2])
                    elseif startswith(line, "isOptimal")
                        isOptimal = parse(Bool, strip(split(line, "=")[2]))
                    end
                end
            end

            # Display results
            println(resolutionMethod[methodId], " optimal: ", isOptimal)
            println(resolutionMethod[methodId], " time: ",
                    string(round(resolutionTime, sigdigits = 3)), "s\n")
        end
    end
end