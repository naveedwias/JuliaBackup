
abstract type FEEvaluator{T <: Real, TvG <: Real, TiG <: Integer} end

struct SingleFEEvaluator{T <: Real, TvG <: Real, TiG <: Integer, operator, FEType, EG, FType_basis <: Function, FType_coeffs <: Function, FType_subset <: Function, FType_jac <: Function} <: FEEvaluator{T, TvG, TiG}
    citem::Base.RefValue{Int}                   # current item
    FE::FESpace{TvG,TiG,FEType}                 # link to full FE (e.g. for coefficients)
    FE2::Union{Nothing, FESpace{TvG,TiG}}       # link to other FE (if needed, e.g. for reconstruction)
    L2G::L2GTransformer{TvG, TiG, EG}           # local2global mapper
    L2GAinv::Array{TvG,2}                       # 2nd heap for transformation matrix (e.g. Piola + mapderiv)
    iteminfo::Array{TvG,1}                      # (e.g. current determinant for Hdiv, current tangent)
    xref::Array{Array{T,1},1}                   # xref of quadrature formula
    refbasis::FType_basis                       # function to call to evaluate basis function on reference geometry
    refbasisvals::Array{Array{T,2},1}           # basis evaluation on EG reference cell 
    refbasisderivvals::Array{T,3}               # additional values to evaluate operator
    derivorder::Int                             # order of derivatives that are needed
    Dresult::Union{Nothing,DiffResults.DiffResult}      # DiffResults for ForwardDiff handling
    Dcfg::Union{Nothing,ForwardDiff.DerivativeConfig, ForwardDiff.JacobianConfig}    # config for ForwardDiff handling
    jacobian_wrap::FType_jac
    offsets::Array{Int,1}                       # offsets for gradient entries of each dof
    offsets2::Array{Int,1}                      # offsets for dof entries of each gradient (on ref)
    cvals::Array{T,3}                           # current operator vals on item
    coefficients::Array{T,2}                    # coefficients for finite element
    coefficients2::Array{T,2}                   # additional coefficients for reconstruction
    coefficients3::AbstractArray{T,2}           # coefficients for operator (e.g. TangentialGradient)
    coeffs_handler::FType_coeffs                # function to call to get coefficients for finite element
    subset_handler::FType_subset                # function to call to get linear independent subset of basis on cell
    reconst_handler::Union{Nothing, ReconstructionHandler{T, TiG}} # handler for reconstruction coefficients (if needed)
    current_subset::Array{Int,1}                # current indices of subset of linear independent basis functions
    compressiontargets::Array{Int,1}            # some operators allow for compressed storage (e.g. SymmetricGradient)
end



