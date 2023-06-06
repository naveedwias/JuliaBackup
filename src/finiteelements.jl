#######################################################################################################
#######################################################################################################
### FFFFF II NN    N II TTTTTT EEEEEE     EEEEEE LL     EEEEEE M     M EEEEEE NN    N TTTTTT SSSSSS ###
### FF    II N N   N II   TT   EE         EE     LL     EE     MM   MM EE     N N   N   TT   SS     ###
### FFFF  II N  N  N II   TT   EEEEE      EEEEE  LL     EEEEE  M M M M EEEEE  N  N  N   TT    SSSS  ###
### FF    II N   N N II   TT   EE         EE     LL     EE     M  M  M EE     N   N N   TT       SS ###
### FF    II N    NN II   TT   EEEEEE     EEEEEE LLLLLL EEEEEE M     M EEEEEE N    NN   TT   SSSSSS ###
#######################################################################################################
#######################################################################################################

abstract type AbstractFiniteElement end
  

#############################
# Finite Element Supertypes #
#############################
#
# they are used to steer the kind of local2global transformation
# below subtypes are defined that define basis functions on reference geometries 
# and some other information like polyonomial degrees etc.

abstract type AbstractHdivFiniteElement <: AbstractFiniteElement end
abstract type AbstractH1FiniteElement <: AbstractFiniteElement end
abstract type AbstractH1FiniteElementWithCoefficients <: AbstractH1FiniteElement end
abstract type AbstractHcurlFiniteElement <: AbstractFiniteElement end


"""
````
struct FESpace{Tv, Ti, FEType<:AbstractFiniteElement,AT<:AssemblyType}
    name::String                          # full name of finite element space (used in messages)
    broken::Bool                          # if true, broken dofmaps are generated
    ndofs::Int                            # total number of dofs
    coffset::Int                          # offset for component dofs
    xgrid::ExtendableGrid[Tv,Ti}          # link to xgrid 
    dofmaps::Dict{Type{<:AbstractGridComponent},Any} # backpack with dofmaps
end
````

A struct that has a finite element type as parameter and carries dofmaps (CellDofs, FaceDofs, BFaceDofs) plus additional grid information and access to arrays holding coefficients if needed.
"""
struct FESpace{Tv,Ti,FEType<:AbstractFiniteElement,AT<:AssemblyType}
    name::String                          # full name of finite element space (used in messages)
    broken::Bool                          # if true, broken dofmaps are generated
    ndofs::Int64                          # total number of dofs
    coffset::Int                          # offset for component dofs
    xgrid::ExtendableGrid{Tv,Ti}          # link to xgrid 
    dofmaps::Dict{Type{<:AbstractGridComponent},Any} # backpack with dofmaps
end

include("dofmaps.jl")

"""
$(TYPEDSIGNATURES)
Set new dofmap
"""
Base.setindex!(FES::FESpace,v,DM::Type{<:DofMap}) = FES.dofmaps[DM] = v


"""
````
function FESpace{FEType<:AbstractFiniteElement,AT<:AssemblyType}(
    xgrid::ExtendableGrid{Tv,Ti};
    name = "",
    broken::Bool = false)
````

Constructor for FESpace of the given FEType, AT = ON_CELLS/ON_FACES/ON_EDGES generates a finite elements space on the cells/faces/edges of the provided xgrid (if omitted ON_CELLS is used as default).
The broken switch allows to generate a broken finite element space (that is piecewise H1/Hdiv/HCurl). If no name is provided it is generated automatically from FEType.
If no AT is provided, the space is generated ON_CELLS.
"""
function FESpace{FEType,AT}(
    xgrid::ExtendableGrid{Tv,Ti};
    name = "",
    broken::Bool = false) where {Tv, Ti, FEType <:AbstractFiniteElement, AT<:AssemblyType}

    # piecewise constants are always broken
    if FEType <: L2P0 || FEType <: L2P1
        broken = true
    end

    if AT == ON_FACES
        xgrid = get_facegrid(xgrid)
        xgrid[BFaceNodes] = zeros(Ti,2,0)
        xgrid[BFaceRegions] = zeros(Ti,0)
        xgrid[BFaceGeometries] = VectorOfConstants{ElementGeometries,Int}(Edge1D,0)
        xgrid[BFaceVolumes] = zeros(Tv,0)
    elseif AT == ON_BFACES
        xgrid = subgrid(xgrid, unique(xgrid[BFaceRegions]); boundary = true, project = false)
        xgrid[BFaceNodes] = zeros(Ti,2,0)
        xgrid[BFaceRegions] = zeros(Ti,0)
        xgrid[BFaceGeometries] = VectorOfConstants{ElementGeometries,Int}(Edge1D,0)
        xgrid[BFaceVolumes] = zeros(Tv,0)
    elseif AT == ON_EDGES
        xgrid = get_edgegrid(xgrid)
        xgrid[BFaceNodes] = zeros(Ti,2,0)
        xgrid[BFaceRegions] = zeros(Ti,0)
        xgrid[BFaceGeometries] = VectorOfConstants{ElementGeometries,Int}(Edge1D,0)
        xgrid[BFaceVolumes] = zeros(Tv,0)
    end
    
    # first generate some empty FESpace
    if name == ""
        name = broken ? "$FEType (broken)" : "$FEType"
    end
    ndofs, coffset = count_ndofs(xgrid, FEType, broken)
    FES = FESpace{Tv, Ti, FEType,AT}(name,broken,ndofs,coffset,xgrid,Dict{Type{<:AbstractGridComponent},Any}())

    @logmsg DeepInfo "Generated FESpace $name ($AT, ndofs=$ndofs)"

    return FES
