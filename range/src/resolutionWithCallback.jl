# ─────────────────────────────────────────────────────────────────────────────
#  resolutionWithCallback.jl
#
#  Alternative ILP solver for the Range puzzle.
#
#  Instead of modelling white-connectivity with a single-commodity flow
#  (as done in resolution.jl), this version uses CPLEX Lazy-Constraint
#  Callbacks: at every integer-feasible candidate the solver finds, we
#  detect disconnected white components and dynamically add a separator
#  cut that forbids them.
#
#  Compared with the flow formulation, this approach:
#    + has no big-M and yields a tighter LP relaxation
#    + has fewer continuous variables (no flow vars)
#    - requires a callback (slightly more code complexity)
#    - may add many cuts for hard instances
#
#  ── Mathematical idea of the cut ───────────────────────────────────────────
#  Let s be the source (any clue cell, guaranteed white).  Suppose the
#  current candidate has a connected component of white cells S that does
#  NOT contain s.  Let N(S) = { cells outside S adjacent to some cell of S }.
#  In the candidate, every cell of S is white (b=0) and every cell of N(S)
#  is black (b=1) — otherwise S would be reachable from s.  We forbid
#  precisely that pattern with the separator inequality:
#
#        sum_{(i,j) ∈ S}    b[i,j]      +
#        sum_{(i,j) ∈ N(S)} (1 - b[i,j]) ≥ 1
#
#  Either some cell of S becomes black (component vanishes) or some cell
#  of N(S) becomes white (component gets connected outward).
# ─────────────────────────────────────────────────────────────────────────────

using CPLEX
using JuMP

include("resolution.jl")   # reuses readInputFile, verifySolution,
                           # isWhiteConnected, computeVisibility,
                           # heuristicSolve, displayGrid, displaySolution


# ─────────────────────────────────────────────────────────────────────────────
#  Auxiliary BFS helpers (used inside the callback)
# ─────────────────────────────────────────────────────────────────────────────

const NEIGHBOUR_OFFSETS = ((-1, 0), (1, 0), (0, -1), (0, 1))

"""
BFS through white cells (`is_black[i,j] == false`) starting at `(sr, sc)`.
Returns a Boolean matrix `reachable` of the same size as `is_black`.
"""
function bfsWhiteReachable(is_black::AbstractMatrix{Bool}, sr::Int, sc::Int)
    n, m = size(is_black)
    reachable = falses(n, m)

    if is_black[sr, sc]
        return reachable      # source itself is black ⇒ nothing reachable
    end

    reachable[sr, sc] = true
    queue = [(sr, sc)]

    while !isempty(queue)
        i, j = popfirst!(queue)
        for (di, dj) in NEIGHBOUR_OFFSETS
            ni, nj = i + di, j + dj
            if 1 <= ni <= n && 1 <= nj <= m &&
               !is_black[ni, nj] && !reachable[ni, nj]
                reachable[ni, nj] = true
                push!(queue, (ni, nj))
            end
        end
    end
    return reachable
end


"""
Given an integer candidate `is_black`, return the list of all maximal
connected components of white cells that do NOT contain the source
`(sr, sc)`.  Each component is returned as a `Vector{Tuple{Int,Int}}`.
"""
function disconnectedWhiteComponents(is_black::AbstractMatrix{Bool},
                                     sr::Int, sc::Int)
    n, m = size(is_black)
    reachable  = bfsWhiteReachable(is_black, sr, sc)
    visited    = copy(reachable)        # source-component is "already seen"
    components = Vector{Vector{Tuple{Int,Int}}}()

    for i in 1:n, j in 1:m
        if is_black[i, j] || visited[i, j]
            continue
        end
        # New disconnected white component — BFS to enumerate it
        comp = Tuple{Int,Int}[]
        queue = [(i, j)]
        visited[i, j] = true
        while !isempty(queue)
            ci, cj = popfirst!(queue)
            push!(comp, (ci, cj))
            for (di, dj) in NEIGHBOUR_OFFSETS
                ni, nj = ci + di, cj + dj
                if 1 <= ni <= n && 1 <= nj <= m &&
                   !is_black[ni, nj] && !visited[ni, nj]
                    visited[ni, nj] = true
                    push!(queue, (ni, nj))
                end
            end
        end
        push!(components, comp)
    end
    return components
