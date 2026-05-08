# This file contains methods to generate a data set of Galaxies instances

include("io.jl")
using Random


"""
Compute the 180° symmetric image of cell (i,j) with respect to a dot
at doubled coordinates (p, q).

Returns (si, sj) if the image lies inside the grid, `nothing` otherwise.
"""
function symmetricImage(i::Int, j::Int, p::Int, q::Int, n::Int, m::Int)
    si = p - i
    sj = q - j
    if 1 <= si <= n && 1 <= sj <= m
        return (si, sj)
    end
    return nothing
end


"""
Compute the anchor cells D_k of a dot at doubled position (p, q):
the grid cells that the dot lies on or touches.

Returns a Vector{Tuple{Int,Int}} with 1, 2, or 4 cells.
"""
function getAnchorCells(p::Int, q::Int, n::Int, m::Int)
    i_min = max(1, Int(ceil((p - 1) / 2)))
    i_max = min(n, Int(floor((p + 1) / 2)))
    j_min = max(1, Int(ceil((q - 1) / 2)))
    j_max = min(m, Int(floor((q + 1) / 2)))

    cells = Tuple{Int,Int}[]
    for i in i_min:i_max, j in j_min:j_max
        push!(cells, (i, j))
    end
    return cells
end


# ─────────────────────────────────────────────────────────────────────────────
#  Instance generation
# ─────────────────────────────────────────────────────────────────────────────

"""
Generate a random Galaxies instance of size `n` rows × `m` columns.

Strategy: build a valid partition by growing symmetric regions one by one,
then extract the dot positions.

Arguments:
- n: number of rows
- m: number of columns

Returns:
- grid: (n, m)
- dots: Vector{Tuple{Int,Int}} of dot positions in doubled coordinates
"""
function generateInstance(n::Int, m::Int)

    assignment = zeros(Int, n, m)    # 0 = unassigned
    dots = Tuple{Int,Int}[]
    galaxy_id = 0

    offsets = [(-1, 0), (1, 0), (0, -1), (0, 1)]

    while any(assignment .== 0)
        # ── Pick a random unassigned cell ────────────────────────────────
        free = [(i, j) for i in 1:n, j in 1:m if assignment[i, j] == 0]
        if isempty(free)
            break
        end
        seed_i, seed_j = free[rand(1:length(free))]

        # ── Try different dot placements around this cell ────────────────
        # Candidate doubled positions: cell centre, edges, and corner
        candidateDots = [
            (2 * seed_i, 2 * seed_j),               # cell centre
        ]
        # Edge midpoints (if neighbour exists and is also free)
        for (di, dj) in offsets
            ni, nj = seed_i + di, seed_j + dj
            if 1 <= ni <= n && 1 <= nj <= m
                push!(candidateDots, (seed_i + ni, seed_j + nj))  # doubled midpoint
            end
        end
        # Corner (if diagonal neighbour exists)
        for (di, dj) in [(1, 1), (1, -1), (-1, 1), (-1, -1)]
            ni, nj = seed_i + di, seed_j + dj
            if 1 <= ni <= n && 1 <= nj <= m
                push!(candidateDots, (seed_i + ni, seed_j + nj))
            end
        end

        # Shuffle candidates for randomness
        shuffle_order = randperm(length(candidateDots))
        placed = false

        for idx in shuffle_order
            p, q = candidateDots[idx]
            anch = getAnchorCells(p, q, n, m)

            # Check that all anchor cells are free
            if !all(assignment[ai, aj] == 0 for (ai, aj) in anch)
                continue
            end

            # Place this galaxy and try to grow it
            galaxy_id += 1
            for (ai, aj) in anch
                assignment[ai, aj] = galaxy_id
            end

            # Grow: try adding cell + symmetric pair from the boundary
            changed = true
            while changed
                changed = false
                boundary = Tuple{Int,Int}[]

                # Find free cells adjacent to the current region
                for i in 1:n, j in 1:m
                    if assignment[i, j] != galaxy_id
                        continue
                    end
                    for (di, dj) in offsets
                        ni, nj = i + di, j + dj
                        if 1 <= ni <= n && 1 <= nj <= m &&
                           assignment[ni, nj] == 0
                            push!(boundary, (ni, nj))
                        end
                    end
                end
                unique!(boundary)

                # Shuffle for randomness
                for bi in randperm(length(boundary))
                    ci, cj = boundary[bi]
                    if assignment[ci, cj] != 0
                        continue
                    end

                    img = symmetricImage(ci, cj, p, q, n, m)
                    if img === nothing
                        continue
                    end
                    si, sj = img

                    if (si, sj) == (ci, cj)
                        # Self-symmetric cell
                        assignment[ci, cj] = galaxy_id
                        changed = true
                    elseif assignment[si, sj] == 0
                        assignment[ci, cj] = galaxy_id
                        assignment[si, sj] = galaxy_id
                        changed = true
                    end
                end
            end

            push!(dots, (p, q))
            placed = true
            break
        end

        if !placed
            # Could not place a galaxy at this seed — mark cell as its own
            # single-cell galaxy (dot at its centre)
            galaxy_id += 1
            assignment[seed_i, seed_j] = galaxy_id
            push!(dots, (2 * seed_i, 2 * seed_j))
        end
    end

    return (n, m), dots
end


"""
Generate a data set of instances and save them to `../data/`.

Creates grids of varying sizes. Skips files that already exist.
"""
function generateDataSet()

    dataFolder = "../data/"
    if !isdir(dataFolder)
        mkpath(dataFolder)
    end

    sizes = [(4, 4), (5, 5), (6, 6), (7, 7), (8, 8), (10, 10)]

    for (n, m) in sizes
        for trial in 1:3
            filename = dataFolder * "galaxies_$(n)x$(m)_$(trial).txt"
            if isfile(filename)
                continue
            end

            grid, dots = generateInstance(n, m)
            fout = open(filename, "w")
            println(fout, "$m $n")
            for (p, q) in dots
                println(fout, "$p $q")
            end
            close(fout)

            println("Generated $filename  ($(length(dots)) galaxies)")
        end
    end
end