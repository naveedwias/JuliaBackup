"""
````
abstract type HDIVBDM2{edim} <: AbstractHdivFiniteElement where {edim<:Int}
````

Hdiv-conforming vector-valued (ncomponents = edim) Brezzi-Douglas-Marini space of order 2

allowed ElementGeometries:
- Triangle2D
"""
abstract type HDIVBDM2{edim} <: AbstractHdivFiniteElement where {edim<:Int} end

function Base.show(io::Core.IO, ::Type{<:HDIVBDM2{edim}}) where {edim}
    print(io,"HDIVBDM2{$edim}")
end

get_ncomponents(FEType::Type{<:HDIVBDM2}) = FEType.parameters[1]
get_ndofs(::Union{Type{<:ON_FACES}, Type{<:ON_BFACES}}, FEType::Type{<:HDIVBDM2}, EG::Type{<:AbstractElementGeometry1D}) = 3
get_ndofs(::Type{ON_CELLS}, FEType::Type{<:HDIVBDM2}, EG::Type{<:AbstractElementGeometry2D}) = 3*num_faces(EG) + 3

get_polynomialorder(::Type{<:HDIVBDM2{2}}, ::Type{<:Edge1D}) = 2;
get_polynomialorder(::Type{<:HDIVBDM2{2}}, ::Type{<:Triangle2D}) = 2;

get_dofmap_pattern(FEType::Type{<:HDIVBDM2{2}}, ::Type{CellDofs}, EG::Type{<:AbstractElementGeometry}) = "f3i3"
get_dofmap_pattern(FEType::Type{<:HDIVBDM2{2}}, ::Union{Type{FaceDofs},Type{BFaceDofs}}, EG::Type{<:AbstractElementGeometry}) = "i3"

isdefined(FEType::Type{<:HDIVBDM2}, ::Type{<:Triangle2D}) = true

interior_dofs_offset(::Type{<:ON_CELLS}, ::Type{<:HDIVBDM2{2}}, ::Type{<:Triangle2D}) = 9