end


"""
Compute N(S) — the set of cells outside `S` that are 4-adjacent to some
cell of `S`.  Cells outside the grid are ignored.
"""
function neighbourhoodOfComponent(S::Vector{Tuple{Int,Int}},
                                  n::Int, m::Int)
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


# ─────────────────────────────────────────────────────────────────────────────
#  Main solver
# ─────────────────────────────────────────────────────────────────────────────

"""
Solve a Range instance using CPLEX with Lazy-Constraint callbacks for
white connectivity.

Constraints inside the model:
  (R1)  Clue cells are white
  (R2)  No two adjacent black cells
  (R3a) Visibility-ray definition variables
  (R3b) Total visibility = clue value

Connectivity (R4) is *not* in the model.  It is enforced lazily: every
time CPLEX finds an integer-feasible candidate, the callback runs a BFS;
for every white component disconnected from the source, a separator cut
is added.

Arguments:
- grid: n x m matrix with clue values (-1 for empty cells)

Return:
- isOptimal: true if a feasible solution was found
- solveTime: resolution time in seconds
- solution:  n x m matrix with 0 (white) and 1 (black)
"""
function cplexSolveWithCallback(grid::Matrix{Int})

    n, m = size(grid)

    # ─────────────────────────────────────────────────────────────────────
    # Identify clue cells and pick the flow source
    # ─────────────────────────────────────────────────────────────────────
    clueCells = Tuple{Int,Int}[]
    for i in 1:n, j in 1:m
        if grid[i, j] != -1
            push!(clueCells, (i, j))
        end
    end

    if isempty(clueCells)
        # Trivial: no clues ⇒ all-white grid is a valid solution
        return true, 0.0, zeros(Int, n, m)
    end
    sr, sc = clueCells[1]    # source = first clue cell

    # ─────────────────────────────────────────────────────────────────────
    # Build the model (no flow variables this time)
    # ─────────────────────────────────────────────────────────────────────
    model = Model(CPLEX.Optimizer)
    set_silent(model)
    set_time_limit_sec(model, 60.0)

    # ── Primary variables ────────────────────────────────────────────────
    @variable(model, b[1:n, 1:m], Bin)

    # ── (R1) Clue cells are white ────────────────────────────────────────
    for (i, j) in clueCells
        @constraint(model, b[i, j] == 0)
    end

    # ── (R2) No two adjacent black cells ─────────────────────────────────
    for i in 1:n, j in 1:(m-1)
        @constraint(model, b[i, j] + b[i, j+1] <= 1)
    end
    for i in 1:(n-1), j in 1:m
        @constraint(model, b[i, j] + b[i+1, j] <= 1)
    end

    # ── (R3) Visibility ──────────────────────────────────────────────────
    for (r, c) in clueCells
        v = grid[r, c]
        visVars = JuMP.VariableRef[]

        # Right
        for d in 1:(m - c)
            vis = @variable(model, binary = true,
                            base_name = "visR_$(r)_$(c)_$(d)")
            push!(visVars, vis)
            for k in 1:d
                @constraint(model, vis <= 1 - b[r, c + k])
            end
            @constraint(model, vis >= 1 - sum(b[r, c + k] for k in 1:d))
        end
        # Left
        for d in 1:(c - 1)
            vis = @variable(model, binary = true,
                            base_name = "visL_$(r)_$(c)_$(d)")
            push!(visVars, vis)
            for k in 1:d
                @constraint(model, vis <= 1 - b[r, c - k])
            end
            @constraint(model, vis >= 1 - sum(b[r, c - k] for k in 1:d))
        end
        # Down
        for d in 1:(n - r)
            vis = @variable(model, binary = true,
                            base_name = "visD_$(r)_$(c)_$(d)")
            push!(visVars, vis)
            for k in 1:d
                @constraint(model, vis <= 1 - b[r + k, c])
            end
            @constraint(model, vis >= 1 - sum(b[r + k, c] for k in 1:d))
        end
        # Up
        for d in 1:(r - 1)
            vis = @variable(model, binary = true,
                            base_name = "visU_$(r)_$(c)_$(d)")
            push!(visVars, vis)
            for k in 1:d
                @constraint(model, vis <= 1 - b[r - k, c])
            end
            @constraint(model, vis >= 1 - sum(b[r - k, c] for k in 1:d))
        end

        # (R3b) total visibility (incl. self) = clue value
        @constraint(model, 1 + sum(visVars) == v)
    end

    # ─────────────────────────────────────────────────────────────────────
    # (R4) Connectivity — installed as a lazy-constraint callback
    # ─────────────────────────────────────────────────────────────────────

    # Counter (for diagnostics if you want to print it later)
    cutCount = Ref(0)

    function connectivityCallback(cb_data)

        # Only act on candidate INTEGER solutions (CPLEX may invoke the
        # callback at fractional nodes too — we ignore those).
        status = callback_node_status(cb_data, model)
        if status != MOI.CALLBACK_NODE_STATUS_INTEGER
            return
        end

        # Read the current candidate values of b
        is_black = falses(n, m)
        for i in 1:n, j in 1:m
            val = callback_value(cb_data, b[i, j])
            is_black[i, j] = val > 0.5
        end

        # Find every white component disconnected from the source
        components = disconnectedWhiteComponents(is_black, sr, sc)

        if isempty(components)
            return       # candidate is connected → accept it
        end

        # Add one separator cut per disconnected component
        for S in components
            NS = neighbourhoodOfComponent(S, n, m)

            # Separator inequality:
            #   sum_{S} b + sum_{N(S)} (1 - b) ≥ 1
            con = @build_constraint(
                sum(b[ci, cj] for (ci, cj) in S) +
                sum(1 - b[ni, nj] for (ni, nj) in NS) >= 1
            )
            MOI.submit(model, MOI.LazyConstraint(cb_data), con)
            cutCount[] += 1
        end
    end

    # Register the callback. IMPORTANT for CPLEX: lazy constraints require
    # disabling certain dual-reduction presolves so that solutions discarded
    # by lazy cuts are not pre-eliminated. JuMP/CPLEX handles most of this
    # transparently, but we set the option explicitly for safety.
    set_attribute(model, MOI.LazyConstraintCallback(), connectivityCallback)

    # ── Objective: feasibility ───────────────────────────────────────────
    @objective(model, Min, 0)

    # ── Solve ────────────────────────────────────────────────────────────
    start = time()
    optimize!(model)
    solveTime = time() - start

    isOptimal = primal_status(model) == MOI.FEASIBLE_POINT

    solution = fill(-1, n, m)
    if isOptimal
        for i in 1:n, j in 1:m
            solution[i, j] = JuMP.value(b[i, j]) > TOL ? 1 : 0
        end
    end

    return isOptimal, solveTime, solution