function FEEvaluator(FE::FESpace{TvG,TiG,FEType,FEAPT}, operator, qrule::QuadratureRule{TvR,EG}; T = Float64, AT = ON_CELLS) where {TvG, TiG, TvR, FEType <: AbstractFiniteElement, EG <: AbstractElementGeometry, FEAPT <: AssemblyType}
    
    xref = qrule.xref
    xgrid = FE.xgrid
    L2G = L2GTransformer(EG, xgrid, AT)
    L2GAinv = copy(L2G.A)

    # get effective assembly type for basis
    # depending on the AT and the AT of the FESpace
    FEAT = GradientRobustMultiPhysics.EffAT4AssemblyType(FEAPT,AT)

    @debug "Creating FEEvaluator for $FEType, EG = $EG, operator = $operator, FEAT = $FEAT, AT = $AT"

    # collect basis function information
    ndofs4item::Int = 0
    refbasis = get_basis(FEAT, FEType, EG)
    ndofs4item = get_ndofs(FEAT, FEType, EG)
    ndofs4item_all = get_ndofs_all(FEAT, FEType, EG)

    # determine size of operator evaluation
    ncomponents::Int = get_ncomponents(FEType)
    if AT <: Union{ON_BFACES,<:ON_FACES,<:ON_EDGES,ON_BEDGES}
        if FEType <: AbstractHdivFiniteElement ||  FEType <: AbstractHcurlFiniteElement
            ncomponents = 1
        end
    end    
    edim = max(1,dim_element(EG))
    xdim = size(FE.xgrid[Coordinates],1)
    resultdim = Int(Length4Operator(operator,edim,ncomponents))

    # evaluate basis on reference domain
    refbasisvals = Array{Array{T,2},1}(undef,length(xref));
    for i = 1 : length(xref)
        refbasisvals[i] = zeros(T,ndofs4item_all,ncomponents)
    end    

    # set coefficient handlers needed for basis evaluation
    coefficients = zeros(T,0,0)
    coeff_handler = NothingFunction
    if FEType <: Union{AbstractH1FiniteElementWithCoefficients, AbstractHdivFiniteElement, AbstractHcurlFiniteElement}
        coefficients = ones(T,ncomponents,ndofs4item)
        coeff_handler = get_coefficients(FEAT, FE, EG)
    end    

    # set subset handler (only relevant if ndofs4item_all > ndofs4item)
    subset_handler = get_basissubset(FEAT, FE, EG)

    # prepare offsets and additional coefficients
    offsets = 0:edim:((ncomponents-1)*edim) # edim steps
    if ndofs4item_all > 0
        offsets2 = 0:ndofs4item_all:max(edim,ncomponents)*ndofs4item_all
    else
        @warn "ndofs = 0 for FEType = $FEType on EG = $EG"
        offsets2 = []
    end
    compressiontargets = _prepare_compressiontargets(operator, FE.xgrid, AT, edim)
    coefficients3 = _prepare_additional_coefficients(operator, FE.xgrid, AT, edim)
    current_eval = zeros(T,resultdim,ndofs4item,length(xref))

    derivorder = NeededDerivative4Operator(operator)
    if derivorder == 0
        for i = 1 : length(xref)
            # evaluate basis functions at quadrature point
            refbasis(refbasisvals[i], xref[i])
        end    
        refbasisderivvals = zeros(T,0,0,0)
        if operator <: Identity || operator <: IdentityDisc
            for i = 1 : length(xref), j = 1 : ndofs4item, k = 1 : ncomponents
                current_eval[k,j,i] = refbasisvals[i][j,k]
            end
        elseif operator <: IdentityComponent
            for i = 1 : length(xref), j = 1 : ndofs4item
                current_eval[1,j,i] = refbasisvals[i][j,operator.parameters[1]]
            end
        end
        Dcfg = nothing
        Dresult = nothing
        jacobian_wrap = NothingFunction
    elseif derivorder > 0
        # get derivatives of basis on reference geometry
        if derivorder == 1
            refbasisderivvals = zeros(T,ndofs4item_all*ncomponents,edim,length(xref))
        elseif derivorder == 2
            refbasisderivvals = zeros(T,ndofs4item_all*ncomponents*edim,edim,length(xref))
        end
        Dresult, Dcfg, jacobian_wrap = _prepare_derivatives(refbasisderivvals, refbasis, xref, derivorder, ndofs4item_all, ncomponents)

        if operator <: SymmetricGradient
            # the following mapping tells where each entry of the full gradient lands in the reduced vector
            @assert ncomponents == edim "SymmetricGradient requires a square matrix as gradient (ncomponents == dim is needed)"
            @assert edim > 1 "SymmetricGradient makes only sense for dim > 1, please use Gradient"
        elseif operator <: SymmetricHessian
            cl = maximum(compressiontargets)
            for n = 1 : ncomponents
                append!(compressiontargets,compressiontargets .+ cl)
            end
        end
    end

    FE2 = nothing
    coefficients2 = zeros(T,0,0)
    reconst_handler = nothing

    return SingleFEEvaluator{T,TvG,TiG,operator,FEType,EG,typeof(refbasis),typeof(coeff_handler),typeof(subset_handler),typeof(jacobian_wrap)}(Ref(0),FE,FE2,L2G,L2GAinv,zeros(T,xdim+1),xref,refbasis,refbasisvals,refbasisderivvals,derivorder,Dresult,Dcfg,jacobian_wrap,offsets,offsets2,current_eval,coefficients,coefficients2,coefficients3, coeff_handler, subset_handler, reconst_handler, 1:ndofs4item, compressiontargets)
end    