end

function FESpace{FEType}(
    xgrid::ExtendableGrid{Tv,Ti};
    name = "",
    broken::Bool = false) where {Tv, Ti, FEType <:AbstractFiniteElement}
    return FESpace{FEType,ON_CELLS}(xgrid; name = name, broken = broken)
end

"""
$(TYPEDSIGNATURES)

Custom `eltype` function for `FESpace` returns the finite element type parameter of the finite element space.
"""
Base.eltype(::FESpace{Tv, Ti, FEType, APT}) where {Tv, Ti, FEType<:AbstractFiniteElement, APT} = FEType


"""
$(TYPEDSIGNATURES)

returns the assembly type parameter of the finite element space, i.e. on which entities of the grid the finite element is defined.
"""
assemblytype(::FESpace{Tv, Ti, FEType, APT}) where {Tv, Ti, FEType<:AbstractFiniteElement, APT} = APT


"""
$(TYPEDSIGNATURES)

Custom `show` function for `FESpace` that prints some information and all available dofmaps.
"""
function Base.show(io::IO, FES::FESpace{Tv,Ti,FEType,APT}) where {Tv,Ti,FEType<:AbstractFiniteElement,APT}
	  println("\nFESpace information")
    println("===================")
    println("     name = $(FES.name)")
    println("   FEType = $FEType")
    println("  FEClass = $(supertype(FEType))")
    println("    ndofs = $(FES.ndofs)\n")
    println("")
    println("DofMaps");
    println("==========");
    for tuple in FES.dofmaps
        println("> $(tuple[1])")
    end
end

## used if no coefficient handler or subset handler is needed (to have a single Function type for all)
const NothingFunction = (x,y) -> nothing

# default coefficient functions that can be overwritten by finite element that has non-default coefficients
# ( see e.g. h1v_br.jl )
function get_coefficients(::Type{<:AssemblyType}, FE::FESpace{Tv,Ti,FEType,APT}, ::Type{<:AbstractElementGeometry}) where {Tv,Ti,FEType <: AbstractFiniteElement, APT}
    return NothingFunction
end    

# it is assumed that subset_ids is already 1 vector of form subset_ids = 1:ndofs
# meaning that all basis functions on the reference cells are used
# see 3D implementation of BDM1 for an example how this is can be used the choose
# different basis functions depending on the face orientations (which in 3D is not just a sign)
function get_basissubset(::Type{<:AssemblyType}, FE::FESpace{Tv,Ti,FEType,APT}, ::Type{<:AbstractElementGeometry}) where {Tv,Ti,FEType <: AbstractFiniteElement, APT}
    return NothingFunction
end  
get_ndofs(AT::Type{<:AssemblyType}, FEType::Type{<:AbstractFiniteElement}, EG::Type{<:AbstractElementGeometry}) = 0 # element is undefined for this AT or EG
get_basis(AT::Type{<:AssemblyType}, FEType::Type{<:AbstractFiniteElement}, EG::Type{<:AbstractElementGeometry}) = (refbasis,xref) -> nothing
get_ndofs_all(AT::Type{<:AssemblyType}, FEType::Type{<:AbstractFiniteElement}, EG::Type{<:AbstractElementGeometry}) = get_ndofs(AT, FEType, EG)
isdefined(FEType::Type{<:AbstractFiniteElement}, EG::Type{<:AbstractElementGeometry}) = false
isdefined(FEType::Type{<:AbstractFiniteElement}, EG::Type{<:AbstractElementGeometry}, ::Bool) = isdefined(FEType, EG)


"""
$(TYPEDSIGNATURES)
To be called by getindex. This triggers lazy creation of 
non-existing dofmaps
"""
Base.get!(FES::FESpace,DM::Type{<:DofMap}) = get!( ()-> init_dofmap!(FES,DM), FES.dofmaps ,DM)

