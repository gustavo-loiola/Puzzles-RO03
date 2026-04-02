# This file contains methods to solve a sudoku grid (heuristically or with CPLEX)
using CPLEX

include("generation.jl")

TOL = 0.00001

"""
Solve a sudoku grid with CPLEX with the additional rule that the Manhattan distance between the ones must all be different.

Argument
- t: array of size n*n with values in [0, n] (0 if the cell is empty)

Return
- status: :Optimal if the problem is solved optimally
- x: 3-dimensional variables array such that x[i, j, k] = 1 if cell (i, j) has value k
- getsolvetime(m): resolution time in seconds
"""
function cplexSolveWithCallback(t::Array{Int, 2})

    n = size(t, 1)

    # Create the model
    m = Model(CPLEX.Optimizer)

    # x[i, j, k] = 1 if cell (i, j) has value k
    @variable(m, x[1:n, 1:n, 1:n], Bin)

    # Set the fixed value in the grid
    for l in 1:n
        for c in 1:n
            if t[l, c] != 0
                @constraint(m, x[l,c, t[l, c]] == 1)
            end
        end
    end

    # Each cell (i, j) has one value k
    @constraint(m, [i in 1:n, j in 1:n], sum(x[i, j, k] for k in 1:n) == 1)

    # Each line l has one cell with value k
    @constraint(m, [k in 1:n, l in 1:n], sum(x[l, j, k] for j in 1:n) == 1)

    # Each column c has one cell with value k
    @constraint(m, [k in 1:n, c in 1:n], sum(x[i, c, k] for i in 1:n) == 1)

    # Get the size of a block
    blockSize = round.(Int, sqrt(n))

    # Each block has one cell with value k
    # (lTop, cLeft) is the top left cell of each block
    @constraint(m, [lTop in 1:blockSize:n, cLeft in 1:blockSize:n, k in 1:n], sum(x[lTop+i, cLeft+j, k] for i in 0:blockSize-1, j in 0:blockSize-1) == 1)

    # Maximize the top-left cell (reduce the problem symmetry)
    @objective(m, Max, sum(x[1, 1, k] for k in 1:n))

    """
      Fonction qui sera exécutée par CPLEX à chaque fois qu'une des conditions suivantes est remplie :
       - 1 solution entière a été trouvée ;
       - 1 relaxation a été calculée ;
       - ...
      
       Arguments :
       - context_id : permet de déterminer pour quelle raison le callback à  été appelé ;
       - cb_data  :   permet  d'obtenir   d'autres   informations
         (valeur des bornes inférieures et supérieures , meilleure solution
         connue, ...)
      """
    function callback_manhattan(cb_data::CPLEX.CallbackContext, context_id::Clong)

        # On teste d'abord si c'est l'obtention d'une solution entière
        # qui a entraîné l'appel du callback
        # (cette fonction isIntegerPoint est définie ci-dessous mais son 
        # contenu n'est pas très important)
        if isIntegerPoint(cb_data, context_id)
            
            # Cette ligne doit être  appelée avant de pouvoir récupérer la
            # solution entière ayant entraîné l'appel du callback
            CPLEX.load_callback_variable_primal(cb_data, context_id)

            # On récupère la valeur de x dans la solution trouvée par CPLEX
            x_val = callback_value.(cb_data, x)

            # On trouve les coordonnées du 1 dans le carré en haut à gauche
            pTopLeft = nothing
            for i in 1:blockSize
                for j in 1:blockSize
                    if x_val[i, j, 1] > 0.9
                        pTopLeft = (i, j)
                    end
                end
            end
            
            # On trouve  les coordonnées de toutes les cases ayant la valeur 1
            ones_positions = Vector{Tuple{Int,Int}}()
            for i in 1:n, j in 1:n
                if x_val[i, j, 1] > 0.9
                    push!(ones_positions, (i, j))
                end
            end
            
            # Dictionnaire contenant les positions des 1 indexées par
            # leur distance à la position pTopLeft
            # Par exemple si l'index 10 existe, dist_dict[10] contiendra une
            # position p à distance 10 de pTopLeft
            dist_dict = Dict{Int, Tuple{Int,Int}}()

            for a in 1:length(ones_positions)
                p = ones_positions[a]  # On récupère la position

                # Calculer la distance de Manhattan entre p et pTopLeft
                d = abs(pTopLeft[1] - p[1]) + abs(pTopLeft[2] - p[2]) 

                # S'il existe déjà une autre position à distance d de pTopLeft
                if haskey(dist_dict, d) 
                    p2 = dist_dict[d] # Récupérer l'autre position

                    println("Callback : solution trouvée avec 2 positions contenant des 1 à distance ", d, " du 1 dans le bloc en haut à gauche :\n\tPosition du 1 en haut à gauche :", pTopLeft, "\n\tPosition à même distance couple de positions : ", p, p2)
                    
                    # Ajouter une contrainte qui empêche d'avoir des 1 dans ces 3
                    # positions en même temps
                    cstr = @build_constraint(x[pTopLeft[1], pTopLeft[2], 1] +
                                             x[p[1], p[2], 1] +
                                             x[p2[1], p2[2], 1] <= 2)
                    MOI.submit(m, MOI.LazyConstraint(cb_data), cstr)
                else
                    # Sinon, ajouter au dictionnaire les position à l'indice d
                    dist_dict[d] = (p) 
                end
            end
        end
    end

    # Utilisation d'un unique thread (obligatoire quand on utilise les callbacks
    MOI.set(m, MOI.NumberOfThreads(), 1)
    
    # Ajout du callback au modèle m
    MOI.set(m, CPLEX.CallbackFunction(), callback_manhattan)

    # Limite le temps de réoslution à 30 secondes
    #set_optimizer_attribute(m, "CPX_PARAM_TILIM", 30)

    start = time()
    optimize!(m)

    # Return:
    # - a boolean which is true if a feasible solution is found (type: Bool);
    # - the value of each cell (type: Array{VariableRef, 2})
    # - the resolution time (type Float64)
    return JuMP.primal_status(m) == JuMP.MOI.FEASIBLE_POINT, x, time() - start

