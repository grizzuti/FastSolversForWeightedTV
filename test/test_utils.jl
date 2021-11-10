using Test, Flux, CUDA

const RealOrComplex{T}=Union{T,Complex{T}}

function test_grad(fun::DifferentiableFunction{CT,N}, x::AbstractArray{CT,N}; step::T=T(1e-4), rtol::T=eps(T)) where {T<:Real,N,CT<:RealOrComplex{T}}

    dx = randn(T, size(x)); dx *= norm(x)/norm(dx); x isa CuArray && (dx = dx |> gpu)
    _, Δx = grad(fun, x)
    fp1 = fun(x+T(0.5)*step*dx)
    fm1 = fun(x-T(0.5)*step*dx)
    @test (fp1-fm1)/step ≈ real(dot(dx, Δx)) rtol=rtol

end