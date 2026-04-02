# This file contains functions related to reading, writing and displaying a Mosaic grid and experimental results

using JuMP
using Plots
import GR

TOL = 0.00001

"""
Read an instance from an input file

- Argument:
inputFile: path of the input file

- Format:
  First line: "n m" (grid dimensions)
  Then a "# grid" header followed by n rows of m space-separated values (. for empty, integer for clue)
  Optionally a "# solution" header followed by n rows of m space-separated values (0/1)

Returns a Tuple containing:
1. An n x m matrix of Integers (the puzzle, -1 for empty)
2. An n x m matrix of Integers (the solution, 1 for black, 0 for white. -1 if no solution provided)
"""
function readInputFile(inputFile::String)
    # Open the input file and read all lines
    lines = readlines(inputFile)
    
    # The first line contains the dimensions (e.g., "5 5")
    dims = split(lines[1])
    n = parse(Int, dims[1])
    m = parse(Int, dims[2])
    
    # Initialize empty matrices of size n x m filled with -1
    grid = fill(-1, n, m)
    solution = fill(-1, n, m)
    
    reading_solution = false
    row_idx = 1
    
    # Loop through the remaining lines to fill the grid and solution
    for i in 2:length(lines)
        line = strip(lines[i]) # Remove leading/trailing whitespace
        
        # Skip empty lines
        if isempty(line)
            continue
        end
        
        # Check for section headers
        if startswith(line, "#")
            if occursin("solution", lowercase(line))
                reading_solution = true
                row_idx = 1 # Reset row counter for the solution matrix
            end
            continue # Move to the next line
        end
        
        # Parse the actual grid or solution rows
        row_str = split(line)
        if !reading_solution
            # We are reading the initial puzzle
            for j in 1:min(m, length(row_str))
                if row_str[j] != "."
                    grid[row_idx, j] = parse(Int, row_str[j])
                end
            end
        else
            # We are reading the solution
            for j in 1:min(m, length(row_str))
                solution[row_idx, j] = parse(Int, row_str[j])
            end
        end
        
        row_idx += 1
    end
    
    return grid, solution 
end


"""
Displays the unsolved grid in the console.
"""
function displayGrid(grid::Matrix{Int})
    n, m = size(grid)
    println("┌", "───" ^ m, "┐")
    for i in 1:n
        print("│")
        for j in 1:m
            if grid[i, j] == -1
                print(" . ")
            else
                print(" $(grid[i, j]) ")
            end
        end
        println("│")
    end
    println("└", "───" ^ m, "┘")
end


"""
Displays the solved solution in the console.

Argument:
- solution: an n x m matrix with values 0 (white) or 1 (black)
"""
function displaySolution(solution::Matrix{Int})
    n, m = size(solution)
    println("┌", "───" ^ m, "┐")
    for i in 1:n
        print("│")
        for j in 1:m
            if solution[i, j] == 1
                print(" ■ ") # Black square
            elseif solution[i, j] == 0
                print(" □ ") # White square
            else
                print(" ? ") # Unknown/Error
            end
        end
        println("│")
    end
    println("└", "───" ^ m, "┘")
end


"""
Save a Mosaic instance to a text file

Arguments:
- grid: n x m matrix with clue values (-1 for empty cells)
- outputFile: path of the output file
"""
function saveInstance(grid::Matrix{Int}, outputFile::String)
    n, m = size(grid)
    writer = open(outputFile, "w")
    
    println(writer, "$n $m")
    println(writer, "# grid")
    
    for i in 1:n
        row_parts = String[]
        for j in 1:m
            if grid[i, j] == -1
                push!(row_parts, ".")
            else
                push!(row_parts, string(grid[i, j]))
            end
        end
        println(writer, join(row_parts, " "))
    end
    
    close(writer)
end