# constructor for ReconstructionIdentity, ReconstructionDivergence, ReconstructionGradient
function FEEvaluator(FE::FESpace{TvG,TiG,FEType,FEAPT}, operator::Type{<:Union{<:ReconstructionIdentity{FETypeReconst},ReconstructionNormalFlux{FETypeReconst},ReconstructionDivergence{FETypeReconst},<:ReconstructionGradient{FETypeReconst}}}, qrule::QuadratureRule{TvR,EG}; T = Float64, AT = ON_CELLS) where {TvG, TiG, TvR, FEType <: AbstractFiniteElement, FETypeReconst <: AbstractFiniteElement, EG <: AbstractElementGeometry, FEAPT <: AssemblyType}
    
    @debug "Creating FEBasisEvaluator for $operator operator of $FEType on $EG"

    # generate reconstruction space
    # avoid computation of full dofmap
    # we will just use local basis functions
    xgrid = FE.xgrid
    FE2 = FESpace{FETypeReconst}(xgrid)
    L2G = L2GTransformer(EG, xgrid,AT)
    L2GAinv = copy(L2G.A)

    # collect basis function information
    ncomponents::Int = get_ncomponents(FEType)
    ncomponents2::Int = get_ncomponents(FETypeReconst)
    if AT <: Union{ON_BFACES,<:ON_FACES}
        if FETypeReconst <: AbstractHdivFiniteElement
            ncomponents2 = 1
        end
    end
    refbasis = get_basis(AT, FEType, EG)
    refbasis_reconst = get_basis(AT, FETypeReconst, EG)
    ndofs4item = get_ndofs(AT, FEType, EG)
    ndofs4item2 = get_ndofs(AT, FETypeReconst, EG)
    ndofs4item2_all = get_ndofs_all(AT, FETypeReconst, EG)    

    # evaluate reconstruction basis
    xref = qrule.xref
    refbasisvals = Array{Array{T,2},1}(undef,length(xref));
    for i = 1 : length(xref)
        # evaluate basis functions at quadrature point
        refbasisvals[i] = zeros(T,ndofs4item2_all,ncomponents2)
        refbasis_reconst(refbasisvals[i], xref[i])
    end    

    # set coefficient handlers needed for basis evaluation (for both FEType and FETypereconst)
    if FETypeReconst <: Union{AbstractH1FiniteElementWithCoefficients, AbstractHdivFiniteElement}
        coefficients = ones(T,ncomponents,ndofs4item2)
        coeff_handler = get_coefficients(AT, FE2, EG)
    else
        coefficients = zeros(T,0,0)
        coeff_handler = NothingFunction
    end    
    coefficients2 = zeros(T,ndofs4item,ndofs4item2)

    # set subset handler (only relevant if ndofs4item_all > ndofs4item)
    subset_handler = get_basissubset(AT, FE2, EG)

    # get reconstruction coefficient handlers
    reconst_handler = ReconstructionHandler(FE,FE2,AT,EG)

    # compute refbasisderivvals and further coefficients needed for operator eval
    edim = dim_element(EG)
    xdim = size(FE.xgrid[Coordinates],1)
    offsets = 0:edim:((ncomponents-1)*edim);
    offsets2 = 0:ndofs4item2_all:ncomponents*ndofs4item2_all
    coefficients3 = _prepare_additional_coefficients(operator, FE.xgrid, AT, edim)
    compressiontargets = _prepare_compressiontargets(operator, FE.xgrid, AT, edim)
    resultdim = Int(Length4Operator(operator,edim,ncomponents))
    current_eval = zeros(T,resultdim,ndofs4item,length(xref))
    derivorder = NeededDerivative4Operator(operator)
    if derivorder == 0
        # refbasisderivvals are used as a cache for the reconstruction basis
        refbasisderivvals = zeros(T,ncomponents,ndofs4item2_all,length(xref));
        Dcfg = nothing
        Dresult = nothing
        jacobian_wrap = NothingFunction
    elseif derivorder == 1
        # derivatives of the reconstruction basis on the reference domain are computed
        refbasisderivvals = zeros(T,ndofs4item2_all*ncomponents2,edim,length(xref));
        Dresult, Dcfg, jacobian_wrap = _prepare_derivatives(refbasisderivvals, refbasis_reconst, xref, derivorder, ndofs4item2_all, ncomponents2)
        coefficients3 = zeros(T,resultdim,ndofs4item2)
    end
    
    return SingleFEEvaluator{T,TvG,TiG,operator,FEType,EG,typeof(refbasis),typeof(coeff_handler),typeof(subset_handler),typeof(jacobian_wrap)}(Ref(0),FE,FE2,L2G,L2GAinv,zeros(T,xdim+1),xref,refbasis,refbasisvals,refbasisderivvals,derivorder,Dresult,Dcfg,jacobian_wrap,offsets,offsets2,current_eval,coefficients,coefficients2,coefficients3, coeff_handler, subset_handler, reconst_handler, 1:ndofs4item, compressiontargets)
