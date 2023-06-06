"""
````
abstract type HDIVBDM1{edim} <: AbstractHdivFiniteElement where {edim<:Int}
````

Hdiv-conforming vector-valued (ncomponents = edim) lowest-order Brezzi-Douglas-Marini space

allowed ElementGeometries:
- Triangle2D
- Quadrilateral2D
- Tetrahedron3D
"""
abstract type HDIVBDM1{edim} <: AbstractHdivFiniteElement where {edim<:Int} end

function Base.show(io::Core.IO, ::Type{<:HDIVBDM1{edim}}) where {edim}
    print(io,"HDIVBDM1{$edim}")
end

get_ncomponents(FEType::Type{<:HDIVBDM1}) = FEType.parameters[1]
get_ndofs(::Union{Type{<:ON_FACES}, Type{<:ON_BFACES}}, FEType::Type{<:HDIVBDM1}, EG::Type{<:AbstractElementGeometry1D}) = 2
get_ndofs(::Union{Type{<:ON_FACES}, Type{<:ON_BFACES}}, FEType::Type{<:HDIVBDM1}, EG::Type{<:AbstractElementGeometry2D}) = 3
get_ndofs(::Type{ON_CELLS}, FEType::Type{<:HDIVBDM1}, EG::Type{<:AbstractElementGeometry2D}) = 2*num_faces(EG)
get_ndofs(::Type{ON_CELLS}, FEType::Type{<:HDIVBDM1}, EG::Type{<:AbstractElementGeometry3D}) = 3*num_faces(EG)
get_ndofs_all(::Type{ON_CELLS}, FEType::Type{<:HDIVBDM1}, EG::Type{<:AbstractElementGeometry3D}) = 4*num_faces(EG) # in 3D only 3 of 4 face dofs are used depending on orientation

get_polynomialorder(::Type{<:HDIVBDM1{2}}, ::Type{<:Edge1D}) = 1;
get_polynomialorder(::Type{<:HDIVBDM1{2}}, ::Type{<:Triangle2D}) = 1;
get_polynomialorder(::Type{<:HDIVBDM1{2}}, ::Type{<:Quadrilateral2D}) = 2;
get_polynomialorder(::Type{<:HDIVBDM1{3}}, ::Type{<:Triangle2D}) = 1;
get_polynomialorder(::Type{<:HDIVBDM1{3}}, ::Type{<:Tetrahedron3D}) = 1;

get_dofmap_pattern(FEType::Type{<:HDIVBDM1{2}}, ::Type{CellDofs}, EG::Type{<:AbstractElementGeometry}) = "f2"
get_dofmap_pattern(FEType::Type{<:HDIVBDM1{2}}, ::Union{Type{FaceDofs},Type{BFaceDofs}}, EG::Type{<:AbstractElementGeometry}) = "i2"

get_dofmap_pattern(FEType::Type{<:HDIVBDM1{3}}, ::Type{CellDofs}, EG::Type{<:AbstractElementGeometry}) = "f3"
get_dofmap_pattern(FEType::Type{<:HDIVBDM1{3}}, ::Union{Type{FaceDofs},Type{BFaceDofs}}, EG::Type{<:AbstractElementGeometry}) = "i3"

isdefined(FEType::Type{<:HDIVBDM1}, ::Type{<:Triangle2D}) = true
isdefined(FEType::Type{<:HDIVBDM1}, ::Type{<:Quadrilateral2D}) = true
isdefined(FEType::Type{<:HDIVBDM1}, ::Type{<:Tetrahedron3D}) = true