end

"""
Heuristically solve a grid by successively assigning values to one of the most constrained cells 
(i.e., a cell in which the number of remaining possible values is the lowest)

Argument
- t: array of size n*n with values in [0, n] (0 if the cell is empty)

Return
- gridFeasible: true if the problem is solved
- tCopy: the grid solved (or partially solved if the problem is not solved)
"""
function heuristicSolve(t::Array{Int, 2}, checkFeasibility::Bool)

    n = size(t, 1)
    tCopy = copy(t)

    # True if the grid has completely been filled
    gridFilled = false

    # True if the grid may still have a solution
    gridStillFeasible = true

    # While the grid is not filled and it may still be solvable
    while !gridFilled && gridStillFeasible

        # Coordinates of the most constrained cell
        mcCell = [-1 -1]

        # Values which can be assigned to the most constrained cell
        values = nothing
        
        # Randomly select a cell and a value
        l = ceil.(Int, n * rand())
        c = ceil.(Int, n * rand())
        id = 1

        # For each cell of the grid, while a cell with 0 values has not been found
        while id <= n*n && (values == nothing || size(values, 1)  != 0)

            # If the cell does not have a value
            if tCopy[l, c] == 0

                # Get the values which can be assigned to the cell
                cValues = possibleValues(tCopy, l, c)

                # If it is the first cell or if it is the most constrained cell currently found
                if values == nothing || size(cValues, 1) < size(values, 1)

                    values = cValues
                    mcCell = [l c]
                end 
            end
            
            # Go to the next cell                    
            if c < n
                c += 1
            else
                if l < n
                    l += 1
                    c = 1
                else
                    l = 1
                    c = 1
                end
            end

            id += 1
        end

        # If all the cell have a value
        if values == nothing

            gridFilled = true
            gridStillFeasible = true
        else

            # If a cell cannot be assigned any value
            if size(values, 1) == 0
                gridStillFeasible = false

                # Else assign a random value to the most constrained cell 
            else
                
                newValue = ceil.(Int, rand() * size(values, 1))
                if checkFeasibility
                    
                    gridStillFeasible = false
                    id = 1
                    while !gridStillFeasible && id <= size(values, 1)

                        tCopy[mcCell[1], mcCell[2]] = values[rem(newValue, size(values, 1)) + 1]
                        
                        if isGridFeasible(tCopy)
                            gridStillFeasible = true
                        else
                            newValue += 1
                        end

                        id += 1
                        
                    end
                else 
                    tCopy[mcCell[1], mcCell[2]] = values[newValue]
                end 
            end 
        end  
    end  

    return gridStillFeasible, tCopy
    
