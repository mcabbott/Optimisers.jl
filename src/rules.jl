"""
    Descent(η = 1f-1)

Classic gradient descent optimiser with learning rate `η`.
For each parameter `p` and its gradient `dp`, this runs `p -= η*dp`.

# Parameters
- Learning rate (`η`): Amount by which gradients are discounted before updating
                       the weights.
"""
struct Descent{T}
  eta::T
end
Descent() = Descent(1f-1)

init(o::Descent, x::AbstractArray) = nothing

function apply!(o::Descent, state, x, dx)
  η = convert(float(eltype(x)), o.eta)
  
  return state, @lazy dx * η  # @lazy creates a Broadcasted, will later fuse with x .= x .- dx
end

"""
    Momentum(η = 1f-2, ρ = 9f-1)

Gradient descent optimizer with learning rate `η` and momentum `ρ`.

# Parameters
- Learning rate (`η`): Amount by which gradients are discounted before updating
                       the weights.
- Momentum (`ρ`): Controls the acceleration of gradient descent in the
                  prominent direction, in effect dampening oscillations.
"""
struct Momentum{T}
  eta::T
  rho::T
end
Momentum(η = 1f-2, ρ = 9f-1) = Momentum{typeof(η)}(η, ρ)

init(o::Momentum, x::AbstractArray) = zero(x)

function apply!(o::Momentum, state, x, dx)
  η, ρ, mvel = o.eta, o.rho, state
  @.. mvel = ρ * mvel + η * dx  # Macro @.. broadcasts into mvel if it can, else @. of rhs.
  
  return mvel, mvel
end

"""
    Nesterov(η = 1f-3, ρ = 9f-1)

Gradient descent optimizer with learning rate `η` and Nesterov momentum `ρ`.

# Parameters
- Learning rate (`η`): Amount by which gradients are discounted before updating
                       the weights.
- Nesterov momentum (`ρ`): Controls the acceleration of gradient descent in the
                           prominent direction, in effect dampening oscillations.
"""
struct Nesterov{T}
  eta::T
  rho::T
end
Nesterov(η = 1f-3, ρ = 9f-1) = Nesterov{typeof(η)}(η, ρ)

init(o::Nesterov, x::AbstractArray) = zero(x)

function apply!(o::Nesterov, state, x, dx)
  η, ρ, vel = o.eta, o.rho, state

  newdx = @. - ρ^2 * vel + (1+ρ) * η * dx  # Cannot be lazy as this needs the old velocity
  @.. vel = ρ * vel - η * dx
  
  return vel, newdx
end

"""
    RMSProp(η = 1f-3, ρ = 9f-1, ϵ = eps(typeof(η)))

Optimizer using the
[RMSProp](https://www.cs.toronto.edu/~tijmen/csc321/slides/lecture_slides_lec6.pdf)
algorithm. Often a good choice for recurrent networks. Parameters other than learning rate
generally don't need tuning.

# Parameters
- Learning rate (`η`): Amount by which gradients are discounted before updating
                       the weights.
- Momentum (`ρ`): Controls the acceleration of gradient descent in the
                  prominent direction, in effect dampening oscillations.
- Machine epsilon (`ϵ`): Constant to prevent division by zero
                         (no need to change default)
"""
struct RMSProp{T}
  eta::T
  rho::T
  epsilon::T
end
RMSProp(η = 1f-3, ρ = 9f-1, ϵ = eps(typeof(η))) = RMSProp{typeof(η)}(η, ρ, ϵ)

init(o::RMSProp, x::AbstractArray) = zero(x)

function apply!(o::RMSProp, state, x, dx)
  η, ρ, ϵ, acc = o.eta, o.rho, o.epsilon, state

  @.. acc = ρ * acc + (1 - ρ) * abs2(dx)
  dx′ = @lazy dx * (η / (sqrt(acc) + ϵ))
  
  return acc, dx′
end

"""
    ADAM(η = 1f-3, β = (9f-1, 9.99f-1), ϵ = eps(typeof(η)))

[ADAM](https://arxiv.org/abs/1412.6980) optimiser.

# Parameters
- Learning rate (`η`): Amount by which gradients are discounted before updating
                       the weights.
- Decay of momentums (`β::Tuple`): Exponential decay for the first (β1) and the
                                   second (β2) momentum estimate.
- Machine epsilon (`ϵ`): Constant to prevent division by zero
                         (no need to change default)
"""
struct ADAM{T}
  eta::T
  beta::Tuple{T, T}
  epsilon::T
