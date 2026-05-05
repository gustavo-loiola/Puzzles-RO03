# This file contains methods to solve a Range instance (with CPLEX and heuristically)
using CPLEX

include("generation.jl")

TOL = 0.00001

"""
Solve a Range instance with CPLEX using the full ILP formulation.

The model implements:
  (R1) Clue cells are white:  b[i,j] = 0  ∀ (i,j) ∈ C
  (R2) No two adjacent black: b[i,j] + b[i',j'] ≤ 1  ∀ adjacent pairs
  (R3a) Visibility definition via line-of-sight binary variables
  (R3b) Total visibility = clue value
  (R4a) Flow balance at source
  (R4b) Flow balance at every other cell
  (R4c) Flow capacity through white cells only

Arguments:
- grid: n x m matrix with clue values (-1 for empty cells)

Return:
- isOptimal: true if a feasible solution was found
- solveTime: resolution time in seconds
- solution: n x m matrix with 0 (white) and 1 (black)
"""
function cplexSolve(grid::Matrix{Int})

    n, m = size(grid)
    M = n * m  # big-M constant

    # ─────────────────────────────────────────────────────────────────────────
    # Identify clue cells and choose a flow source
    # ─────────────────────────────────────────────────────────────────────────
    clueCells = Tuple{Int,Int}[]
    for i in 1:n
        for j in 1:m
            if grid[i, j] != -1
                push!(clueCells, (i, j))
            end
        end
    end

    # Source = first clue cell (guaranteed white by R1)
    if isempty(clueCells)
        # No clues: trivial instance (all white is a solution)
        return true, 0.0, zeros(Int, n, m)
    end
    sr, sc = clueCells[1]

    # ─────────────────────────────────────────────────────────────────────────
    # Build the model
    # ─────────────────────────────────────────────────────────────────────────
    model = Model(CPLEX.Optimizer)
    set_silent(model)
    set_time_limit_sec(model, 60.0)  # 60s time limit per instance

    # ── Primary variables ────────────────────────────────────────────────────
    # b[i,j] = 1 if black, 0 if white
    @variable(model, b[1:n, 1:m], Bin)

    # ── (R1) Clue cells are white ────────────────────────────────────────────
    for (i, j) in clueCells
        @constraint(model, b[i, j] == 0)
    end

    # ── (R2) No two adjacent black cells ─────────────────────────────────────
    for i in 1:n
        for j in 1:(m-1)
            @constraint(model, b[i, j] + b[i, j+1] <= 1)
        end
    end
    for i in 1:(n-1)
        for j in 1:m
            @constraint(model, b[i, j] + b[i+1, j] <= 1)
        end
    end

    # ── (R3) Visibility constraints ──────────────────────────────────────────
    # For each clue cell, create visibility variables and constraints
    # We store them in dictionaries keyed by (r, c, direction, d)
    
    for (r, c) in clueCells
        v = grid[r, c]  # clue value

        # Collect visibility variable references for the total-visibility constraint
        visVars = JuMP.VariableRef[]

        # ── Right direction: d = 1, ..., m - c ──────────────────────────────
        for d in 1:(m - c)
            vis = @variable(model, binary = true,
                            base_name = "visR_$(r)_$(c)_$(d)")
            push!(visVars, vis)

            # Any black cell on the path forces vis = 0
            for k in 1:d
                @constraint(model, vis <= 1 - b[r, c + k])
            end
            # All white on the path forces vis = 1
            @constraint(model, vis >= 1 - sum(b[r, c + k] for k in 1:d))
        end

        # ── Left direction: d = 1, ..., c - 1 ───────────────────────────────
        for d in 1:(c - 1)
            vis = @variable(model, binary = true,
                            base_name = "visL_$(r)_$(c)_$(d)")
            push!(visVars, vis)

            for k in 1:d
                @constraint(model, vis <= 1 - b[r, c - k])
            end
            @constraint(model, vis >= 1 - sum(b[r, c - k] for k in 1:d))
        end

        # ── Down direction: d = 1, ..., n - r ───────────────────────────────
        for d in 1:(n - r)
            vis = @variable(model, binary = true,
                            base_name = "visD_$(r)_$(c)_$(d)")
            push!(visVars, vis)

            for k in 1:d
                @constraint(model, vis <= 1 - b[r + k, c])
            end
            @constraint(model, vis >= 1 - sum(b[r + k, c] for k in 1:d))
        end

        # ── Up direction: d = 1, ..., r - 1 ─────────────────────────────────
        for d in 1:(r - 1)
            vis = @variable(model, binary = true,
                            base_name = "visU_$(r)_$(c)_$(d)")
            push!(visVars, vis)

            for k in 1:d
                @constraint(model, vis <= 1 - b[r - k, c])
            end
            @constraint(model, vis >= 1 - sum(b[r - k, c] for k in 1:d))
        end

        # ── (R3b) Total visibility = clue value ─────────────────────────────
        # 1 (self) + sum of all vis variables = v
        @constraint(model, 1 + sum(visVars) == v)
    end

    # ── (R4) White connectivity via single-commodity network flow ────────────
    # Directed flow variables on every adjacent pair (both directions)
    # Neighbours offsets
    offsets = [(-1, 0), (1, 0), (0, -1), (0, 1)]

    # Create flow variables: f[i, j, dir] where dir indexes the 4 directions
    # We use a dictionary for sparse storage (only valid edges)
    flowVars = Dict{Tuple{Int,Int,Int,Int}, JuMP.VariableRef}()

    for i in 1:n
        for j in 1:m
            for (di, dj) in offsets
                ni, nj = i + di, j + dj
                if 1 <= ni <= n && 1 <= nj <= m
                    fvar = @variable(model, lower_bound = 0,
                                     base_name = "f_$(i)_$(j)_$(ni)_$(nj)")
                    flowVars[(i, j, ni, nj)] = fvar

                    # (R4c) Flow capacity: flow only through white cells
                    @constraint(model, fvar <= M * (1 - b[i, j]))
                    @constraint(model, fvar <= M * (1 - b[ni, nj]))
                end
            end
        end
    end

    # Helper: get outflow - inflow for cell (i,j)
    function netOutflow(i, j)
        outflow = AffExpr(0.0)
        inflow  = AffExpr(0.0)
        for (di, dj) in offsets
            ni, nj = i + di, j + dj
            if 1 <= ni <= n && 1 <= nj <= m
                add_to_expression!(outflow, flowVars[(i, j, ni, nj)])
                add_to_expression!(inflow,  flowVars[(ni, nj, i, j)])
            end
        end
        return outflow - inflow
    end

    # (R4a) Flow balance at source s = (sr, sc)
    # net outflow = sum over all other cells of (1 - b[i,j])
    totalOtherWhite = AffExpr(0.0)
    for i in 1:n
        for j in 1:m
            if !(i == sr && j == sc)
                add_to_expression!(totalOtherWhite, 1.0 - b[i, j])
            end
        end
    end
    @constraint(model, netOutflow(sr, sc) == totalOtherWhite)

    # (R4b) Flow balance at every non-source cell
    for i in 1:n
        for j in 1:m
            if !(i == sr && j == sc)
                # inflow - outflow = 1 - b[i,j]  (i.e., -netOutflow = 1 - b)
                @constraint(model, -netOutflow(i, j) == 1 - b[i, j])
            end
        end
    end

    # ── Objective: feasibility ───────────────────────────────────────────────
    @objective(model, Min, 0)

    # ── Solve ────────────────────────────────────────────────────────────────
    start = time()
    optimize!(model)
    solveTime = time() - start

    # ── Extract solution ─────────────────────────────────────────────────────
    isOptimal = primal_status(model) == MOI.FEASIBLE_POINT

    solution = fill(-1, n, m)
    if isOptimal
        for i in 1:n
            for j in 1:m
                if JuMP.value(b[i, j]) > TOL
                    solution[i, j] = 1  # black
                else
                    solution[i, j] = 0  # white
                end
            end
        end
    end

    return isOptimal, solveTime, solution
