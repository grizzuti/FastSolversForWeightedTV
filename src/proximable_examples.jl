#: Utilities for norm functions

export ptdot, ptnorm1, ptnorm2, ptnormInf
export mixed_norm, gradient_norm, gradient_norm_batch
export proj_options


# Options for projection-related operations

struct ProjOptions
    maxiter::Union{Nothing,Int64}
    xrtol::Union{Nothing,Real}
end

proj_options(; maxiter::Union{Nothing,Int64}=nothing, xrtol::Union{Nothing,Real}=nothing) = ProjOptions(maxiter, xrtol)


# Mixed norm

struct MixedNorm{T,D,N1,N2}<:ProximableFunction{T,D}
    proj_opt::ProjOptions
end

function mixed_norm(T::DataType, D::Number, N1::Number, N2::Number; proj_opt::Union{Nothing,ProjOptions}=nothing)
    proj_opt === nothing && (proj_opt = proj_options())
    (D == 1) && return MixedNorm{T,2,N1,N2}(proj_opt)
    (D == 2) && return MixedNorm{T,3,N1,N2}(proj_opt)
    (D == 3) && return MixedNorm{T,4,N1,N2}(proj_opt)
end


# Mixed norm (batch)

struct MixedNormBatch{T,D,N1,N2}<:ProximableFunction{T,D}
    proj_opt::ProjOptions
end

function mixed_norm_batch(T::DataType, D::Number, N1::Number, N2::Number; proj_opt::Union{Nothing,ProjOptions}=nothing)
    proj_opt === nothing && (proj_opt = proj_options())
    (D == 2) && return MixedNormBatch{T,4,N1,N2}(proj_opt)
    (D == 3) && return MixedNormBatch{T,5,N1,N2}(proj_opt)
    throw("Dimension not supported")
end


# L22 norm

function proxy!(p::AbstractArray{CT,N}, λ::T, ::MixedNorm{CT,N,2,2}, q::AbstractArray{CT,N}) where {T<:Real,N,CT<:RealOrComplex{T}}
    np = norm22(p)
    np <= λ ? (return q .= CT(0)) : (return q .= (1-λ/np)*p)
end

function project!(p::AbstractArray{CT,N}, ε::T, ::MixedNorm{CT,N,2,2}, q::AbstractArray{CT,N}) where {T<:Real,N,CT<:RealOrComplex{T}}
    np = norm22(p)
    np <= ε ? (return q .= p) : (return q .= ε*p/np)
end

(::MixedNorm{T,N,2,2})(p::AbstractArray{T,N}) where {T,N} = norm22(p)


# L21 norm

function proxy!(p::AbstractArray{CT,N}, λ::T, ::MixedNorm{CT,N,2,1}, q::AbstractArray{CT,N}; ptn::Union{AbstractArray{T,N},Nothing}=nothing) where {T<:Real,N,CT<:RealOrComplex{T}}
    ptn === nothing && (ptn = ptnorm2(p; η=eps(T)))
    return q .= (1 .-λ./ptn).*(ptn .>= λ).*p
end

function project!(p::AbstractArray{CT,N}, ε::T, g::MixedNorm{CT,N,2,1}, q::AbstractArray{CT,N}) where {T<:Real,N,CT<:RealOrComplex{T}}
    ptn = ptnorm2(p; η=eps(T))
    sum(ptn) <= ε && (return q .= p)
    λ = pareto_search_proj21(ptn, ε; xrtol=g.proj_opt.xrtol, maxiter=g.proj_opt.maxiter)
    return proxy!(p, λ, g, q; ptn=ptn)
end

(::MixedNorm{T,N,2,1})(p::AbstractArray{T,N}) where {T,N} = norm21(p)


# L21 norm (batch, 2-D)

function proxy!(p::AbstractArray{CT,4}, λ::T, ::MixedNormBatch{CT,4,2,1}, q::AbstractArray{CT,4}; ptn::Union{AbstractArray{CT,4},Nothing}=nothing) where {T<:Real,CT<:RealOrComplex{T}}
    ptn === nothing && (ptn = ptnorm2_batch(p; η=eps(T)))
    nx,ny,nc,nb = size(p)
    p = reshape(p, nx,ny,2,div(nc,2)*nb)
    q = reshape(q, nx,ny,2,div(nc,2)*nb)
    ptn = reshape(ptn, nx,ny,1,div(nc,2)*nb)
    q .= (CT(1).-λ./ptn).*(ptn .>= λ).*p
    return reshape(q, nx,ny,nc,nb)
end

(::MixedNormBatch{T,4,2,1})(p::AbstractArray{T,4}) where T = norm21_batch(p)


# L2Inf norm

function proxy!(p::AbstractArray{CT,N}, λ::T, ::MixedNorm{CT,N,2,Inf}, q::AbstractArray{CT,N}) where {T<:Real,N,CT<:RealOrComplex{T}}
    project!(p, λ, mixed_norm(CT, N-1, 2, 1), q)
    return q .= p.-q
end

function project!(p::AbstractArray{CT,N}, ε::T, ::MixedNorm{CT,N,2,Inf}, q::AbstractArray{CT,N}) where {T<:Real,N,CT<:RealOrComplex{T}}
    ptn = ptnorm2(p; η=eps(T))
    val = ptn .>= ε
    q .= p.*(ε*val./ptn+(!).(val))
    return q