"""
````
Base.getindex(FES::FESpace,DM::Type{<:DofMap})
````
Generic method for obtaining dofmap.
This method is mutating in the sense that non-existing dofmaps
are created on demand.
Due to the fact that components are stored as Any the return
value triggers type instability.
"""
Base.getindex(FES::FESpace,DM::Type{<:DofMap})=get!(FES,DM)

function count_ndofs(xgrid, FEType, broken)
    EG = xgrid[UniqueCellGeometries]
    xItemGeometries = xgrid[CellGeometries]
    ncells4EG = [(i, count(==(i), xItemGeometries)) for i in EG]
    ncomponents::Int = get_ncomponents(FEType)
    totaldofs::Int = 0
    offset4component::Int = 0

    ## todo : below it is assumed that number of dofs on nodes/edges/faces is the same for all EG
    ##        (which usually makes sense for unbroken elements, but who knows...)
    for j = 1 : length(EG)
        pattern = get_dofmap_pattern(FEType, CellDofs, EG[j])
        parsed_dofmap = ParsedDofMap(pattern, ncomponents, EG[j])
        if broken == true
            # if broken count all dofs here
            totaldofs += ncells4EG[j][2] * get_ndofs(parsed_dofmap)
        else
            # if not broken only count interior dofs on cell here
            totaldofs += ncells4EG[j][2] * get_ndofs(parsed_dofmap, DofTypeInterior)
            offset4component += ncells4EG[j][2] * get_ndofs4c(parsed_dofmap, DofTypeInterior)
        end

        if j == length(EG) && !broken
            # add continuous dofs here
            totaldofs += size(xgrid[Coordinates],2) * get_ndofs(parsed_dofmap, DofTypeNode)
            if get_ndofs(parsed_dofmap, DofTypeFace) > 0
                totaldofs += num_sources(xgrid[FaceNodes]) * get_ndofs(parsed_dofmap, DofTypeFace)
            end
            if get_ndofs(parsed_dofmap, DofTypeEdge) > 0
                totaldofs += num_sources(xgrid[EdgeNodes]) * get_ndofs(parsed_dofmap, DofTypeEdge)
            end

            # compute also offset4component

            offset4component += num_nodes(xgrid) * get_ndofs4c(parsed_dofmap, DofTypeNode)
            if get_ndofs4c(parsed_dofmap, DofTypeFace) > 0
                nfaces = num_sources(xgrid[FaceNodes])
                offset4component += nfaces * get_ndofs4c(parsed_dofmap, DofTypeFace)
            end
            if get_ndofs4c(parsed_dofmap, DofTypeEdge) > 0
                nedges = num_sources(xgrid[EdgeNodes])
                offset4component += nedges * get_ndofs4c(parsed_dofmap, DofTypeEdge)
            end
            offset4component += num_cells(xgrid) * get_ndofs4c(parsed_dofmap, DofTypePCell)
            #nitems::Int = length(xItemGeometries)
            #offset4component += nitems * get_ndofs4c(parsed_dofmap, DofTypeInterior)
        end
    end

    return totaldofs, offset4component
end


include("fevector.jl");
include("fematrix.jl");
include("interpolations.jl")


# dummy functions
get_edim(FEType::Type{<:AbstractFiniteElement}) = 0 # not defined
get_polynomialorder(::Type{<:AbstractFiniteElement}, ::Type{<:Vertex0D}) = 0
interior_dofs_offset(AT::Type{<:AssemblyType}, FE::Type{<:AbstractFiniteElement}, EG::Type{<:AbstractElementGeometry}) = -1 # should be specified by element if needed


###########################
# Finite Element Subtypes #
###########################
#
# subtypes of the finite element supertypes above
# each defined in its own file
  
# Hdiv-conforming elements (only vector-valued)
# lowest order
include("fedefs/hdiv_rt0.jl");
include("fedefs/hdiv_bdm1.jl");
include("fedefs/hdiv_rt1.jl");
include("fedefs/hdiv_bdm2.jl");
include("fedefs/hdiv_rtk_enrich.jl");

# H1 conforming elements (also Crouzeix-Raviart)
# no order (just for certain purposes)
include("fedefs/h1_bubble.jl");
# lowest order
include("fedefs/l2_p0.jl");
include("fedefs/l2_p1.jl");
include("fedefs/h1_p1.jl");
include("fedefs/h1_q1.jl");
include("fedefs/h1_mini.jl");
include("fedefs/h1nc_cr.jl");
include("fedefs/h1v_br.jl"); # Bernardi--Raugel (only vector-valued, with coefficients)
include("fedefs/h1v_p1teb.jl"); # P1 + tangential edge bubbles (only vector-valued, with coefficients)
# second order
include("fedefs/h1_p2.jl");
include("fedefs/h1_q2.jl");
include("fedefs/h1_p2b.jl");
# third order
include("fedefs/h1_p3.jl");
# arbitrary order
include("fedefs/h1_pk.jl");

