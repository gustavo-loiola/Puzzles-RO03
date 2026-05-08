# Random instance generator for the Galaxies puzzle.
#
# Strategy: build a valid partition by growing 180°-symmetric regions one at a
# time, then publish the dot positions. Because every cell is added together
# with its symmetric counterpart, the resulting partition is guaranteed
# symmetric. Connectivity follows from the fact that we only ever add cells
# adjacent to the current region. The dots are produced in the project's
# doubled-coordinate convention (cell centre at (2i-1, 2j-1)).

include("io.jl")
using Random

const _GEN_OFFSETS = ((-1, 0), (1, 0), (0, -1), (0, 1))


"""
    candidate_dots_around(i, j, n, m) -> Vector{Tuple{Int,Int}}

Doubled-coordinate dot positions that sit on, or touch, cell (i,j). Includes
the cell centre, the four edges, and the four corners (clipped to the grid).
"""
function candidate_dots_around(i::Int, j::Int, n::Int, m::Int)
    cands = Tuple{Int,Int}[]
    push!(cands, (2i-1, 2j-1))                           # cell centre
    i > 1 && push!(cands, (2i-2, 2j-1))                  # edge above
    i < n && push!(cands, (2i,   2j-1))                  # edge below
    j > 1 && push!(cands, (2i-1, 2j-2))                  # edge left
    j < m && push!(cands, (2i-1, 2j))                    # edge right
    i > 1 && j > 1 && push!(cands, (2i-2, 2j-2))         # corner top-left
    i > 1 && j < m && push!(cands, (2i-2, 2j))           # corner top-right
    i < n && j > 1 && push!(cands, (2i,   2j-2))         # corner bottom-left
    i < n && j < m && push!(cands, (2i,   2j))           # corner bottom-right
    return cands
end


"""
    generateInstance(n, m) -> (n, m, dots)

Generate a random Galaxies instance on an `n × m` grid. Returns the dimensions
and a vector of dot positions in doubled coordinates.
"""
function generateInstance(n::Int, m::Int)
    assignment = zeros(Int, n, m)
    dots = Tuple{Int,Int}[]
    galaxy_id = 0

    while any(assignment .== 0)
        # Pick a random unassigned cell as the seed
        free = [(i, j) for i in 1:n for j in 1:m if assignment[i, j] == 0]
        isempty(free) && break
        seed_i, seed_j = free[rand(1:length(free))]

        # Try candidate dot positions for a galaxy anchored on this seed
        cands = candidate_dots_around(seed_i, seed_j, n, m)
        shuffle!(cands)

        placed = false
        for (dr, dc) in cands
            anchors = cells_touched_by_dot(dr, dc, n, m)
            isempty(anchors) && continue
            all(assignment[a[1], a[2]] == 0 for a in anchors) || continue

            # Open a new galaxy and seed it with all anchor cells
            galaxy_id += 1
            for (ai, aj) in anchors
                assignment[ai, aj] = galaxy_id
            end

            # Grow by adding (cell, symmetric counterpart) pairs
            changed = true
            while changed
                changed = false
                boundary = Tuple{Int,Int}[]
                for i in 1:n, j in 1:m
                    assignment[i, j] == galaxy_id || continue
                    for (di, dj) in _GEN_OFFSETS
                        ni, nj = i + di, j + dj
                        if 1 <= ni <= n && 1 <= nj <= m && assignment[ni, nj] == 0
                            push!(boundary, (ni, nj))
                        end
                    end
                end
                unique!(boundary)
                shuffle!(boundary)

                for (ci, cj) in boundary
                    assignment[ci, cj] == 0 || continue
                    img = sym_cell(ci, cj, dr, dc, n, m)
                    img === nothing && continue
                    si, sj = img
                    if (si, sj) == (ci, cj)
                        assignment[ci, cj] = galaxy_id
                        changed = true
                    elseif assignment[si, sj] == 0
                        assignment[ci, cj] = galaxy_id
                        assignment[si, sj] = galaxy_id
                        changed = true
                    end
                end
            end

            push!(dots, (dr, dc))
            placed = true
            break
        end

        if !placed
            # Fallback: a single-cell galaxy at the seed's centre
            galaxy_id += 1
            assignment[seed_i, seed_j] = galaxy_id
            push!(dots, (2*seed_i-1, 2*seed_j-1))
        end
    end

    return n, m, dots
end


"""
    generateDataSet()

Generate Galaxies instances of various sizes under `../data/`.
Skips files that already exist.
"""
function generateDataSet()
    dataFolder = "../data/"
    isdir(dataFolder) || mkpath(dataFolder)

    sizes = [(4, 4), (5, 5), (6, 6), (7, 7), (8, 8), (10, 10)]

    for (n, m) in sizes
        for trial in 1:3
            filename = dataFolder * "galaxies_$(n)x$(m)_$(trial).txt"
            isfile(filename) && continue
            _, _, dots = generateInstance(n, m)
            saveInstance(filename, n, m, dots)
            println("Generated $filename  ($(length(dots)) galaxies)")
        end
    end
end