end


# ─────────────────────────────────────────────────────────────────────────────
#  Convenience: solve every instance in ../data/ using the callback solver
#  Results are written to  ../res/cplex_callback/
# ─────────────────────────────────────────────────────────────────────────────

"""
Solve all instances in `../data/` with the callback-based CPLEX solver.
Writes one result file per instance to `../res/cplex_callback/`.

Skips instances that have already been solved (file exists).
"""
function solveDataSetWithCallback()

    dataFolder = "../data/"
    resFolder  = "../res/cplex_callback/"

    if !isdir(resFolder)
        mkpath(resFolder)
    end

    global isOptimal = false
    global solveTime = -1.0

    for file in filter(x -> occursin(".txt", x), readdir(dataFolder))

        println("-- Resolution of ", file, "  [callback]")
        grid, _ = readInputFile(dataFolder * file)

        outputFile = resFolder * file
        if isfile(outputFile)
            include(abspath(outputFile))
            println("  cplex_callback optimal: ", isOptimal)
            println("  cplex_callback time: ",
                    round(solveTime, sigdigits = 2), "s\n")
            continue
        end

        fout = open(outputFile, "w")

        isOpt, tSolve, sol = cplexSolveWithCallback(grid)

        if isOpt
            writeSolution(fout, sol)
        end

        println(fout, "solveTime = ", tSolve)
        println(fout, "isOptimal = ", isOpt)
        close(fout)

        include(abspath(outputFile))
        println("  cplex_callback optimal: ", isOptimal)
        println("  cplex_callback time: ",
                round(solveTime, sigdigits = 2), "s\n")
    end
end