end

(::MixedNorm{T,N,2,Inf})(p::AbstractArray{T,N}) where {T,N} = norm2Inf(p)


# Gradient mixed norm

function gradient_norm(N1::Number, N2::Number, n::NTuple{D,Int64}, h::NTuple{D,T}; weight::Union{Nothing,AbstractLinearOperator}=nothing, proj_opt::Union{Nothing,ProjOptions}=nothing, complex::Bool=false) where {D,T<:Real}
    ∇ = gradient_operator(n, h; complex=complex)
    weight !== nothing ? (A∇ = weight*∇) : (A∇ = ∇)
    return mixed_norm(T, D, N1, N2; proj_opt=proj_opt)∘A∇
end


# Gradient mixed norm (2-D, batch)

function gradient_norm_batch(N1::Number, N2::Number, n::NTuple{D,Int64}, nc::Int64, nb::Int64, h::NTuple{2,T}; weight::Union{Nothing,AbstractLinearOperator}=nothing, proj_opt::Union{Nothing,ProjOptions}=nothing, complex::Bool=false) where {T<:Real,D}
    ∇ = gradient_operator_batch(n, nc, nb, h; complex=complex)
    weight !== nothing ? (A∇ = weight*∇) : (A∇ = ∇)
    return mixed_norm_batch(T, D, N1, N2; proj_opt=proj_opt)∘A∇
end


# Pareto-search routines

pareto_search_proj21(ptn::AbstractArray{T,N}, ε::T; maxiter::Union{Nothing,Int64}=nothing, xrtol::Union{Nothing,T}=nothing) where {T<:Real,N} = T(solve(ZeroProblem(λ -> obj_pareto_search_proj21(λ, ptn, ε), (T(0), maximum(ptn))), Roots.Brent(); xreltol=isnothing(xrtol) ? eps(T) : xrtol, maxevals=isnothing(maxiter) ? length(ptn) : maxiter))

obj_pareto_search_proj21(λ::T, ptn::AbstractArray{T,N}, ε::T) where {T<:Real,N} = sum(Flux.relu.(ptn.-λ))-ε


# Algebraic utils

ptdot(v1::AbstractArray{T,N}, v2::AbstractArray{T,N}) where {T,N} = sum(v1.*conj.(v2); dims=N)
ptnorm1(p::AbstractArray{CT,N}; η::T=T(0)) where {T<:Real,N,CT<:RealOrComplex{T}} = sum(abs.(p).+η; dims=N)
ptnorm2(p::AbstractArray{CT,N}; η::T=T(0)) where {T<:Real,N,CT<:RealOrComplex{T}} = sqrt.(sum(abs.(p).^2 .+η^2; dims=N))
ptnormInf(p::AbstractArray{CT,N}; η::T=T(0)) where {T<:Real,N,CT<:RealOrComplex{T}} = sqrt.(maximum(abs.(p).+η; dims=N))
function ptnorm2_batch(p::AbstractArray{CT,4}; η::T=T(0)) where {T<:Real,CT<:RealOrComplex{T}}
    nx,ny,nc,nb = size(p)
    p = reshape(p, nx,ny,2,div(nc,2)*nb)
    return reshape(sqrt.(abs.(p[:,:,1:1,:]).^2+abs.(p[:,:,2:2,:]).^2 .+η^2), nx,ny,div(nc,2),nb)
end
function ptnorm2_batch(p::AbstractArray{CT,5}; η::T=T(0)) where {T<:Real,CT<:RealOrComplex{T}}
    nx,ny,nz,nc,nb = size(p)
    p = reshape(p, nx,ny,nz,2,div(nc,2)*nb)
    return reshape(sqrt.(abs.(p[:,:,1:1,:]).^2+abs.(p[:,:,2:2,:]).^2+abs.(p[:,:,3:3,:]).^2 .+η^2), nx,ny,div(nc,2),nb)
end
norm21(v::AbstractArray{CT,N}; η::T=T(0)) where {T<:Real,N,CT<:RealOrComplex{T}} = sum(ptnorm2(v; η=η))
norm22(v::AbstractArray{CT,N}; η::T=T(0)) where {T<:Real,N,CT<:RealOrComplex{T}} = sqrt(sum(ptnorm2(v; η=η).^2))
norm2Inf(v::AbstractArray{CT,N}; η::T=T(0)) where {T<:Real,N,CT<:RealOrComplex{T}} = maximum(ptnorm2(v; η=η))
function norm21_batch(v::AbstractArray{CT,4}; η::T=T(0)) where {T<:Real,CT<:RealOrComplex{T}}
    _,_,nc,nb = size(v)
    return reshape(sum(ptnorm2_batch(v; η=η); dims=(1,2)), div(nc,2), nb)
end
function norm21_batch(v::AbstractArray{CT,5}; η::T=T(0)) where {T<:Real,CT<:RealOrComplex{T}}
    _,_,_,nc,nb = size(v)
    return reshape(sum(ptnorm2_batch(v; η=η); dims=(1,2,3)), div(nc,2), nb)
end