# This file contains methods to generate a data set of Mosaic instances
include("io.jl")

"""
Generate a random Mosaic instance of size n x m with a given clue density.

The approach:
1. Generate a random black/white grid (the "solution").
2. Compute the clue value for every cell (count of black cells in its 3x3 neighbourhood).
3. Randomly keep only a fraction `density` of these clues to form the puzzle.

Arguments:
- n: number of rows
- m: number of columns (default = n for square grids)
- density: fraction in [0, 1] of cells that will contain a clue

Return:
- grid: n x m matrix with clue values (-1 for cells without a clue)
- solution: n x m matrix with 0 (white) and 1 (black)
"""
function generateInstance(n::Int64, m::Int64, density::Float64)

    # Step 1: Generate a random solution grid
    solution = rand(0:1, n, m)
    
    # Step 2: Compute the full clue grid (every cell gets a clue)
    fullClues = fill(0, n, m)
    for i in 1:n
        for j in 1:m
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
            fullClues[i, j] = count
        end
    end
    
    # Step 3: Keep only `density` fraction of the clues
    grid = fill(-1, n, m)
    for i in 1:n
        for j in 1:m
            if rand() < density
                grid[i, j] = fullClues[i, j]
            end
        end
    end
    
    return grid, solution
end

# Convenience: square grid
function generateInstance(n::Int64, density::Float64)
    return generateInstance(n, n, density)
end


"""
Generate all the instances for the Mosaic puzzle.

Generates instances of various sizes and densities.
A grid is generated only if the corresponding output file does not already exist.
"""
function generateDataSet()

    dataFolder = "../data/"

    # Create the data folder if it does not exist
    if !isdir(dataFolder)
        mkdir(dataFolder)
    end

    # For each grid size considered
    for gridSize in [3, 5, 7, 10, 15, 20]

        # For each grid density considered
        for density in [0.3, 0.5, 0.7, 0.9]

            # Generate 10 instances per (size, density) combination
            for instance in 1:10

                fileName = dataFolder * "mosaic_$(gridSize)x$(gridSize)_d$(density)_$(instance).txt"

                if !isfile(fileName)
                    println("-- Generating file ", fileName)
                    grid, _ = generateInstance(gridSize, density)
                    saveInstance(grid, fileName)
                end
            end
        end
    end
end