end 

"""
Number of values which could currently be assigned to a cell

Arguments
- t: array of size n*n with values in [0, n] (0 if the cell is empty)
- l, c: row and column of the cell

Return
- values: array of integers which do not appear on line l, column c or in the block of (l, c)
"""
function possibleValues(t::Array{Int, 2}, l::Int64, c::Int64)

    values = Array{Int64, 1}()

    for v in 1:size(t, 1)
        if isValid(t, l, c, v)
            values = append!(values, v)
        end 
    end 

    return values
    
end

"""
Solve all the instances contained in "../data" through CPLEX and the heuristic

The results are written in "../res/cplex" and "../res/heuristic"

Remark: If an instance has previously been solved (either by cplex or the heuristic) it will not be solved again
"""
function solveDataSetWithCallback()

    dataFolder = "../data/"
    resFolder = "../res/"

    resolutionFolder = resFolder * "cplex_callback"
    
    if !isdir(resolutionFolder)
        mkdir(resolutionFolder)
    end
    
    global isOptimal = false
    global solveTime = -1

    # For each input file
    # (for each file in folder dataFolder which ends by ".txt")
    for file in filter(x->occursin(".txt", x)  && !occursin(r"~$", x), readdir(dataFolder))  
        
        println("-- Resolution of ", file)
        t = readInputFile(dataFolder * file)
        
        outputFile = resolutionFolder * "/" * file

        # If the input file has not already been solved by this method
        if true#!isfile(outputFile)
            
            fout = open(outputFile, "w")  

            resolutionTime = -1
            isOptimal = false
            
            # Solve it and get the results
            isOptimal, x, resolutionTime = cplexSolveWithCallback(t)
            
            # Also write the solution (if any)
            if isOptimal
                writeSolution(fout, x)
            end

            println(fout, "solveTime = ", resolutionTime) 
            println(fout, "isOptimal = ", isOptimal) 
            close(fout)
        end

        # Display the results obtained with the method on the current instance
        include(outputFile)
        println("optimal: ", isOptimal)
        println("time: " * string(round(solveTime, sigdigits=2)) * "s\n")
    end 
end

"""
Test if the grid is feasible

Arguments
- t: array of size n*n with values in [0, n] (0 if the cell is empty)
"""
function isGridFeasible(t::Array{Int64, 2})

    n = size(t, 1)
    isFeasible = true

    l = 1
    c = 1

    # For each cell (l, c) while previous cells can be assigned a value
    while isFeasible && l <= n

        # If a value is not assigned to (l, c)
        if t[l, c] == 0

            # Test all values v until a value which can be assigned to (l, c) is found
            feasibleValueFound = false
            v = 1

            while !feasibleValueFound && v <= n

                if isValid(t, l, c, v)
                    feasibleValueFound = true
                end
                
                v += 1
                
            end
            
            if !feasibleValueFound
                isFeasible = false
            end 
        end 

        # Go to the next cell
        if c < n
            c += 1
        else
            l += 1
            c = 1
        end
    end

    return isFeasible
end 


"""
Fonction  permettant  de  déterminer  si  c'est  l'obtention  d'une solution entière qui a entraîné l'appel d'un callback
(il n'est pas nécessaire d'en comprendre le fonctionnement)
"""
function isIntegerPoint(cb_data::CPLEX.CallbackContext, context_id::Clong)

    # context_id  == CPX_CALLBACKCONTEXT_CANDIDATE si le  callback est
    # appelé dans un des deux cas suivants :
    # cas 1 - une solution entière a été obtenue; ou
    # cas 2 - une relaxation non bornée a été obtenue
    if context_id != CPX_CALLBACKCONTEXT_CANDIDATE
        return false
    end

    # Pour déterminer si on est dans le cas 1 ou 2, on essaie de récupérer la
    # solution entière courante
    ispoint_p = Ref{Cint}()
    ret = CPXcallbackcandidateispoint(cb_data, ispoint_p)

    # S'il n'y a pas de solution entière
    if ret != 0 || ispoint_p[] == 0
        return false
    else
        return true
    end
end