end


"""
Heuristically solve a Range instance using constraint propagation.

Strategy:
1. Mark all clue cells as definitely white.
2. For cells whose visibility number already matches the
   max possible reach in all directions → no blacks needed nearby.
3. For cells where the required visibility is small → try to
   force nearby cells to black.
4. Iterate until no progress; fall back to random guesses.

Arguments:
- grid: n x m matrix with clue values (-1 for empty cells)

Return:
- isSolved: true if the grid is completely and validly solved
- solution: n x m matrix with 0 (white) and 1 (black)
"""
function heuristicSolve(grid::Matrix{Int})

    n, m = size(grid)
    # -1 = unknown, 0 = white, 1 = black
    solution = fill(-1, n, m)

    # Step 1: clue cells are white
    for i in 1:n
        for j in 1:m
            if grid[i, j] != -1
                solution[i, j] = 0
            end
        end
    end

    maxIter = n * m * 20
    progress = true
    iter = 0

    while progress && iter < maxIter
        progress = false
        iter += 1

        for i in 1:n
            for j in 1:m
                if grid[i, j] == -1 || solution[i, j] != 0
                    continue
                end

                v = grid[i, j]

                # Count how many cells are definitely visible (known white on the ray)
                # and how many are unknown
                definiteVis = 1  # self
                unknownCells = Tuple{Int,Int}[]

                for (di, dj) in [(0,1),(0,-1),(1,0),(-1,0)]
                    d = 1
                    while true
                        ni, nj = i + di * d, j + dj * d
                        if !(1 <= ni <= n && 1 <= nj <= m)
                            break
                        end
                        if solution[ni, nj] == 1
                            break  # hit a known black cell
                        elseif solution[ni, nj] == 0
                            definiteVis += 1
                        else  # unknown
                            push!(unknownCells, (ni, nj))
                            # We stop counting definite visibility here
                            break
                        end
                        d += 1
                    end
                end

                # If definite visibility already equals the clue,
                # all unknown cells at the boundary of rays should be black
                if definiteVis == v
                    for (ui, uj) in unknownCells
                        # Check no-adjacency before placing black
                        canPlace = true
                        for (di2, dj2) in [(-1,0),(1,0),(0,-1),(0,1)]
                            ni2, nj2 = ui + di2, uj + dj2
                            if 1 <= ni2 <= n && 1 <= nj2 <= m && solution[ni2, nj2] == 1
                                canPlace = false
                                break
                            end
                        end
                        if canPlace && solution[ui, uj] == -1
                            solution[ui, uj] = 1
                            progress = true
                        end
                    end
                end
            end
        end

        # After constraint propagation pass, try to set remaining unknowns to white
        # if forced by adjacency to existing blacks
        for i in 1:n
            for j in 1:m
                if solution[i, j] == -1
                    # If any neighbour is black, this cell cannot be black
                    for (di, dj) in [(-1,0),(1,0),(0,-1),(0,1)]
                        ni, nj = i + di, j + dj
                        if 1 <= ni <= n && 1 <= nj <= m && solution[ni, nj] == 1
                            solution[i, j] = 0
                            progress = true
                            break
                        end
                    end
                end
            end
        end
    end

    # Fill remaining unknowns: try white first (safer for connectivity)
    for i in 1:n
        for j in 1:m
            if solution[i, j] == -1
                solution[i, j] = 0
            end
        end
    end

    # Verify the solution
    isSolved = verifySolution(grid, solution)

    return isSolved, solution