end    

_prepare_additional_coefficients(::Type{<:AbstractFunctionOperator}, xgrid, AT, edim) = zeros(Float64,0,0)
_prepare_additional_coefficients(::Type{<:NormalFlux}, xgrid, AT, edim) = AT == ON_BFACES ? view(xgrid[FaceNormals], :, xgrid[BFaceFaces]) : xgrid[FaceNormals]
_prepare_additional_coefficients(::Type{<:TangentialGradient}, xgrid, AT, edim) = xgrid[FaceNormals]
function _prepare_additional_coefficients(::Type{<:TangentFlux}, xgrid, AT, edim)
    if edim == 2
        return _prepare_additional_coefficients(NormalFlux, AT, edim)
    else
        return AT == ON_BEDGES ? view(xgrid[EdgeTangents], :, xgrid[BEdgeEdges]) : xgrid[EdgeTangents]
    end
end

_prepare_compressiontargets(::Type{<:AbstractFunctionOperator}, xgrid, AT, edim) = zeros(Float64,0)
_prepare_compressiontargets(::Type{<:SymmetricGradient}, xgrid, AT, edim) = edim == 2 ? [1,3,3,2] : [1,6,5,6,2,4,5,4,3]
_prepare_compressiontargets(::Type{<:SymmetricHessian}, xgrid, AT, edim) = edim == 1 ? [1] : edim == 2 ? [1,3,3,2] : [1,6,5,6,2,4,5,4,3]


function _prepare_derivatives(refbasisderivvals, refbasis, xref, derivorder, ndofs4item_all, ncomponents; Dcfg = "init", Dresult = "init", jac_wrap = NothingFunction)

    # derivatives of the basis on the reference domain are computed
    # by ForwardDiff, to minimise memory allocations and be able
    # to rebase the quadrature points later (e.g. when evaluating cuts through cells)
    # we use DiffResults and JacobianConfig of ForwardDiff and save these in the struct

    if Dcfg == "init" || Dresult == "init" || jac_wrap == NothingFunction

        edim = size(refbasisderivvals,2)
        result_temp = zeros(Float64,ndofs4item_all,ncomponents)
        result_temp2 = zeros(Real,ndofs4item_all,ncomponents)
        input_temp = Vector{Float64}(undef,edim)
        jac_temp = Matrix{Float64}(undef,ndofs4item_all*ncomponents,edim)
        Dresult = DiffResults.DiffResult(result_temp,jac_temp)
        Dcfg = ForwardDiff.JacobianConfig(refbasis, result_temp, input_temp)

        function jacobian_wrap(x)
            fill!(result_temp,0.0)
            ForwardDiff.vector_mode_jacobian!(Dresult, refbasis, result_temp, x, Dcfg)
            return DiffResults.jacobian(Dresult)
        end
        jac_wrap = jacobian_wrap
        if derivorder == 1 ## first order derivatives
            jac::Array{Float64,2} = DiffResults.jacobian(Dresult)
        elseif derivorder == 2
            # todo: use DiffResults for hessian evaluation 
            function refbasis_wrap(xref)
                fill!(result_temp2,0)
                refbasis(result_temp2,xref)
                return result_temp2
            end

            jac_function = x -> ForwardDiff.jacobian(refbasis_wrap, x)
            function hessian_wrap(xref)
                return ForwardDiff.jacobian(jac_function, xref)
            end
        end
    end

    if derivorder == 1 ## first order derivatives
        for i = 1 : length(xref)
            # evaluate gradients of basis function
            # = list of vectors [du_k/dx_1; du_k,dx_2]

            jac = jac_wrap(xref[i])

            for j = 1 : ndofs4item_all*ncomponents, k = 1 : edim
                refbasisderivvals[j,k,i] = jac[j,k];
            end
        end
    elseif derivorder == 2 # second order derivatives
        for i = 1 : length(xref)
            # evaluate second derivatives of basis function
            refbasisderivvals[:,:,i] = hessian_wrap(xref[i])
        end 
    end
    return Dresult, Dcfg, jac_wrap
end

