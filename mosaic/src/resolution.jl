# This file contains methods to solve a Mosaic instance (with CPLEX and heuristically)
using CPLEX

include("generation.jl")

TOL = 0.00001

"""
Solve a Mosaic instance with CPLEX using Integer Linear Programming.

Mathematical model:
- Decision variables: x[i,j] ∈ {0,1} (1 = black, 0 = white)
- Constraints: For each clue v at position (i,j), the sum of x values
  in the 3×3 neighbourhood of (i,j) must equal v.
- Objective: constant (feasibility problem)

Argument:
- grid: n x m matrix with clue values (-1 for empty cells)

Return:
- isOptimal: true if a feasible solution was found
- solveTime: resolution time in seconds
- solution: n x m matrix with 0 (white) and 1 (black)
"""
function cplexSolve(grid::Matrix{Int})

    n, m = size(grid)

    # Create the model
    model = Model(CPLEX.Optimizer)

    # Suppress CPLEX output for cleaner console
    set_silent(model)

    # Decision variables: x[i,j] = 1 if cell (i,j) is black
    @variable(model, x[1:n, 1:m], Bin)

    # Constraints: for each cell with a clue, the sum of its 3x3 neighbourhood must equal the clue
    for i in 1:n
        for j in 1:m
            if grid[i, j] != -1
                # Build the list of neighbours in the 3x3 box around (i,j)
                @constraint(model,
                    sum(x[k, l]
                        for k in max(1, i-1):min(n, i+1)
                        for l in max(1, j-1):min(m, j+1)
                    ) == grid[i, j]
                )
            end
        end
    end

    # Objective: constant (this is a feasibility problem)
    @objective(model, Min, 0)

    # Start chronometer
    start = time()

    # Solve
    optimize!(model)

    solveTime = time() - start

    # Extract solution
    isOptimal = primal_status(model) == MOI.FEASIBLE_POINT

    solution = fill(-1, n, m)
    if isOptimal
        for i in 1:n
            for j in 1:m
                if JuMP.value(x[i, j]) > TOL
                    solution[i, j] = 1
                else
                    solution[i, j] = 0
                end
            end
        end
    end

    return isOptimal, solveTime, solution
end


"""
Heuristically solve a Mosaic instance using constraint propagation.

Strategy:
1. Build a "remaining" counter for each clue cell: how many more blacks are needed
   minus how many unknown neighbours remain.
2. If a clue's remaining count equals its unknown neighbours → all unknowns must be black.
3. If a clue's remaining count is 0 → all unknowns must be white.
4. Repeat until no more progress can be made.
5. If stuck, make a random guess on the most constrained unknown cell.

Argument:
- grid: n x m matrix with clue values (-1 for empty cells)

Return:
- isSolved: true if the grid is completely and validly solved
- solution: n x m matrix with 0 (white) and 1 (black)
"""
function heuristicSolve(grid::Matrix{Int})

    n, m = size(grid)
    
    # Initialize all cells as unknown (-1)
    solution = fill(-1, n, m)
    
    maxIterations = n * m * 10
    iteration = 0
    progress = true
    
    while progress && iteration < maxIterations
        progress = false
        iteration += 1
        
        for i in 1:n
            for j in 1:m
                if grid[i, j] == -1
                    continue  # No clue here
                end
                
                clueValue = grid[i, j]
                
                # Count known blacks and unknowns in the neighbourhood
                blackCount = 0
                unknownCount = 0
                unknownCells = Tuple{Int, Int}[]
                
                for di in -1:1
                    for dj in -1:1
                        ni = i + di
                        nj = j + dj
                        if 1 <= ni <= n && 1 <= nj <= m
                            if solution[ni, nj] == 1
                                blackCount += 1
                            elseif solution[ni, nj] == -1
                                unknownCount += 1
                                push!(unknownCells, (ni, nj))
                            end
                        end
                    end
                end
                
                remaining = clueValue - blackCount
                
                # If the number of remaining blacks equals the number of unknowns,
                # all unknowns must be black
                if remaining == unknownCount && unknownCount > 0
                    for (ci, cj) in unknownCells
                        solution[ci, cj] = 1
                    end
                    progress = true
                end
                
                # If we already have enough blacks, all unknowns must be white
                if remaining == 0 && unknownCount > 0
                    for (ci, cj) in unknownCells
                        solution[ci, cj] = 0
                    end
                    progress = true
                end
            end
        end
    end
    
    # Fill remaining unknowns with a random guess (greedy fallback)
    for i in 1:n
        for j in 1:m
            if solution[i, j] == -1
                solution[i, j] = rand(0:1)
            end
        end
    end
    
    # Verify the solution
    isSolved = verifySolution(grid, solution)
    
    return isSolved, solution
end


"""
Verify that a solution satisfies all Mosaic clues.

Arguments:
- grid: the puzzle grid (-1 for no clue, integer for clue value)
- solution: the proposed solution (0 = white, 1 = black)

Return: true if all clues are satisfied
"""
function verifySolution(grid::Matrix{Int}, solution::Matrix{Int})
    n, m = size(grid)
    
    for i in 1:n
        for j in 1:m
            if grid[i, j] != -1
                # Count black cells in 3x3 neighbourhood
                count = 0
                for di in -1:1
                    for dj in -1:1
                        ni = i + di
                        nj = j + dj
                        if 1 <= ni <= n && 1 <= nj <= m
                            count += solution[ni, nj]
                        end
                    end
                end
                if count != grid[i, j]
                    return false
                end
            end
        end
    end
    return true
end


"""
Solve all the instances contained in "../data" through CPLEX and heuristics

The results are written in "../res/cplex" and "../res/heuristic"

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
                    
                    # While the grid is not solved and less than 100 seconds are elapsed
                    while !isOptimal && resolutionTime < 100
                        
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