end
ADAM(η = 1f-3, β = (9f-1, 9.99f-1), ϵ = eps(typeof(η))) = ADAM{typeof(η)}(η, β, ϵ)

init(o::ADAM, x::AbstractArray) = (zero(x), zero(x), o.beta)

function apply!(o::ADAM, state, x, dx)
  η, β, ϵ = o.eta, o.beta, o.epsilon
  mt, vt, βt = state

  @.. mt = β[1] * mt + (1 - β[1]) * dx
  @.. vt = β[2] * vt + (1 - β[2]) * abs2(dx)
  dx′ = @lazy mt / (1 - βt[1]) / (sqrt(vt / (1 - βt[2])) + ϵ) * η

  return (mt, vt, βt .* β), dx′
end

"""
    RADAM(η = 1f-3, β = (9f-1, 9.99f-1), ϵ = eps(typeof(η)))

[Rectified ADAM](https://arxiv.org/abs/1908.03265) optimizer.

# Parameters
- Learning rate (`η`): Amount by which gradients are discounted before updating
                       the weights.
- Decay of momentums (`β::Tuple`): Exponential decay for the first (β1) and the
                                   second (β2) momentum estimate.
- Machine epsilon (`ϵ`): Constant to prevent division by zero
                         (no need to change default)
"""
struct RADAM{T}
  eta::T
  beta::Tuple{T, T}
  epsilon::T
end
RADAM(η = 1f-3, β = (9f-1, 9.99f-1), ϵ = eps(typeof(η))) = RADAM{typeof(η)}(η, β, ϵ)

init(o::RADAM, x::AbstractArray) = (zero(x), zero(x), o.beta, 1)

function apply!(o::RADAM, state, x, dx)
  η, β, ϵ = o.eta, o.beta, o.epsilon
  ρ∞ = 2/(1-β[2])-1

  mt, vt, βt, t = state

  @.. mt = β[1] * mt + (1 - β[1]) * dx
  @.. vt = β[2] * vt + (1 - β[2]) * abs2(dx)
  ρ = ρ∞ - 2*t * βt[2] / (1 - βt[2])
  if ρ > 4
    r = sqrt((ρ - 4) * (ρ - 2) * ρ∞/((ρ∞ - 4) * (ρ∞ - 2) * ρ))
    dx′ = @lazy mt / (1 - βt[1]) / (sqrt(vt / (1 - βt[2])) + ϵ) * η * r
  else
    dx′ = @lazy mt / (1 - βt[1]) * η
  end

  return (mt, vt, βt .* β, t + 1), dx′
end

"""
    AdaMax(η = 1f-3, β = (9f-1, 9.99f-1), ϵ = eps(typeof(η)))

[AdaMax](https://arxiv.org/abs/1412.6980) is a variant of ADAM based on the ∞-norm.

# Parameters
- Learning rate (`η`): Amount by which gradients are discounted before updating
                       the weights.
- Decay of momentums (`β::Tuple`): Exponential decay for the first (β1) and the
                                   second (β2) momentum estimate.
- Machine epsilon (`ϵ`): Constant to prevent division by zero
                         (no need to change default)
"""
struct AdaMax{T}
  eta::T
  beta::Tuple{T, T}
  epsilon::T
end
AdaMax(η = 1f-3, β = (9f-1, 9.99f-1), ϵ = eps(typeof(η))) = AdaMax{typeof(η)}(η, β, ϵ)

init(o::AdaMax, x::AbstractArray) = (zero(x), zero(x), o.beta)

function apply!(o::AdaMax, state, x, dx)
  η, β, ϵ = o.eta, o.beta, o.epsilon
  mt, ut, βt = state

  @.. mt = β[1] * mt + (1 - β[1]) * dx
  @.. ut = max(β[2] * ut, abs(dx))
  dx′ = @lazy (η/(1 - βt[1])) * mt/(ut + ϵ)

  return (mt, ut, βt .* β), dx′
end

