#: Utils

export conjugate, proxy_objfun, proj_objfun
export no_constraints, indicator


# Scaled version of proximable/projectionable functions

struct ScaledProximableFun{T,N}<:ProximableFunction{T,N}
    c::Real
    g::ProximableFunction{T,N}
end

proxy!(y::AbstractArray{CT,N}, λ::T, g::ScaledProximableFun{CT,N}, x::AbstractArray{CT,N}) where {T<:Real,N,CT<:RealOrComplex{T}} = proxy!(y, λ*g.c, g.g, x)
project!(y::AbstractArray{CT,N}, ε::T, g::ScaledProximableFun{CT,N}, x::AbstractArray{CT,N}) where {T<:Real,N,CT<:RealOrComplex{T}} = project!(y, g.c/ε, g.g, x)


# LinearAlgebra

Base.:*(c::T, g::ProximableFunction{CT,N}) where {T<:Real,N,CT<:RealOrComplex{T}} = ScaledProximableFun{CT,N}(c, g)
Base.:*(c::T, g::ScaledProximableFun{CT,N}) where {T<:Real,N,CT<:RealOrComplex{T}} = ScaledProximableFun{CT,N}(c*g.c, g.g)
Base.:/(g::ProximableFunction{CT,N}, c::T) where {T<:Real,N,CT<:RealOrComplex{T}} = ScaledProximableFun{CT,N}(T(1)/c, g)
Base.:/(g::ScaledProximableFun{CT,N}, c::T) where {T<:Real,N,CT<:RealOrComplex{T}} = ScaledProximableFun{CT,N}(g.c/c, g.g)


# Conjugation of proximable functions

struct ConjugateProxFun{T,N}<:ProximableFunction{T,N}
    g::ProximableFunction{T,N}
end

function proxy!(y::AbstractArray{CT,N}, λ::T, g::ConjugateProxFun{CT,N}, x::AbstractArray{CT,N}) where {T<:Real,N,CT<:RealOrComplex{T}}
    proxy!(y/λ, T(1)/λ, g.g, x)
    x .= y-λ*x
    return x
end

conjugate(g::ProximableFunction{T,N}) where {T,N} = ConjugateProxFun{T,N}(g)
conjugate(g::ConjugateProxFun) = g.g


# Constraint sets

## No constraints

struct NoConstraints{T,N}<:ProjectionableSet{T,N} end

no_constraints(T::DataType, N::Int64) = NoConstraints{T,N}()

project!(x::AbstractArray{T,N}, ::NoConstraints{T,N}, y::Array{T,N}) where {T,N} = (y .= x)

## Sub-level sets with proximable functions

"""
Constraint set C = {x:g(x)<=ε}
"""
struct SubLevelSet{T,N}<:ProjectionableSet{T,N}
    g::ProximableFunction{T,N}
    ε::Real
end

Base.:≤(g::ProximableFunction{CT,N}, ε::T) where {T<:Real,N,CT<:RealOrComplex{T}} = SubLevelSet{CT,N}(g, ε)

project!(x::AbstractArray{T,N}, C::SubLevelSet{T,N}, y::AbstractArray{T,N}) where {T,N} = project!(x, C.ε, C.g, y)
project!(x::AbstractArray{T,N}, C::SubLevelSet{T,N}, y::AbstractArray{T,N}, opt::OptimOptions) where {T,N} = project!(x, C.ε, C.g, y, opt)

## Indicator function

"""
Indicator function δ_C(x) = {0, if x ∈ C; ∞, otherwise} for convex sets C
"""
struct IndicatorFunction{T,N}<:ProximableFunction{T,N}
    C::ProjectionableSet{T,N}
end

indicator(C::ProjectionableSet{T,N}) where {T,N} = IndicatorFunction{T,N}(C)

proxy!(y::AbstractArray{CT,N}, ::T, δ::IndicatorFunction{CT,N}, x::AbstractArray{CT,N}) where {T<:Real,N,CT<:RealOrComplex{T}} = project!(y, δ.C, x)
proxy!(y::AbstractArray{CT,N}, ::T, δ::IndicatorFunction{CT,N}, x::AbstractArray{CT,N}, opt::OptimOptions) where {T<:Real,N,CT<:RealOrComplex{T}} = project!(y, δ.C, x, opt)


# Proximable + linear operator

struct WeightedProximableFun{T,N1,N2}<:ProximableFunction{T,N1}
    g::ProximableFunction{T,N2}
    A::AbstractLinearOperator{T,N1,N2}
