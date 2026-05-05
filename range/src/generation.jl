# This file contains methods to generate a data set of Range instances
include("io.jl")

"""
Generate a random Range instance of size n x m with a given clue density.

Strategy:
1. Randomly place black cells respecting the no-adjacency rule.
2. Verify white connectivity (BFS).
3. Compute the visibility value for each white cell.
4. Keep only `density` fraction of the clue values.

Arguments:
- n: number of rows
- m: number of columns
- density: fraction in [0,1] of white cells that will contain a clue

Return:
- grid: n x m matrix with clue values (-1 for cells without a clue)
- solution: n x m matrix with 0 (white) and 1 (black)
"""
function generateInstance(n::Int64, m::Int64, density::Float64)

    maxAttempts = 1000
    
    for _ in 1:maxAttempts
        # Step 1: Generate random black cells with no-adjacency constraint
        solution = zeros(Int, n, m)
        blackDensity = 0.15 + 0.1 * rand()  # ~15-25% black cells
        
        # Randomly try to place black cells
        cells = [(i, j) for i in 1:n for j in 1:m]
        shuffle!(cells)
        
        for (i, j) in cells
            if rand() < blackDensity
                # Check no-adjacency constraint
                canPlace = true
                for (di, dj) in [(-1,0),(1,0),(0,-1),(0,1)]
                    ni, nj = i + di, j + dj
                    if 1 <= ni <= n && 1 <= nj <= m && solution[ni, nj] == 1
                        canPlace = false
                        break
                    end
                end
                if canPlace
                    solution[i, j] = 1
                end
            end
        end
        
        # Step 2: Check white connectivity via BFS
        if !isWhiteConnected(solution)
            continue
        end
        
        # Step 3: Compute visibility for each white cell
        fullClues = fill(-1, n, m)
        for i in 1:n
            for j in 1:m
                if solution[i, j] == 0  # white cell
                    fullClues[i, j] = computeVisibility(solution, i, j)
                end
            end
        end
        
        # Step 4: Keep only `density` fraction of clues
        grid = fill(-1, n, m)
        for i in 1:n
            for j in 1:m
                if fullClues[i, j] != -1 && rand() < density
                    grid[i, j] = fullClues[i, j]
                end
            end
        end
        
        # Ensure at least one clue exists
        if all(grid .== -1)
            # Place at least one clue
            for i in 1:n, j in 1:m
                if fullClues[i, j] != -1
                    grid[i, j] = fullClues[i, j]
                    break
                end
            end
        end
        
        return grid, solution
    end
    
    error("Failed to generate a valid Range instance after $maxAttempts attempts")
end

# Convenience: square grid
function generateInstance(n::Int64, density::Float64)
    return generateInstance(n, n, density)
end


"""
Check if all white cells in the grid form a single connected component.
Uses BFS from the first white cell found.
"""
function isWhiteConnected(solution::Matrix{Int})
    n, m = size(solution)
    
    # Find the first white cell
    startCell = nothing
    whiteCount = 0
    for i in 1:n, j in 1:m
        if solution[i, j] == 0
            whiteCount += 1
            if startCell === nothing
                startCell = (i, j)
            end
        end
    end
    
    if whiteCount == 0
        return true  # trivially connected
    end
    
    # BFS
    visited = falses(n, m)
    queue = [startCell]
    visited[startCell[1], startCell[2]] = true
    reachable = 1
    
    while !isempty(queue)
        (ci, cj) = popfirst!(queue)
        for (di, dj) in [(-1,0),(1,0),(0,-1),(0,1)]
            ni, nj = ci + di, cj + dj
            if 1 <= ni <= n && 1 <= nj <= m && !visited[ni, nj] && solution[ni, nj] == 0
                visited[ni, nj] = true
                push!(queue, (ni, nj))
                reachable += 1
            end
        end
    end
    
    return reachable == whiteCount
end


"""
Compute the visibility value for a white cell at (r, c).
Counts the cell itself plus all white cells visible in 4 cardinal directions
until hitting a black cell or the grid boundary.
"""
function computeVisibility(solution::Matrix{Int}, r::Int, c::Int)
    n, m = size(solution)
    count = 1  # count the cell itself
    
    # Right
    for d in 1:(m - c)
        if solution[r, c + d] == 1; break; end
        count += 1
    end
    
    # Left
    for d in 1:(c - 1)
        if solution[r, c - d] == 1; break; end
        count += 1
    end
    
    # Down
    for d in 1:(n - r)
        if solution[r + d, c] == 1; break; end
        count += 1
    end
    
    # Up
    for d in 1:(r - 1)
        if solution[r - d, c] == 1; break; end
        count += 1
    end
    
    return count
end


"""
Generate all the instances for the Range puzzle.

Remark: a grid is generated only if the corresponding output file does not already exist.
"""
function generateDataSet()

    dataFolder = "../data/"

    # Create the data folder if it does not exist
    if !isdir(dataFolder)
        mkdir(dataFolder)
    end

    # For each grid size considered
    for (nRows, nCols) in [(5, 5), (6, 9), (7, 7), (8, 10), (10, 10)]

        # For each clue density considered
        for density in [0.3, 0.5, 0.7]

            # Generate 10 instances per combination
            for instance in 1:10

                fileName = dataFolder * "range_$(nCols)x$(nRows)_d$(density)_$(instance).txt"

                if !isfile(fileName)
                    println("-- Generating file ", fileName)
                    grid, _ = generateInstance(nRows, nCols, density)
                    saveInstance(grid, fileName)
                end
            end
        end
    end
end


# Need Random for shuffle
using Random