# ## relocates evaluation points (needs mutable FEB) used by segment integrator/point evaluator
# function relocate_xref!(FEB::SingleFEEvaluator{<:Real,<:Real,<:Integer,operator,FEType}, new_xref) where {FEType, operator}
#     for j = 1 : length(FEB.xref[1])
#         FEB.xref[1][j] = new_xref[j]
#     end
#     if FEB.derivorder == 0
#         # evaluate basis functions at quadrature point
#         FEB.refbasis(FEB.refbasisvals[1], new_xref)
#         if FEType <: AbstractH1FiniteElement # also reset cvals for operator evals that stay the same for all cells
#             if operator <: Identity || operator <: IdentityDisc
#                 for j = 1 : size(FEB.refbasisvals[1],1), k = 1 : size(FEB.refbasisvals[1],2)
#                     FEB.cvals[k,j,1] = FEB.refbasisvals[1][j,k]
#                 end
#             elseif operator <: IdentityComponent
#                 for j = 1 : size(FEB.refbasisvals[1],1)
#                     FEB.cvals[1,j,1] = FEB.refbasisvals[1][j,operator.parameters[1]]
#                 end
#             end
#         end
#     elseif FEB.derivorder > 0
#         _prepare_derivatives(FEB.refbasisderivvals, FEB.refbasis, FEB.xref, FEB.derivorder, size(FEB.refbasisvals[1],1), length(FEB.offsets); Dcfg = FEB.Dcfg, Dresult = FEB.Dresult)
#     end
#     FEB.citem[] = 0 # reset citem to allows recomputation if FEB.cvals (if multiple consecutive relocations are done in the same cell)
#     return nothing
# end

## relocates evaluation points (needs mutable FEB) used by segment integrator/point evaluator
function relocate_xref!(FEB::SingleFEEvaluator{<:Real,<:Real,<:Integer,operator,FEType}, new_xref) where {FEType, operator}
    if typeof(new_xref) <: Vector{<:Real} #length(new_xref) == length(FEB.xref[1])
        nqp = 1
        for j = 1 : length(FEB.xref[1])
            FEB.xref[1][j] = new_xref[j]
        end
    else
        nqp = length(new_xref)
        for j = 1 : length(FEB.xref)
            FEB.xref[j] = new_xref[j]
        end
    end
    if FEB.derivorder == 0
        # evaluate basis functions at new quadrature point(s)
        for j = 1 : nqp
            FEB.refbasis(FEB.refbasisvals[j], FEB.xref[j])
        end
        if FEType <: AbstractH1FiniteElement # also reset cvals for operator evals that stay the same for all cells
            if operator <: Identity || operator <: IdentityDisc
                for qp = 1 : nqp
                    for j = 1 : size(FEB.refbasisvals[1],1), k = 1 : size(FEB.refbasisvals[1],2)
                        FEB.cvals[k,j,qp] = FEB.refbasisvals[qp][j,k]
                    end
                end
            elseif operator <: IdentityComponent
                for qp = 1 : nqp
                    for j = 1 : size(FEB.refbasisvals[1],1)
                        FEB.cvals[1,j,qp] = FEB.refbasisvals[qp][j,operator.parameters[1]]
                    end
                end
            end
        end
    elseif FEB.derivorder > 0
        _prepare_derivatives(FEB.refbasisderivvals, FEB.refbasis, FEB.xref, FEB.derivorder, size(FEB.refbasisvals[1],1), length(FEB.offsets); Dcfg = FEB.Dcfg, Dresult = FEB.Dresult)
    end
    FEB.citem[] = 0 # reset citem to allows recomputation if FEB.cvals (if multiple consecutive relocations are done in the same cell)
    return nothing
end

## general call to update subset
function _update_subset!(FEBE::FEEvaluator)
    subset = FEBE.current_subset
    if FEBE.subset_handler != GradientRobustMultiPhysics.NothingFunction
        FEBE.subset_handler(subset, FEBE.citem[])
    end
    return subset
end

## general call to update trafo
function _update_trafo!(FEBE::FEEvaluator)
    update_trafo!(FEBE.L2G, FEBE.citem[])
    L2GAinv = FEBE.L2GAinv
    if !FEBE.L2G.nonlinear
        mapderiv!(L2GAinv, FEBE.L2G, nothing)
    else
        @error "nonlinear local2global transformations not yet supported"
    end
    return L2GAinv
end

