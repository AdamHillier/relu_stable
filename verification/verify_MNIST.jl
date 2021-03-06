using MIPVerify
using Gurobi
using Memento
using MAT

model_name = ARGS[1]
println(model_name)

eps = parse(Float64, ARGS[2])
println(eps)

if ARGS[3] == "none"
    adv_pred_opt = MIPVerify.None()
elseif ARGS[3] == "find_min_dist_threshold"
    adv_pred_opt = MIPVerify.FindMinDistanceThreshold()
else
    adv_pred_opt = MIPVerify.MinDistanceThreshold(parse(Float32, ARGS[3]))
end
println(adv_pred_opt)

dataset = ARGS[4]
@assert(dataset == "validation" || dataset == "test")
println(dataset)

if isassigned(ARGS, 5)
    start_index = parse(Int64, ARGS[5])
else
    start_index = 1
end
if isassigned(ARGS, 6)
    end_index = parse(Int64, ARGS[6])
elseif dataset == "validation"
    end_index = 5000
else
    end_index = 10000
end
println("Verifying $(start_index) through $(end_index)")

path="./model_mats/$(model_name).mat"
param_dict = path |> matread

c1_size = 3136
c2_size = 1568
c3_size = 100

fc1 = get_matrix_params(param_dict, "fc1", (784, c1_size))
if haskey(param_dict, "fc1/mask")
    m1 = MaskedReLU(squeeze(param_dict["fc1/mask"], 1), interval_arithmetic)
else
    m1 = ReLU(interval_arithmetic)
end
fc2 = get_matrix_params(param_dict, "fc2", (c1_size, c2_size))
if haskey(param_dict, "fc2/mask")
    m2 = MaskedReLU(squeeze(param_dict["fc2/mask"], 1))
else
    m2 = ReLU()
end
fc3 = get_matrix_params(param_dict, "fc3", (c2_size, c3_size))
if haskey(param_dict, "fc3/mask")
    m3 = MaskedReLU(squeeze(param_dict["fc3/mask"], 1))
else
    m3 = ReLU()
end
if adv_pred_opt == MIPVerify.None()
    softmax = get_matrix_params(param_dict, "softmax", (c3_size, 10))
else
    softmax = get_matrix_params(param_dict, "softmax_with_dists", (c3_size, 55))
end

nnparams = Sequential(
    [Flatten(4), fc1, m1, fc2, m2, fc3, m3, softmax],
    "$(model_name)"
)

mnist = dataset == "validation" ?
    read_datasets("MNIST", 55001, 5000).train :
    read_datasets("MNIST").test

target_indexes = start_index:end_index

MIPVerify.setloglevel!("info")

MIPVerify.batch_find_untargeted_attack(
    nnparams,
    mnist,
    target_indexes,
    10,
    adv_pred_opt,
    GurobiSolver(Gurobi.Env(), BestObjStop=eps, TimeLimit=180),
    save_path="./verification/results_$(dataset)/",
    norm_order=Inf,
    tightening_algorithm=lp,
    rebuild=false,
    cache_model=false,
    tightening_solver=GurobiSolver(Gurobi.Env(), TimeLimit=10, OutputFlag=0),
    pp = MIPVerify.LInfNormBoundedPerturbationFamily(eps),
    solve_rerun_option = MIPVerify.retarget_successful_cases
)