"""
Write a CPLEX solution to an output stream

Arguments:
- fout: the output stream (usually an output file)
- solution: an n x m matrix with values 0 (white) or 1 (black)
"""
function writeSolution(fout::IOStream, solution::Matrix{Int})
    n, m = size(solution)
    println(fout, "solution = [")
    for i in 1:n
        print(fout, "[ ")
        for j in 1:m
            print(fout, string(solution[i, j]) * " ")
        end
        endLine = "]"
        if i != n
            endLine *= ";"
        end
        println(fout, endLine)
    end
    println(fout, "]")
end


"""
Create a pdf file which contains a performance diagram associated to the results of the ../res folder
Display one curve for each subfolder of the ../res folder.

Arguments
- outputFile: path of the output file

Prerequisites:
- Each subfolder must contain text files
- Each text file correspond to the resolution of one instance
- Each text file contains a variable "solveTime" and a variable "isOptimal"
"""
function performanceDiagram(outputFile::String)

    resultFolder = "../res/"
    
    # Maximal number of files in a subfolder
    maxSize = 0

    # Number of subfolders
    subfolderCount = 0

    folderName = Array{String, 1}()

    # For each file in the result folder
    for file in readdir(resultFolder)

        path = resultFolder * file
        
        # If it is a subfolder
        if isdir(path)
            
            folderName = vcat(folderName, file)
             
            subfolderCount += 1
            folderSize = size(readdir(path), 1)

            if maxSize < folderSize
                maxSize = folderSize
            end
        end
    end

    if subfolderCount == 0 || maxSize == 0
        println("No results found in $resultFolder")
        return
    end

    # Array that will contain the resolution times (one line for each subfolder)
    results = Array{Float64}(undef, subfolderCount, maxSize)

    for i in 1:subfolderCount
        for j in 1:maxSize
            results[i, j] = Inf
        end
    end

    folderCount = 0
    maxSolveTime = 0

    # For each subfolder
    for file in readdir(resultFolder)
            
        path = resultFolder * file
        
        if isdir(path)

            folderCount += 1
            fileCount = 0

            # For each text file in the subfolder
            for resultFile in filter(x->occursin(".txt", x), readdir(path))

                fileCount += 1
                include(abspath(path * "/" * resultFile))

                if isOptimal
                    results[folderCount, fileCount] = solveTime

                    if solveTime > maxSolveTime
                        maxSolveTime = solveTime
                    end 
                end 
            end 
        end
    end 

    # Sort each row increasingly
    results = sort(results, dims=2)

    println("Max solve time: ", maxSolveTime)

    # For each line to plot
    for dim in 1: size(results, 1)

        x = Array{Float64, 1}()
        y = Array{Float64, 1}()

        # x coordinate of the previous inflexion point
        previousX = 0
        previousY = 0

        append!(x, previousX)
        append!(y, previousY)
            
        # Current position in the line
        currentId = 1

        # While the end of the line is not reached 
        while currentId != size(results, 2) && results[dim, currentId] != Inf

            # Number of elements which have the value previousX
            identicalValues = 1

             # While the value is the same
            while results[dim, currentId] == previousX && currentId <= size(results, 2)
                currentId += 1
                identicalValues += 1
            end

            # Add the proper points
            append!(x, previousX)
            append!(y, currentId - 1)

            if results[dim, currentId] != Inf
                append!(x, results[dim, currentId])
                append!(y, currentId - 1)
            end
            
            previousX = results[dim, currentId]
            previousY = currentId - 1
            
        end

        append!(x, maxSolveTime)
        append!(y, currentId - 1)

        # If it is the first subfolder
        if dim == 1

            # Draw a new plot
            plot(x, y, label = folderName[dim], legend = :bottomright, xaxis = "Time (s)", yaxis = "Solved instances",linewidth=3)

        # Otherwise 
        else
            # Add the new curve to the created plot
            savefig(plot!(x, y, label = folderName[dim], linewidth=3), outputFile)
        end 
    end
end 