## general call to update trafo for HDIV
function _update_piola!(FEBE::FEEvaluator)
    update_trafo!(FEBE.L2G, FEBE.citem[])
    L2GM = FEBE.L2G.A # need matrix for Piola trafo
    if FEBE.L2G.nonlinear
        @error "nonlinear local2global transformations not yet supported"
    end
    return L2GM
end

## general call to update coefficients
function _update_coefficients!(FEBE::FEEvaluator)
    coefficients = FEBE.coefficients
    FEBE.coeffs_handler(coefficients, FEBE.citem[])
    return coefficients
end

## general call that checks item (but causes 1 allocations)
function update_basis!(FEBE, item)
    if FEBE.citem[] == item
    else
        FEBE.citem[] = item
        update_basis!(FEBE)
    end
end


## error function
function update_basis!(FEBE::SingleFEEvaluator{<:Real,<: Real,<:Integer,operator,FEType}) where {operator, FEType}
    @error "no update_basis! available for operator $operator of $FEType"
end


include("feevaluator_h1.jl")
include("feevaluator_hdiv.jl")
include("feevaluator_hcurl.jl")




"""
````
    eval_febe!(result, FEBE::FEBasisEvaluator, j::Int, i::Int, offset::Int = 0, factor = 1)
````

Evaluate the j-th basis function of the FEBasisEvaluator at the i-th quadrature point adn writes the (possibly vector-valued) evaluation into result (beginning at offset and with the specified factor).

"""
function eval_febe!(result, FEBE::FEEvaluator, j::Int, i, offset = 0, factor = 1)
    for k = 1 : size(FEBE.cvals,1)
        result[offset + k] = FEBE.cvals[k,j,i] * factor
    end  
    return nothing
end

"""
````
    eval_febe!(result, FEBE::FEBasisEvaluator, j::Int, i::Int, offset::Int = 0, factor = 1)
````

Evaluates the linear combination of the basisfunction with given coefficients at the i-th quadrature point and writes the (possibly vector-valued) evaluation into result (beginning at offset and with the specified factor).

"""
function eval_febe!(result, FEBE::FEEvaluator, coefficients, i, offset = 0, factor = 1)
    for dof_i = 1 : size(FEBE.cvals,2) # ndofs4item
        for k = 1 : size(FEBE.cvals,1)
            result[offset+k] += coefficients[dof_i] * FEBE.cvals[k,dof_i,i] * factor 
        end    
    end 
    return nothing
end



##### additional infrastructure for pairs of FE evaluators

struct SharedCValView{T} <: AbstractArray{T,3}
    cvals::Array{Array{T,3},1}
    k2cvalindex::Array{Int,1}
    offsets::Array{Int,1}
end

Base.getindex(SCV::SharedCValView,i::Int,j::Int,k::Int) = SCV.cvals[SCV.k2cvalindex[i]][i-SCV.offsets[i],j,k]
Base.size(SCV::SharedCValView) = [SCV.offsets[end] + size(SCV.cvals[end],1), size(SCV.cvals[end],2), size(SCV.cvals[end],3)]
Base.size(SCV::SharedCValView,i) = (i == 1) ? SCV.offsets[end] + size(SCV.cvals[end],1) : size(SCV.cvals[end],i)

# collects two FEBasisEvaluators
struct FEEvaluatorPair{T,TvG,TiG,FEType,FEB1Type,FEB2Type} <: FEEvaluator{T,TvG,TiG}
    citem::Base.RefValue{Int}               # current item
    FE::FESpace{TvG,TiG,FEType}             # link to full FE (e.g. for coefficients)
    FEB1::FEB1Type                          # first FEBasisEvaluator
    FEB2::FEB2Type                          # second FEBasisEvaluator
    cvals::SharedCValView{T}
    L2G::L2GTransformer{TvG,TiG}            # local2global mapper
    xref::Array{Array{T,1},1}               # xref of quadrature formula
end

# collects three FEBasisEvaluators
struct FEEvaluatorTriple{T,TvG,TiG,FEType,FEB1Type,FEB2Type,FEB3Type} <: FEEvaluator{T,TvG,TiG}
    citem::Base.RefValue{Int}               # current item
    FE::FESpace{TvG,TiG,FEType}             # link to full FE (e.g. for coefficients)
    FEB1::FEB1Type                          # first FEBasisEvaluator
    FEB2::FEB2Type                          # second FEBasisEvaluator
    FEB3::FEB3Type                          # third FEBasisEvaluator
    cvals::SharedCValView{T}
    L2G::L2GTransformer{TvG,TiG}            # local2global mapper
    xref::Array{Array{T,1},1}               # xref of quadrature formula