"""
    OADAM(η = 1f-3, β = (5f-1, 9f-1), ϵ = eps(typeof(η)))

[OADAM](https://arxiv.org/abs/1711.00141) (Optimistic ADAM)
is a variant of ADAM adding an "optimistic" term suitable for adversarial training.

# Parameters
- Learning rate (`η`): Amount by which gradients are discounted before updating
                       the weights.
- Decay of momentums (`β::Tuple`): Exponential decay for the first (β1) and the
                                   second (β2) momentum estimate.
- Machine epsilon (`ϵ`): Constant to prevent division by zero
                         (no need to change default)
"""
struct OADAM{T}
  eta::T
  beta::Tuple{T, T}
  epsilon::T
end
OADAM(η = 1f-3, β = (5f-1, 9f-1), ϵ = eps(typeof(η))) = OADAM{typeof(η)}(η, β, ϵ)

init(o::OADAM, x::AbstractArray) = (zero(x), zero(x), o.beta, zero(x))

function apply!(o::OADAM, state, x, dx)
  η, β, ϵ = o.eta, o.beta, o.epsilon
  mt, vt, βt, term = state

  @.. mt = β[1] * mt + (1 - β[1]) * dx
  @.. vt = β[2] * vt + (1 - β[2]) * abs2(dx)
  prev = copy(term)
  @.. term = η * mt / (1 - βt[1]) / (sqrt(vt / (1 - βt[2])) + ϵ)
  dx′ = @lazy 2 * term - prev

  return (mt, vt, βt .* β, term), dx′
end

"""
    ADAGrad(η = 1f-1, ϵ = eps(typeof(η)))

[ADAGrad](http://www.jmlr.org/papers/volume12/duchi11a/duchi11a.pdf) optimizer. It has
parameter specific learning rates based on how frequently it is updated.
Parameters don't need tuning.

# Parameters
- Learning rate (`η`): Amount by which gradients are discounted before updating
                       the weights.
- Machine epsilon (`ϵ`): Constant to prevent division by zero
                         (no need to change default)
"""
struct ADAGrad{T}
  eta::T
  epsilon::T
end
ADAGrad(η = 1f-1, ϵ = eps(typeof(η))) = ADAGrad{typeof(η)}(η, ϵ)

init(o::ADAGrad, x::AbstractArray) = onevalue(o.epsilon, x)

function apply!(o::ADAGrad, state, x, dx)
  η, ϵ = o.eta, o.epsilon
  acc = state

  @.. acc = acc + abs2(dx)
  dx′ = @lazy dx * η / (sqrt(acc) + ϵ)

  return acc, dx′
end

"""
    ADADelta(ρ = 9f-1, ϵ = eps(typeof(ρ)))

[ADADelta](https://arxiv.org/abs/1212.5701) is a version of ADAGrad adapting its learning
rate based on a window of past gradient updates.
Parameters don't need tuning.

# Parameters
- Rho (`ρ`): Factor by which the gradient is decayed at each time step.
- Machine epsilon (`ϵ`): Constant to prevent division by zero
                         (no need to change default)
"""
struct ADADelta{T}
  rho::T
  epsilon::T
end
ADADelta(ρ = 9f-1, ϵ = eps(typeof(ρ))) = ADADelta{typeof(ρ)}(ρ, ϵ)

init(o::ADADelta, x::AbstractArray) = (zero(x), zero(x))

function apply!(o::ADADelta, state, x, dx)
  ρ, ϵ = o.rho, o.epsilon
  acc, Δacc = state

  @.. acc = ρ * acc + (1 - ρ) * abs2(dx)
  # DON'T remove epsilon from numerator or even out of the square roots!
  dx′ = @. dx * sqrt(Δacc + ϵ) / sqrt(acc + ϵ)  # Cannot be lazy as this needs the old Δacc
  @.. Δacc = ρ * Δacc + (1 - ρ) * abs2(dx′)
  
  return (acc, Δacc), dx′
end

"""
    AMSGrad(η = 1f-3, β = (9f-1, 9.99f-1), ϵ = eps(typeof(η)))

The [AMSGrad](https://openreview.net/forum?id=ryQu7f-RZ) version of the ADAM
optimiser. Parameters don't need tuning.

# Parameters
- Learning rate (`η`): Amount by which gradients are discounted before updating
                       the weights.
- Decay of momentums (`β::Tuple`): Exponential decay for the first (β1) and the
                                   second (β2) momentum estimate.
- Machine epsilon (`ϵ`): Constant to prevent division by zero
                         (no need to change default)
"""
struct AMSGrad{T}
  eta::T
  beta::Tuple{T, T}
  epsilon::T
