# Ablation runner. Compares baseline cplexSolve against:
#   (a) no symmetric-cut strengthening
#   (b) no heuristic warm start
# on every instance in ../data/. Writes a CSV summary to ../res/ablation.csv.

include("resolution.jl")
import Random
Random.seed!(2026)

# Add 2 more 15×15 instances if needed
for trial in 2:3
    f = "../data/galaxies_15x15_$(trial).txt"
    isfile(f) && continue
    println("Generating $f")
    _, _, dots = generateInstance(15, 15)
    saveInstance(f, 15, 15, dots)
end

const ABLATION_TIMELIMIT = 120.0

results = Vector{NamedTuple}()
data_files = sort(filter(x -> endswith(x, ".txt"), readdir("../data/")))

for file in data_files
    n, m, dots = readInputFile("../data/" * file)
    println("\n── $file  ($(n)×$(m), $(length(dots)) galaxies) ──")

    # Baseline: warm start ON, sym cut ON
    is_opt_b, t_b, _, _, cuts_b = cplexSolve(n, m, dots;
        time_limit = ABLATION_TIMELIMIT,
        use_heuristic_start = true, use_sym_cut = true)
    println("  baseline:    $(round(t_b, sigdigits=3))s   cuts=$cuts_b   ok=$is_opt_b")

    # No symmetric cut
    is_opt_nsc, t_nsc, _, _, cuts_nsc = cplexSolve(n, m, dots;
        time_limit = ABLATION_TIMELIMIT,
        use_heuristic_start = true, use_sym_cut = false)
    println("  no sym cut:  $(round(t_nsc, sigdigits=3))s   cuts=$cuts_nsc   ok=$is_opt_nsc")

    # No warm start
    is_opt_nws, t_nws, _, _, cuts_nws = cplexSolve(n, m, dots;
        time_limit = ABLATION_TIMELIMIT,
        use_heuristic_start = false, use_sym_cut = true)
    println("  no warmstrt: $(round(t_nws, sigdigits=3))s   cuts=$cuts_nws   ok=$is_opt_nws")

    push!(results, (
        instance = file, n = n, m = m, k = length(dots),
        t_baseline = t_b, cuts_baseline = cuts_b, ok_baseline = is_opt_b,
        t_no_sym = t_nsc, cuts_no_sym = cuts_nsc, ok_no_sym = is_opt_nsc,
        t_no_warm = t_nws, cuts_no_warm = cuts_nws, ok_no_warm = is_opt_nws,
    ))
end

# Write CSV
open("../res/ablation.csv", "w") do f
    println(f, "instance,n,m,K,t_baseline,cuts_baseline,t_no_sym,cuts_no_sym,t_no_warm,cuts_no_warm")
    for r in results
        println(f, "$(r.instance),$(r.n),$(r.m),$(r.k)," *
                   "$(r.t_baseline),$(r.cuts_baseline)," *
                   "$(r.t_no_sym),$(r.cuts_no_sym)," *
                   "$(r.t_no_warm),$(r.cuts_no_warm)")
    end
end
println("\nWrote ../res/ablation.csv  ($(length(results)) instances)")