function ExtendableGrids.interpolate!(Target::AbstractArray{T,1}, FE::FESpace{Tv,Ti,FEType,APT}, ::Type{ON_FACES}, data; items = [], time = 0) where {T,Tv,Ti,FEType <: HDIVBDM2,APT}
    ncomponents = get_ncomponents(FEType)
    if items == []
        items = 1 : num_sources(FE.xgrid[FaceNodes])
    end

    # integrate normal flux of exact_function over edges
    xFaceNormals = FE.xgrid[FaceNormals]
    nfaces = num_sources(xFaceNormals)
    function normalflux_eval(result, kwargs...)
        eval_data!(data) 
        result[1] = dot(data.val, view(xFaceNormals,:,data.item[1]))
        result[2] = result[1] * (data.xref[1] - 1//ncomponents) 
        result[3] = result[1] * (data.xref[1]^2 - data.xref[1] + 1//6)
        return nothing
    end   
    edata_function = DataFunction(normalflux_eval, [3, ncomponents]; dependencies = dependencies(data; enforce = "IL"), bonus_quadorder = data.bonus_quadorder + 2)
    couple!(data, edata_function)
    set_time!(data, time)
    integrate!(Target, FE.xgrid, ON_FACES, edata_function; items = items, time = time, index_offsets = [0, nfaces, 2*nfaces])
end

function ExtendableGrids.interpolate!(Target::AbstractArray{T,1}, FE::FESpace{Tv,Ti,FEType,APT}, ::Type{ON_CELLS}, data; items = [], time = 0) where {T,Tv,Ti,FEType <: HDIVBDM2,APT}
    # delegate cell faces to face interpolation
    subitems = slice(FE.xgrid[CellFaces], items)
    interpolate!(Target, FE, ON_FACES, data; items = subitems, time = time)

    # set values of interior BDM2 functions as piecewise best-approximation
    ncomponents = get_ncomponents(FEType)
    EG = (ncomponents == 2) ? Triangle2D : Tetrahedron3D
    ndofs = get_ndofs(ON_CELLS,FEType,EG)
    interior_offset::Int = 9
    nidofs::Int = ndofs - interior_offset
    ncells = num_sources(FE.xgrid[CellNodes])
    xCellVolumes::Array{Tv,1} = FE.xgrid[CellVolumes]
    xCellDofs::DofMapTypes{Ti} = FE[CellDofs]
    qf = QuadratureRule{T,EG}(max(4,2+data.bonus_quadorder))
    FEB = FEEvaluator(FE, Identity, qf; T = T)

    # evaluation of gradient of P1 functions
    FE3 = H1P1{1}
    FES3 = FESpace{FE3,ON_CELLS}(FE.xgrid)
    FEBP1 = FEEvaluator(FES3, Gradient, qf; T = T)
    # evaluation of curl of bubble functions
    FE4 = H1BUBBLE{1}
    FES4 = FESpace{FE4,ON_CELLS}(FE.xgrid)
    FEBB = FEEvaluator(FES4, CurlScalar, qf; T = T)


    if items == []
        items = 1 : ncells
    end

    interiordofs = zeros(Int,nidofs)
    basisvals::Array{T,3} = FEB.cvals
    basisvalsP1::Array{T,3} = FEBP1.cvals
    basisvalsB::Array{T,3} = FEBB.cvals
    IMM_face = zeros(T,nidofs,interior_offset)
    IMM = zeros(T,nidofs,nidofs)
    lb = zeros(T,nidofs)
    temp::T = 0
    set_time!(data, time)
    for cell in items
        # update basis
        update_basis!(FEB,cell)
        update_basis!(FEBP1,cell)
        update_basis!(FEBB,cell)
        fill!(IMM,0)
        fill!(IMM_face,0)
        fill!(lb,0)

        # quadrature loop
        for i = 1 : length(qf.w)
            # right-hand side : f times grad(P1),curl(bubble)
            eval_trafo!(data.x,FEB.L2G,FEB.xref[i])
            eval_data!(data)
            data.val .*= xCellVolumes[cell] * qf.w[i]
            for dof = 1:nidofs
                for k = 1 : ncomponents
                    if dof < 3
                        lb[dof] += data.val[k] * basisvalsP1[k,dof,i]
                    elseif dof == 3
                        lb[dof] += data.val[k] * basisvalsB[k,1,i]
                    end
                end

                # mass matrix of interior basis functions
                for dof2 = 1 : nidofs-1
                    temp = 0
                    for k = 1 : ncomponents
                        temp += basisvals[k,interior_offset + dof,i] * basisvalsP1[k,dof2,i]
                    end
                    IMM[dof2,dof] += temp * xCellVolumes[cell] * qf.w[i]
                end
                temp = 0
                for k = 1 : ncomponents
                    temp += basisvals[k,interior_offset + dof,i] * basisvalsB[k,1,i]
                end
                IMM[3,dof] += temp * xCellVolumes[cell] * qf.w[i]

                # mass matrix of face basis functions
                for dof2 = 1 : interior_offset
                    temp = 0
                    if dof < 3
                        for k = 1 : ncomponents
                            temp += basisvalsP1[k,dof,i] * basisvals[k,dof2,i]
                        end
                    elseif dof == 3
                        for k = 1 : ncomponents
                            temp += basisvalsB[k,1,i] * basisvals[k,dof2,i]
                        end
                    end
                    IMM_face[dof,dof2] += temp * xCellVolumes[cell] * qf.w[i]
                end
            end
        end

        # subtract face interpolation from right-hand side
        for dof = 1 : nidofs, dof2 = 1 : interior_offset
            lb[dof] -= Target[xCellDofs[dof2,cell]] * IMM_face[dof,dof2]
        end
        
        # solve local system
        for dof = 1 : nidofs
            interiordofs[dof] = xCellDofs[interior_offset + dof,cell] 
        end
        Target[interiordofs] = IMM\lb
    end
end

## only normalfluxes on faces
function get_basis(::Union{Type{<:ON_FACES}, Type{<:ON_BFACES}}, ::Type{<:HDIVBDM2}, ::Type{<:AbstractElementGeometry1D})
    function closure(refbasis,xref)
        refbasis[1,1] = 1
        refbasis[2,1] = 12*(xref[1] - 1//2) # linear normal-flux of BDM2 function
        refbasis[3,1] = 180*(xref[1]^2 - xref[1] + 1//6) # quadratic normal-flux of BDM2 function
    end
end

function get_basis(::Type{ON_CELLS}, ::Type{HDIVBDM2{2}}, ::Type{<:Triangle2D})
    function closure(refbasis, xref)
        refbasis[end] = 1 - xref[1] - xref[2]

        # RT0 basis
        refbasis[1,1] = xref[1];    refbasis[1,2] = xref[2]-1
        refbasis[4,1] = xref[1];    refbasis[4,2] = xref[2]
        refbasis[7,1] = xref[1]-1;  refbasis[7,2] = xref[2]
        # additional BDM1 functions on faces
        refbasis[2,1] = 6*xref[1];                  refbasis[2,2] = 6-12*xref[1]-6*xref[2]      
        refbasis[5,1] = -6*xref[1];                 refbasis[5,2] = 6*xref[2]                   
        refbasis[8,1] = 6*(xref[1]-1)+12*xref[2];   refbasis[8,2] = -6*xref[2]    
        for k = 1 : 2              
            # additional BDM2 face functions on faces
            refbasis[3,k] = -15*((refbasis[end] - 1//2)*refbasis[2,k] + refbasis[1,k])
            refbasis[6,k] = -15*((xref[1] - 1//2)*refbasis[5,k] + refbasis[4,k])
            refbasis[9,k] = -15*((xref[2] - 1//2)*refbasis[8,k] + refbasis[7,k])
            # additional BDM2 interior functions
            refbasis[10,k] = xref[2] * refbasis[2,k]
            refbasis[11,k] = refbasis[end] * refbasis[5,k]
            refbasis[12,k] = xref[1] * refbasis[8,k]
        end
    end
end


function get_coefficients(::Type{ON_CELLS}, FE::FESpace{Tv,Ti,<:HDIVBDM2,APT}, EG::Type{<:AbstractElementGeometry2D}) where {Tv,Ti,APT}
    xCellFaceSigns::Union{VariableTargetAdjacency{Int32},Array{Int32,2}} = FE.xgrid[CellFaceSigns]
    nfaces::Int = num_faces(EG)
    dim::Int = dim_element(EG)
    function closure(coefficients::Array{<:Real,2}, cell::Int)
        fill!(coefficients,1.0)
        # multiplication with normal vector signs (only RT0)
        for j = 1 : nfaces,  k = 1 : dim
            coefficients[k,3*j-2] = xCellFaceSigns[j,cell];
            coefficients[k,3*j] = xCellFaceSigns[j,cell];
        end
        return nothing
    end
end  