"""
Create a latex file which contains an array with the results of the ../res folder.
Each subfolder of the ../res folder contains the results of a resolution method.

Arguments
- outputFile: path of the output file

Prerequisites:
- Each subfolder must contain text files
- Each text file correspond to the resolution of one instance
- Each text file contains a variable "solveTime" and a variable "isOptimal"
"""
function resultsArray(outputFile::String)
    
    resultFolder = "../res/"
    dataFolder = "../data/"
    
    # Maximal number of files in a subfolder
    maxSize = 0

    # Number of subfolders
    subfolderCount = 0

    # Open the latex output file
    fout = open(outputFile, "w")

    # Print the latex file output
    println(fout, raw"""\documentclass{article}

\usepackage[french]{babel}
\usepackage [utf8] {inputenc} % utf-8 / latin1 
\usepackage{multicol}

\setlength{\hoffset}{-18pt}
\setlength{\oddsidemargin}{0pt} % Marge gauche sur pages impaires
\setlength{\evensidemargin}{9pt} % Marge gauche sur pages paires
\setlength{\marginparwidth}{54pt} % Largeur de note dans la marge
\setlength{\textwidth}{481pt} % Largeur de la zone de texte (17cm)
\setlength{\voffset}{-18pt} % Bon pour DOS
\setlength{\marginparsep}{7pt} % Séparation de la marge
\setlength{\topmargin}{0pt} % Pas de marge en haut
\setlength{\headheight}{13pt} % Haut de page
\setlength{\headsep}{10pt} % Entre le haut de page et le texte
\setlength{\footskip}{27pt} % Bas de page + séparation
\setlength{\textheight}{668pt} % Hauteur de la zone de texte (25cm)

\begin{document}""")

    header = raw"""
\begin{center}
\renewcommand{\arraystretch}{1.4} 
 \begin{tabular}{l"""

    # Name of the subfolder of the result folder (i.e, the resolution methods used)
    folderName = Array{String, 1}()

    # List of all the instances solved by at least one resolution method
    solvedInstances = Array{String, 1}()

    # For each file in the result folder
    for file in readdir(resultFolder)

        path = resultFolder * file
        
        # If it is a subfolder
        if isdir(path)

            # Add its name to the folder list
            folderName = vcat(folderName, file)
             
            subfolderCount += 1
            folderSize = size(readdir(path), 1)

            # Add all its files in the solvedInstances array
            for file2 in filter(x->occursin(".txt", x), readdir(path))
                solvedInstances = vcat(solvedInstances, file2)
            end 

            if maxSize < folderSize
                maxSize = folderSize
            end
        end
    end

    # Only keep one string for each instance solved
    solvedInstances = unique(solvedInstances)

    # For each resolution method, add two columns in the array
    for folder in folderName
        header *= "rr"
    end

    header *= "}\n\t\\hline\n"

    # Create the header line which contains the methods name
    for folder in folderName
        header *= " & \\multicolumn{2}{c}{\\textbf{" * folder * "}}"
    end

    header *= "\\\\\n\\textbf{Instance} "

    # Create the second header line with the content of the result columns
    for folder in folderName
        header *= " & \\textbf{Temps (s)} & \\textbf{Optimal ?} "
    end

    header *= "\\\\\\hline\n"

    footer = raw"""\hline\end{tabular}
\end{center}

"""
    println(fout, header)

    # On each page an array will contain at most maxInstancePerPage lines with results
    maxInstancePerPage = 30
    id = 1

    # For each solved files
    for solvedInstance in solvedInstances

        # If we do not start a new array on a new page
        if rem(id, maxInstancePerPage) == 0
            println(fout, footer, "\\newpage")
            println(fout, header)
        end 

        # Replace the potential underscores '_' in file names
        print(fout, replace(solvedInstance, "_" => "\\_"))

        # For each resolution method
        for method in folderName

            path = resultFolder * method * "/" * solvedInstance

            # If the instance has been solved by this method
            if isfile(path)

                include(abspath(path))

                println(fout, " & ", round(solveTime, digits=2), " & ")

                if isOptimal
                    println(fout, "\$\\times\$")
                end 
                
            # If the instance has not been solved by this method
            else
                println(fout, " & - & - ")
            end
        end

        println(fout, "\\\\")

        id += 1
    end

    # Print the end of the latex file
    println(fout, footer)

    println(fout, "\\end{document}")

    close(fout)
    
end