# Hcurl-conforming elements
include("fedefs/hcurl_n0.jl");



function get_coefficients(::Type{ON_BFACES}, FE::FESpace{Tv, Ti, FEType, APT}, EG::Type{<:AbstractElementGeometry}) where {Tv,Ti,FEType <: AbstractFiniteElement, APT}
    get_coeffs_on_face = get_coefficients(ON_FACES, FE, EG)
    xBFaceFaces = FE.xgrid[BFaceFaces]
    function closure(coefficients, bface)
        get_coeffs_on_face(coefficients, xBFaceFaces[bface])
        return nothing
    end
end    


function get_reconstruction_matrix(T::Type{<:Real}, FE::FESpace, FER::FESpace)
    xgrid = FE.xgrid
    xCellGeometries = xgrid[CellGeometries]
    EG = xgrid[UniqueCellGeometries]

    FEType = eltype(FE)
    FETypeReconst = eltype(FER)

    ncells = num_sources(xgrid[CellNodes])
    rhandlers = [get_reconstruction_coefficient(ON_CELLS, FE, FER, EG[1])]
    chandlers = [get_coefficients(ON_CELLS, FER, EG[1])]
    shandlers = [get_basissubset(ON_CELLS, FER, EG[1])]
    for j = 2 : length(EG)
        append!(rhandlers, [get_reconstruction_coefficients(ON_CELLS, FE, FER, EG[j])])
        append!(chandlers, [get_coefficients(ON_CELLS, FER, EG[j])])
        append!(shandlers, [get_basissubset(ON_CELLS, FER, EG[j])])
    end

    ndofs_FE = zeros(Int,length(EG))
    ndofs_FER = zeros(Int,length(EG))
    for j = 1 : length(EG)
        ndofs_FE[j] = get_ndofs(ON_CELLS, FEType, EG[j])
        ndofs_FER[j] = get_ndofs(ON_CELLS, FETypeReconst, EG[j])
    end
    
    xCellDofs = FE[CellDofs]
    xCellDofsR = FER[CellDofs]

    ## generate matrix
    A = ExtendableSparseMatrix{T,Int64}(FER.ndofs,FE.ndofs)

    iEG = 1
    cellEG = EG[1]
    ncomponents = get_ncomponents(FEType)
    coefficients = zeros(T, ncomponents, maximum(ndofs_FER))
    basissubset = zeros(Int, maximum(ndofs_FER))
    rcoefficients = zeros(T, maximum(ndofs_FE),maximum(ndofs_FER))
    dof::Int = 0
    dofR::Int = 0
    for cell = 1 : ncells
        if length(EG) > 1
            cellEG = xCellGeometries[cell]
            for j=1:length(EG)
                if cellEG == EG[j]
                    iEG = j
                    break;
                end
            end
        end
        # get Hdiv coefficients and subset
        chandlers[iEG](coefficients, cell)
        shandlers[iEG](basissubset, cell)

        # get reconstruction coefficients
        rhandlers[iEG](rcoefficients, cell)

        for dof_i = 1 : ndofs_FE[iEG]
            dof = xCellDofs[dof_i,cell]
            for dof_j = 1 : ndofs_FER[iEG]
                if rcoefficients[dof_i,dof_j] != 0
                    dofR = xCellDofsR[dof_j,cell]
                    A[dofR,dof] = rcoefficients[dof_i,dof_j]
                end
            end
        end
    end
    flush!(A)
    return A
end

function get_local_coffsets(FEType, AT, EG)
    ## get dofmap pattern
    pattern = get_dofmap_pattern(FEType, Dofmap4AssemblyType(AT), EG)
    ncomponents = get_ncomponents(FEType)
    parsed_dofmap = ParsedDofMap(pattern, ncomponents, EG)
    local_coffset = 0
    local_coffset += num_nodes(EG) * get_ndofs4c(parsed_dofmap, DofTypeNode)
    if get_ndofs4c(parsed_dofmap, DofTypeFace) > 0
        local_coffset += num_faces(EG) * get_ndofs4c(parsed_dofmap, DofTypeFace)
    end
    if get_ndofs4c(parsed_dofmap, DofTypeEdge) > 0
        local_coffset += num_edges(EG) * get_ndofs4c(parsed_dofmap, DofTypeEdge)
    end
    local_coffset += get_ndofs4c(parsed_dofmap, DofTypeInterior)
    if local_coffset == 0
        return Int[]
    else
        return 0:local_coffset:ncomponents*local_coffset
    end
end