end

Base.:∘(g::ProximableFunction{T,N2}, A::AbstractLinearOperator{T,N1,N2}) where {T,N1,N2} = WeightedProximableFun{T,N1,N2}(g, A)

function proxy!(y::AbstractArray{CT,N1}, λ::T, g::WeightedProximableFun{CT,N1,N2}, x::AbstractArray{CT,N1}, opt::OptimOptions) where {T<:Real,N1,N2,CT<:RealOrComplex{T}}

    # Objective function (dual problem)
    f = leastsquares_misfit(adjoint(g.A), y/λ)+conjugate(g.g)/λ

    # Minimization (dual variable)
    p0 = similar(y, range_size(g.A)); p0 .= T(0)
    p = minimize(f, p0, opt)

    # Dual to primal solution
    return x .= y-λ*(adjoint(g.A)*p)

end

function project!(y::AbstractArray{CT,N1}, ε::T, g::WeightedProximableFun{CT,N1,N2}, x::AbstractArray{CT,N1}, opt::OptimOptions) where {T<:Real,N1,N2,CT<:RealOrComplex{T}}

    # Objective function (dual problem)
    f = leastsquares_misfit(adjoint(g.A), y)+conjugate(indicator(g.g ≤ ε))

    # Minimization (dual variable)
    p0 = similar(y, range_size(g.A)); p0 .= T(0)
    p = minimize(f, p0, opt)

    # Dual to primal solution
    return x .= y-adjoint(g.A)*p

end

(g::WeightedProximableFun{T,N1,N2})(x::AbstractArray{T,N1}) where {T,N1,N2} = g.g(g.A*x)

Flux.gpu(g::WeightedProximableFun{T,N1,N2}) where {T,N1,N2} = WeightedProximableFun{T,N1,N2}(g.g, gpu(g.A))
Flux.cpu(g::WeightedProximableFun{T,N1,N2}) where {T,N1,N2} = WeightedProximableFun{T,N1,N2}(g.g, cpu(g.A))


# Proximable function evaluation

struct ProxyObjFun{T,N} <: DifferentiableFunction{T,N}
    λ::Real
    g::ProximableFunction{T,N}
    opt::Union{Nothing,OptimOptions}
end

proxy_objfun(λ::T, g::ProximableFunction{CT,N}) where {T<:Real,N,CT<:RealOrComplex{T}} = ProxyObjFun{CT,N}(λ, g, nothing)
proxy_objfun(λ::T, g::ProximableFunction{CT,N}, opt::OptimOptions) where {T<:Real,N,CT<:RealOrComplex{T}} = ProxyObjFun{CT,N}(λ, g, opt)

function grad!(f::ProxyObjFun{T,N}, y::AbstractArray{T,N}, g::Union{Nothing,AbstractArray{T,N}}) where {T,N}
    f.opt === nothing ? (x = proxy(y, f.λ, f.g)) : (x = proxy(y, f.λ, f.g, f.opt))
    g !== nothing && (g .= y-x)
    return T(0.5)*norm(x-y)^2+f.λ*f.g(x)
end


struct ProjObjFun{T,N} <: DifferentiableFunction{T,N}
    ε::Real
    g::ProximableFunction{T,N}
    opt::Union{Nothing,OptimOptions}
end

proj_objfun(ε::T, g::ProximableFunction{CT,N}) where {T<:Real,N,CT<:RealOrComplex{T}} = ProjObjFun{CT,N}(ε, g, nothing)
proj_objfun(ε::T, g::ProximableFunction{CT,N}, opt::OptimOptions) where {T<:Real,N,CT<:RealOrComplex{T}} = ProjObjFun{CT,N}(ε, g, opt)

function grad!(f::ProjObjFun{T,N}, y::AbstractArray{T,N}, g::Union{Nothing,AbstractArray{T,N}}) where {T,N}
    f.opt === nothing ? (x = project(y, f.ε, f.g)) : (x = project(y, f.ε, f.g, f.opt))
    g !== nothing && (g .= y-x)
    return T(0.5)*norm(x-y)^2
end


# Minimizable type utils

struct DiffPlusProxFun{T,N}<:MinimizableFunction{T,N}
    f::DifferentiableFunction{T,N}
    g::ProximableFunction{T,N}
end

Base.:+(f::DifferentiableFunction{T,N}, g::ProximableFunction{T,N}) where {T,N} = DiffPlusProxFun{T,N}(f, g)