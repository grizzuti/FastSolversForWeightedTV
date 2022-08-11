using LinearAlgebra, FastSolversForWeightedTV, ConvexOptimizationUtils, Flux, TestImages, BenchmarkTools
using CUDA; CUDA.allowscalar(false)
using Random; Random.seed!(123)

# Dimension
# dim = 2
dim = 3

# Optimization options
flag_gpu = true
# flag_gpu = false
dim == 2 && (L = 8f0)
dim == 3 && (L = 12f0)
opt = FISTA_optimizer(L; Nesterov=true, niter=10, reset_counter=10, verbose=false)

# TV norm
n = tuple(256*ones(Int64, dim)...)
h = tuple(ones(Float32, dim)...)
g = gradient_norm(2,1,n,h; complex=true); flag_gpu && (g = g |> gpu)

# Numerical phantom
y = Float32.(TestImages.shepp_logan(n[1:2]...))
dim == 3 && (y = repeat(y; outer=(1,1,n[3])))
y = y/norm(y, Inf)
y += 0.1f0*randn(ComplexF32, n)
flag_gpu && (y = y |> gpu)

# Proxy
λ = 0.5f0*norm(y)^2/g(y)
@btime proxy(y, λ, g, opt);

# Projection test
ε = 0.1f0*g(y)
@btime project(y, ε, g, opt);