end
AMSGrad(η = 1f-3, β = (9f-1, 9.99f-1), ϵ = eps(typeof(η))) = AMSGrad{typeof(η)}(η, β, ϵ)

init(o::AMSGrad, x::AbstractArray) =
  (onevalue(o.epsilon, x), onevalue(o.epsilon, x), onevalue(o.epsilon, x))

function apply!(o::AMSGrad, state, x, dx)
  η, β, ϵ = o.eta, o.beta, o.epsilon
  mt, vt, v̂t = state

  @.. mt = β[1] * mt + (1 - β[1]) * dx
  @.. vt = β[2] * vt + (1 - β[2]) * abs2(dx)
  @.. v̂t = max(v̂t, vt)
  dx′ = @lazy η * mt / (sqrt(v̂t) + ϵ)

  return (mt, vt, v̂t), dx′
end

"""
    NADAM(η = 1f-3, β = (9f-1, 9.99f-1), ϵ = eps(typeof(η)))

[NADAM](https://openreview.net/forum?id=OM0jvwB8jIp57ZJjtNEZ) is a Nesterov variant of ADAM.
Parameters don't need tuning.

# Parameters
- Learning rate (`η`): Amount by which gradients are discounted before updating
                       the weights.
- Decay of momentums (`β::Tuple`): Exponential decay for the first (β1) and the
                                   second (β2) momentum estimate.
- Machine epsilon (`ϵ`): Constant to prevent division by zero
                         (no need to change default)
"""
struct NADAM{T}
  eta::T
  beta::Tuple{T, T}
  epsilon::T
end
NADAM(η = 1f-3, β = (9f-1, 9.99f-1), ϵ = eps(typeof(η))) = NADAM{typeof(η)}(η, β, ϵ)

init(o::NADAM, x::AbstractArray) = (zero(x), zero(x), o.beta)

function apply!(o::NADAM, state, x, dx)
  η, β, ϵ = o.eta, o.beta, o.epsilon

  mt, vt, βt = state

  @.. mt = β[1] * mt + (1 - β[1]) * dx
  @.. vt = β[2] * vt + (1 - β[2]) * abs2(dx)
  dx′ = @lazy (β[1] * mt / (1 - β[1] * βt[1]) + (1 - β[1]) * dx / (1 - βt[1])) / 
          (sqrt(vt * β[2] / (1 - βt[2])) + ϵ) * η

  return (mt, vt, βt .* β), dx′
end

"""
    ADAMW(η = 1f-3, β = (9f-1, 9.99f-1), γ = 0, ϵ = eps(typeof(η)))

[ADAMW](https://arxiv.org/abs/1711.05101) is a variant of ADAM fixing (as in repairing) its
weight decay regularization.

# Parameters
- Learning rate (`η`): Amount by which gradients are discounted before updating
                       the weights.
- Decay of momentums (`β::Tuple`): Exponential decay for the first (β1) and the
                                   second (β2) momentum estimate.
- Weight decay (`γ`): Decay applied to weights during optimisation.
- Machine epsilon (`ϵ`): Constant to prevent division by zero
                         (no need to change default)
"""
ADAMW(η = 1f-3, β = (9f-1, 9.99f-1), γ = 0, ϵ = eps(typeof(η))) =
  OptimiserChain(ADAM{typeof(η)}(η, β, ϵ), WeightDecay{typeof(η)}(γ))

"""
    AdaBelief(η = 1f-3, β = (9f-1, 9.99f-1), ϵ = eps(typeof(η)))

The [AdaBelief](https://arxiv.org/abs/2010.07468) optimiser is a variant of the well-known
ADAM optimiser.

# Parameters
- Learning rate (`η`): Amount by which gradients are discounted before updating
                       the weights.
- Decay of momentums (`β::Tuple`): Exponential decay for the first (β1) and the
                                   second (β2) momentum estimate.
- Machine epsilon (`ϵ::Float32`): Constant to prevent division by zero
                                  (no need to change default)
"""
struct AdaBelief{T}
  eta::T
  beta::Tuple{T, T}
  epsilon::T