end

function FEEvaluator(FE::FESpace{TvG,TiG,FEType,FEAPT}, operator::Type{<:OperatorPair}, qrule::QuadratureRule{TvR,EG}; T = Float64, AT = ON_CELLS) where {TvG, TiG, TvR, FEType <: AbstractFiniteElement, EG <: AbstractElementGeometry, FEAPT <: AssemblyType}
    operator1 = operator.parameters[1]
    operator2 = operator.parameters[2]
    xref = qrule.xref
    FEB1 = FEEvaluator(FE, operator1, qrule; T = T, AT = AT)
    FEB2 = FEEvaluator(FE, operator2, qrule; T = T, AT = AT)
    ncomponents = size(FEB1.cvals,1) + size(FEB2.cvals,1)
    indexes = ones(Int,ncomponents)
    offsets = zeros(Int,ncomponents)
    for j = 1 : size(FEB2.cvals,1)
        indexes[size(FEB1.cvals,1)+j] = 2
        offsets[size(FEB1.cvals,1)+j] = size(FEB1.cvals,1)
    end
    cvals = SharedCValView([FEB1.cvals,FEB2.cvals],indexes,offsets)
    edim = dim_element(EG)
    ndofs = size(FEB1.cvals,2)
    return FEEvaluatorPair{T,TvG,TiG,FEType,typeof(FEB1),typeof(FEB2)}(Ref(0),FEB1.FE,FEB1,FEB2,cvals,FEB1.L2G,xref)
end

function FEEvaluator(FE::FESpace{TvG,TiG,FEType,FEAPT}, operator::Type{<:OperatorTriple}, qrule::QuadratureRule{TvR,EG}; T = Float64, AT = ON_CELLS) where {TvG, TiG, TvR, FEType <: AbstractFiniteElement, EG <: AbstractElementGeometry, FEAPT <: AssemblyType}
    operator1 = operator.parameters[1]
    operator2 = operator.parameters[2]
    operator3 = operator.parameters[3]
    xref = qrule.xref
    FEB1 = FEEvaluator(FE, operator1, qrule; T = T, AT = AT)
    FEB2 = FEEvaluator(FE, operator2, qrule; T = T, AT = AT)
    FEB3 = FEEvaluator(FE, operator3, qrule; T = T, AT = AT)
    ncomponents = size(FEB1.cvals,1) + size(FEB2.cvals,1) + size(FEB3.cvals,1)
    indexes = ones(Int,ncomponents)
    offsets = zeros(Int,ncomponents)
    for j = 1 : size(FEB2.cvals,1)
        indexes[size(FEB1.cvals,1)+j] = 2
        offsets[size(FEB1.cvals,1)+j] = size(FEB1.cvals,1)
    end
    for j = 1 : size(FEB3.cvals,1)
        indexes[size(FEB1.cvals,1)+size(FEB2.cvals,1)+j] = 3
        offsets[size(FEB1.cvals,1)+size(FEB2.cvals,1)+j] = size(FEB1.cvals,1)+size(FEB2.cvals,1)
    end
    cvals = SharedCValView([FEB1.cvals,FEB2.cvals,FEB3.cvals],indexes,offsets)
    edim = dim_element(EG)
    ndofs = size(FEB1.cvals,2)
    return FEEvaluatorTriple{T,TvG,TiG,FEType,typeof(FEB1),typeof(FEB2),typeof(FEB3)}(Ref(0),FEB1.FE,FEB1,FEB2,FEB3,cvals,FEB1.L2G,xref)
end

function update_basis!(FEBE::FEEvaluatorPair)
    FEBE.FEB1.citem[] = FEBE.citem[]
    FEBE.FEB2.citem[] = FEBE.citem[]
    update_basis!(FEBE.FEB1)
    update_basis!(FEBE.FEB2)
    return nothing
end

function update_basis!(FEBE::FEEvaluatorTriple)
    FEBE.FEB1.citem[] = FEBE.citem[]
    FEBE.FEB2.citem[] = FEBE.citem[]
    FEBE.FEB3.citem[] = FEBE.citem[]
    update_basis!(FEBE.FEB1)
    update_basis!(FEBE.FEB2)
    update_basis!(FEBE.FEB3)
    return nothing
end