function ExtendableGrids.interpolate!(Target::AbstractArray{T,1}, FE::FESpace{Tv,Ti,FEType,APT}, ::Type{ON_FACES}, data; items = [], time = 0) where {T,Tv,Ti,FEType <: HDIVBDM1,APT}
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
        if ncomponents == 3
            result[3] = result[1] * (data.xref[2] - 1//ncomponents)
        end
        return nothing
    end   
    edata_function = DataFunction(normalflux_eval, [ncomponents, ncomponents]; dependencies = dependencies(data; enforce = "IL"), bonus_quadorder = data.bonus_quadorder+1)
    couple!(data, edata_function)
    set_time!(data, time)
    integrate!(Target, FE.xgrid, ON_FACES, edata_function; items = items, time = time, index_offsets = [0, nfaces, 2*nfaces])
end

function ExtendableGrids.interpolate!(Target::AbstractArray{<:Real,1}, FE::FESpace{Tv,Ti,FEType,APT}, ::Type{ON_CELLS}, data; items = [], time = 0) where {Tv,Ti,FEType <: HDIVBDM1,APT}
    # delegate cell faces to face interpolation
    subitems = slice(FE.xgrid[CellFaces], items)
    interpolate!(Target, FE, ON_FACES, data; items = subitems, time = time)
end

## only normalfluxes on faces
function get_basis(::Union{Type{<:ON_FACES}, Type{<:ON_BFACES}}, ::Type{<:HDIVBDM1}, ::Type{<:AbstractElementGeometry1D})
    function closure(refbasis,xref)
        refbasis[1,1] = 1
        refbasis[2,1] = 12*(xref[1] - 1//2) # linear normal-flux of BDM1 function
    end
end

function get_basis(::Type{ON_CELLS}, ::Type{HDIVBDM1{2}}, ::Type{<:Triangle2D})
    function closure(refbasis, xref)
        # RT0 basis
        refbasis[1,1] = xref[1];    refbasis[1,2] = xref[2]-1
        refbasis[3,1] = xref[1];    refbasis[3,2] = xref[2]
        refbasis[5,1] = xref[1]-1;  refbasis[5,2] = xref[2]
        # additional BDM1 functions on faces
        refbasis[2,1] = 6*xref[1];                  refbasis[2,2] = 6-12*xref[1]-6*xref[2]      # = 6*refbasis[1,:] + 12*[0,phi_1]       # phi2-weighted linear moment
        refbasis[4,1] = -6*xref[1];                 refbasis[4,2] = 6*xref[2]                   # = 6*refbasis[3,:] + 12*[-phi_2,0]      # phi3-weighted linear moment
        refbasis[6,1] = 6*(xref[1]-1)+12*xref[2];   refbasis[6,2] = -6*xref[2]                  # = 6*refbasis[5,:] + 12*[phi_3,-phi_3]  # phi1-weighted linear moment
    end
end

function get_basis(::Type{ON_CELLS}, ::Type{HDIVBDM1{2}}, ::Type{<:Quadrilateral2D})
    function closure(refbasis, xref)
        # RT0 basis
        refbasis[1,1] = 0;           refbasis[1,2] = xref[2]-1
        refbasis[3,1] = xref[1];     refbasis[3,2] = 0
        refbasis[5,1] = 0;           refbasis[5,2] = xref[2]
        refbasis[7,1] = xref[1]-1;   refbasis[7,2] = 0
        # additional BDM1 functions on faces
        refbasis[2,1] = -2*(3*xref[1]*xref[1]-3*xref[1]);               refbasis[2,2] = -2*(-6*xref[1]*xref[2]+6*xref[1]+3*xref[2]-3)
        refbasis[4,1] = -2*(-6*xref[1]*xref[2]+3*xref[1]);              refbasis[4,2] = -2*(3*xref[2]*xref[2]-3*xref[2])
        refbasis[6,1] = -2*(-3*xref[1]*xref[1]+3*xref[1]);              refbasis[6,2] = -2*(6*xref[1]*xref[2]-3*xref[2])
        refbasis[8,1] = -2*(6*xref[1]*xref[2]-3*xref[1]-6*xref[2]+3);   refbasis[8,2] = -2*(-3*xref[2]*xref[2]+3*xref[2])
    end
end

function get_basis(::Union{Type{<:ON_FACES}, Type{<:ON_BFACES}}, ::Type{<:HDIVBDM1}, ::Type{<:AbstractElementGeometry2D})
    function closure(refbasis,xref)
        refbasis[1,1] = 1
        refbasis[2,1] = 12*(2*xref[1]+xref[2]-1) # 1st linear normal-flux BDM1 function (normal flux weighted with (phi_1 - 1/3))
        refbasis[3,1] = 12*(2*xref[2]+xref[1]-1) # 2nd linear normal-flux BDM1 function (normal flux weighted with (phi_2 - 1/3))
    end
end

function get_basis(::Type{ON_CELLS}, ::Type{HDIVBDM1{3}}, ::Type{<:Tetrahedron3D})
    function closure(refbasis, xref)
        # RT0 basis
        refbasis[1,1] = 2*xref[1];      refbasis[1,2] = 2*xref[2];      refbasis[1,3] = 2*(xref[3]-1)
        refbasis[5,1] = 2*xref[1];      refbasis[5,2] = 2*(xref[2]-1);  refbasis[5,3] = 2*xref[3]
        refbasis[9,1] = 2*xref[1];      refbasis[9,2] = 2*xref[2];      refbasis[9,3] = 2*xref[3]
        refbasis[13,1] = 2*(xref[1]-1);  refbasis[13,2] = 2*xref[2];      refbasis[13,3] = 2*xref[3]
        # additional BDM1 functions on faces
        # note: we define three additional functions per face
        #       and later select only two linear independent ones that match the local enumeration/orientation
        #       of the global/local face nodes + a possible sign change managed by coefficient_handler
        refbasis[end] = 1 - xref[1] - xref[2] - xref[3] # store last barycentric coordinate
        # FACE1 [1,3,2], normal = [0,0,-1], |E| = 1/2, xref[3] = 0
        # phi = [-gamma*phi2,-beta*phi3,alpha*phi1+beta*phi3+gamma*phi2]
        # [J1,J2,J3] = linear moments of normal flux weighted with (phi_1-1/3), (phi_3-1/3), (phi_2-1/3)
        refbasis[2,1] = 24*xref[1];         refbasis[2,2] = 0;                      refbasis[2,3] = 24*(refbasis[end]-xref[1])           # [1,0,-1]
        refbasis[3,1] = 0;                  refbasis[3,2] = -24*xref[2];            refbasis[3,3] = -24*(refbasis[end]-xref[2])          # [0,-1,1]
        refbasis[4,1] = -24*xref[1];        refbasis[4,2] = 24*xref[2];             refbasis[4,3] = -24(xref[2]-xref[1])        # [-1,1,0]
        
        # FACE2 [1 2 4], normal = [0,-1,0], |E| = 1/2, xref[2] = 0
        # phi = [-beta*phi2,alpha*phi1+beta*phi2+gamma*phi4,-gamma*phi4]
        # [J1,J2,J3] = linear moments of normal flux weighted with (phi_1-1/3), (phi_2-1/3), (phi_4-1/3)
        refbasis[6,1] = 0;                  refbasis[6,2] = 24*(refbasis[end]-xref[3]);      refbasis[6,3] = 24*xref[3]                  # [1,0,-1]
        refbasis[7,1] = -24*xref[1];        refbasis[7,2] = -24*(refbasis[end]-xref[1]);     refbasis[7,3] = 0                           # [0,-1,1]
        refbasis[8,1] = 24*xref[1];         refbasis[8,2] = -24(xref[1]-xref[3]);   refbasis[8,3] = -24*xref[3]                 # [-1,1,0]

        # FACE3 [2 3 4], normal = [1,1,1]/sqrt(3), |E| = sqrt(3)/2, xref[1]+xref[2]+xref[3] = 1
        # phi = [alpha*phi2,beta*phi3,gamma*phi4]
        # [J1,J2,J3] = linear moments of normal flux weighted with (phi_2-1/3), (phi_3-1/3), (phi_4-1/3)
        refbasis[10,1] = -24*xref[1];       refbasis[10,2] = 0;                     refbasis[10,3] = 24*xref[3]                 # [1,0,-1]
        refbasis[11,1] = 24*xref[1];        refbasis[11,2] = -24*xref[2];           refbasis[11,3] = 0                          # [0,-1,1]
        refbasis[12,1] = 0;                 refbasis[12,2] = 24*xref[2];            refbasis[12,3] = -24*xref[3]                # [-1,1,0]
        
        # FACE4 [1 4 3], normal = [-1,0,0], |E| = 1/2, xref[1] = 0
        # phi = [alpha*phi1+beta*phi4+gamma*phi3,-gamma*phi3,-beta*phi4]
        # [J1,J2,J3] = linear moments of normal flux weighted with (phi_1-1/3), (phi_4-1/3), (phi_3-1/3)
        refbasis[14,1] = 24*(refbasis[end]-xref[2]);         refbasis[14,2] = 24*xref[2];    refbasis[14,3] = 0                          # [1,0,-1]
        refbasis[15,1] = -24*(refbasis[end]-xref[3]);        refbasis[15,2] = 0;             refbasis[15,3] = -24*xref[3]                # [0,-1,1]
        refbasis[16,1] = -24*(xref[3]-xref[2]);     refbasis[16,2] = -24*xref[2];   refbasis[16,3] = 24*xref[3]                 # [-1,1,0]
    end

    return closure
end


function get_coefficients(::Type{ON_CELLS}, FE::FESpace{Tv,Ti,<:HDIVBDM1,APT}, EG::Type{<:AbstractElementGeometry2D}) where {Tv,Ti,APT}
    xCellFaceSigns::Union{VariableTargetAdjacency{Int32},Array{Int32,2}} = FE.xgrid[CellFaceSigns]
    nfaces::Int = num_faces(EG)
    dim::Int = dim_element(EG)
    function closure(coefficients::Array{<:Real,2}, cell::Int)
        fill!(coefficients,1.0)
        # multiplication with normal vector signs (only RT0)
        for j = 1 : nfaces,  k = 1 : dim
            coefficients[k,2*j-1] = xCellFaceSigns[j,cell];
        end
        return nothing
    end
end  


function get_coefficients(::Type{ON_CELLS}, FE::FESpace{Tv,Ti,<: HDIVBDM1,APT}, EG::Type{<:AbstractElementGeometry3D}) where {Tv,Ti,APT}
    xCellFaceSigns::Union{VariableTargetAdjacency{Int32},Array{Int32,2}}  = FE.xgrid[CellFaceSigns]
    xCellFaceOrientations::Union{VariableTargetAdjacency{Int32},Array{Int32,2}} = FE.xgrid[CellFaceOrientations]
    nfaces::Int = num_faces(EG)
    dim::Int = dim_element(EG)
    function closure(coefficients::Array{<:Real,2}, cell::Int)
        fill!(coefficients,1.0)
        for j = 1 : nfaces,  k = 1 : dim
            coefficients[k,3*j-2] = xCellFaceSigns[j,cell]; # RT0
            coefficients[k,3*j-1] = -1;
            coefficients[k,3*j] = 1;
        end
        return nothing
    end
end  

# subset selector ensures that for every cell face
# the RT0 and those two BDM1 face functions are chosen
# such that they reflect the two moments with respect to the second and third node
# of the global face enumeration
function get_basissubset(::Type{ON_CELLS}, FE::FESpace{Tv,Ti,<:HDIVBDM1,APT}, EG::Type{<:AbstractElementGeometry3D}) where {Tv,Ti,APT}
    xCellFaceOrientations = FE.xgrid[CellFaceOrientations]
    nfaces::Int = num_faces(EG)
    orientation = xCellFaceOrientations[1,1]
    shift4orientation1::Array{Int,1} = [1,0,1,2]
    shift4orientation2::Array{Int,1} = [2,2,0,1]
    function closure(subset_ids, cell)
        for j = 1 : nfaces
            subset_ids[3*j-2] = 4*j-3; # always take the RT0 function
            orientation = xCellFaceOrientations[j,cell]
            subset_ids[3*j-1] = 4*j-shift4orientation1[orientation]
            subset_ids[3*j  ] = 4*j-shift4orientation2[orientation]
        end
        return nothing
    end
end  
 