end
AdaBelief(η = 1f-3, β = (9f-1, 9.99f-1), ϵ = eps(typeof(η))) = AdaBelief{typeof(η)}(η, β, ϵ)

init(o::AdaBelief, x::AbstractArray) = (zero(x), zero(x))

function apply!(o::AdaBelief, state, x, dx)
  η, β, ϵ = o.eta, o.beta, o.epsilon
  mt, st = state

  @.. mt = β[1] * mt + (1 - β[1]) * dx
  @.. st = β[2] * st + (1 - β[2]) * abs2(dx - mt)
  dx′ = @lazy η * mt / (sqrt(st) + ϵ)
  
  return (mt, st), dx′
end

"""
    WeightDecay(γ = 5f-4)

Decay weights by ``γ``, that is, add `γ .* x` to the gradient `x̄` which will be
subtracted from `x`.

Typically composed  with other optimisers as the first transformation in an [`OptimiserChain`](@ref).
This is equivalent to adding ``L_2`` regularization with coefficient ``γ`` to the loss.

# Parameters
- Weight decay (`γ`): Decay applied to weights during optimisation.
"""
struct WeightDecay{T}
  gamma::T
end
WeightDecay() = WeightDecay(5f-4)

init(o::WeightDecay, x::AbstractArray) = nothing

function apply!(o::WeightDecay, state, x, dx)
  dx′ = @lazy dx + o.gamma * x

  return state, dx′
end

"""
    ClipGrad(δ = 10f0)

Restricts every gradient component to obey `-δ ≤ dx[i] ≤ δ`.

See also [`ClipNorm`](@ref).
"""
struct ClipGrad{T<:Real}
  delta::T
end
ClipGrad() = ClipGrad(10f0)

init(o::ClipGrad, x::AbstractArray) = nothing

function apply!(o::ClipGrad, state, x, dx)
  δ = convert(float(eltype(x)), o.delta)
  dx′ = @lazy clamp(dx, -δ, δ)

  return state, dx′
end

"""
    ClipNorm(ω = 10f0, p = 2; throw = true)

Scales any gradient array for which `norm(dx, p) > ω`
to stay at this threshold (unless `p==0`).

Throws an error if the norm is infinite or `NaN`,
which you can turn off with `throw = false`.

See also [`ClipGrad`](@ref).
"""
struct ClipNorm{T<:Real}
  omega::T
  p::T
  throw::Bool
end
ClipNorm(ω = 10f0, p = 2; throw::Bool = true) = ClipNorm{typeof(ω)}(ω, p, throw)

init(o::ClipNorm, x::AbstractArray) = nothing

function apply!(o::ClipNorm, state, x, dx)
  nrm = norm(dx, o.p)
  if o.throw && !isfinite(nrm)
    throw(DomainError("gradient has $(o.p)-norm $nrm, for array $(summary(x))"))
  end
  λ = min(o.omega / nrm, 1)

  return state, @lazy dx * λ
end

"""
    OptimiserChain(opts...)

Compose a sequence of optimisers so that each `opt` in `opts`
updates the gradient, in the order specified.

With an empty sequence, `OptimiserChain()` is the identity,
so `update!` will subtract the full gradient from the parameters.
This is equivalent to `Descent(1)`.

# Example
```jldoctest
julia> o = OptimiserChain(ClipGrad(1), Descent(0.1));

julia> m = (zeros(3),);

julia> s = Optimisers.setup(o, m)
(Leaf(OptimiserChain(ClipGrad{Int64}(1), Descent{Float64}(0.1)), [nothing, nothing]),)

julia> Optimisers.update(s, m, ([0.3, 1, 7],))[2]  # clips before discounting
([-0.03, -0.1, -0.1],)
```
"""
struct OptimiserChain{O<:Tuple}
  opts::O
end
OptimiserChain(opts...) = OptimiserChain(opts)

init(o::OptimiserChain, x::AbstractArray) = [init(opt, x) for opt in o.opts]

function apply!(o::OptimiserChain, states, x, dx, dxs...)
  new_states = similar(states)
  for (i, (opt, state)) in enumerate(zip(o.opts, states))
    new_states[i], dx = apply!(opt, state, x, dx, dxs...)
  end

  return new_states, dx
end

function Base.show(io::IO, c::OptimiserChain)
  print(io, "OptimiserChain(")
  join(io, c.opts, ", ")
  print(io, ")")
end