end


"""
Verify that a solution satisfies all Range rules.

Arguments:
- grid: the puzzle grid (-1 for no clue, positive integer for clue)
- solution: the proposed solution (0=white, 1=black)

Return: true if all 4 rules are satisfied
"""
function verifySolution(grid::Matrix{Int}, solution::Matrix{Int})
    n, m = size(grid)

    # R1: clue cells must be white
    for i in 1:n
        for j in 1:m
            if grid[i, j] != -1 && solution[i, j] != 0
                return false
            end
        end
    end

    # R2: no two adjacent black cells
    for i in 1:n
        for j in 1:m
            if solution[i, j] == 1
                for (di, dj) in [(0,1),(1,0)]
                    ni, nj = i + di, j + dj
                    if 1 <= ni <= n && 1 <= nj <= m && solution[ni, nj] == 1
                        return false
                    end
                end
            end
        end
    end

    # R3: white connectivity (BFS)
    if !isWhiteConnected(solution)
        return false
    end

    # R4: visibility matches clues
    for i in 1:n
        for j in 1:m
            if grid[i, j] != -1
                vis = computeVisibility(solution, i, j)
                if vis != grid[i, j]
                    return false
                end
            end
        end
    end

    return true
end


"""
Solve all the instances contained in "../data" through CPLEX and heuristics

The results are written in "../res/cplex" and "../res/heuristique"

Remark: If an instance has previously been solved (either by cplex or the heuristic) it will not be solved again
"""
function solveDataSet()

    dataFolder = "../data/"
    resFolder = "../res/"

    # Array which contains the name of the resolution methods
    resolutionMethod = ["cplex", "heuristique"]

    # Array which contains the result folder of each resolution method
    resolutionFolder = resFolder .* resolutionMethod

    # Create each result folder if it does not exist
    for folder in resolutionFolder
        if !isdir(folder)
            mkpath(folder)
        end
    end
            
    global isOptimal = false
    global solveTime = -1

    # For each instance
    for file in filter(x->occursin(".txt", x), readdir(dataFolder))  
        
        println("-- Resolution of ", file)
        grid, _ = readInputFile(dataFolder * file)
        
        # For each resolution method
        for methodId in 1:size(resolutionMethod, 1)
            
            outputFile = resolutionFolder[methodId] * "/" * file

            # If the instance has not already been solved by this method
            if !isfile(outputFile)
                
                fout = open(outputFile, "w")  

                resolutionTime = -1
                isOptimal = false
                
                # If the method is cplex
                if resolutionMethod[methodId] == "cplex"
                    
                    # Solve it and get the results
                    isOptimal, resolutionTime, sol = cplexSolve(grid)
                    
                    # If a solution is found, write it
                    if isOptimal
                        writeSolution(fout, sol)
                    end

                # If the method is the heuristic
                else
                    
                    # Start a chronometer 
                    startingTime = time()
                    resolutionTime = 0.0
                    sol = nothing
                    
                    # While the grid is not solved and less than 10 seconds are elapsed
                    while !isOptimal && resolutionTime < 10
                        
                        # Solve it and get the results
                        isOptimal, sol = heuristicSolve(grid)

                        # Update the chronometer
                        resolutionTime = time() - startingTime
                        
                    end

                    # Write the solution (if any)
                    if isOptimal && sol !== nothing
                        writeSolution(fout, sol)
                    end 
                end

                println(fout, "solveTime = ", resolutionTime) 
                println(fout, "isOptimal = ", isOptimal)
                close(fout)
            end


            # Display the results obtained with the method on the current instance
            include(abspath(outputFile))
            println(resolutionMethod[methodId], " optimal: ", isOptimal)
            println(resolutionMethod[methodId], " time: " * string(round(solveTime, sigdigits=2)) * "s\n")
        end         
    end 
end
