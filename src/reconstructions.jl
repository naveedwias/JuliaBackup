
abstract type ReconstructionCoefficients{FE1,FE2,AT} <: AbstractGridFloatArray2D end
abstract type ReconstructionDofs{FE1,FE2,AT} <: AbstractGridIntegerArray2D end

struct ReconstructionHandler{Tv,Ti,FE1,FE2,AT,EG}
    FES::FESpace{Tv,Ti,FE1,ON_CELLS}
    FER::FESpace{Tv,Ti,FE2,ON_CELLS}
    xFaceVolumes::Array{Tv,1}
    xFaceNormals::Array{Tv,2}
    xCellFaceOrientations::Adjacency{Ti}
    xCellFaces::Adjacency{Ti}
    interior_offset::Int
    interior_ndofs::Int
    interior_coefficients::Matrix{Tv} # coefficients for interior basis functions are precomputed
end

function ReconstructionHandler(FES::FESpace{Tv,Ti,FE1,APT},FES_Reconst::FESpace{Tv,Ti,FE2,APT},AT,EG) where {Tv,Ti,FE1,FE2,APT}
    xgrid = FES.xgrid
    interior_offset = interior_dofs_offset(AT,FE2,EG)
    interior_ndofs = get_ndofs(AT,FE2,EG) - interior_offset
    if interior_offset != -1 && interior_ndofs > 0
        coeffs = xgrid[ReconstructionCoefficients{FE1,FE2,AT}]
    else
        interior_ndofs = 0
        coeffs = zeros(Tv,0,0)
    end
    xFaceVolumes = xgrid[FaceVolumes]
    xFaceNormals = xgrid[FaceNormals]
    xCellFaceOrientations = dim_element(EG) == 2 ? xgrid[CellFaceSigns] : xgrid[CellFaceOrientations]
    xCellFaces = xgrid[CellFaces]
    return ReconstructionHandler{Tv,Ti,FE1,FE2,AT,EG}(FES,FES_Reconst,xFaceVolumes,xFaceNormals,xCellFaceOrientations,xCellFaces,interior_offset,interior_ndofs,coeffs)
end

function get_rcoefficients!(coefficients, RH::ReconstructionHandler{Tv,Ti,FE1,FE2,AT,EG}, item) where {Tv,Ti,FE1,FE2,AT,EG}
    boundary_coefficients!(coefficients, RH, item)
    for dof = 1 : size(coefficients,1), k = 1 : RH.interior_ndofs
        coefficients[dof,RH.interior_offset + k] = RH.interior_coefficients[(dof-1)*RH.interior_ndofs+k, item]
    end
    return nothing
end

# interior coefficients for P2B > RT1/BDM2 reconstruction
function ExtendableGrids.instantiate(xgrid::ExtendableGrid{Tv,Ti}, ::Type{ReconstructionCoefficients{FE1,FE2,AT}}) where {Tv, Ti, FE1<:H1P2B{2,2}, FE2<:HDIVRT1{2}, AT <: ON_CELLS}
    @info "Computing interior reconstruction coefficients for $FE1 > $FE2 ($AT)"
    xCellFaces = xgrid[CellFaces]
    xCoordinates = xgrid[Coordinates]
    xCellNodes = xgrid[CellNodes]
    xFaceVolumes::Array{Tv,1} = xgrid[FaceVolumes]
    xFaceNormals::Array{Tv,2} = xgrid[FaceNormals]
    xCellVolumes::Array{Tv,1} = xgrid[CellVolumes]
    xCellFaceSigns = xgrid[CellFaceSigns]
    EG = xgrid[UniqueCellGeometries]

    @assert EG == [Triangle2D]

    face_rule::Array{Int,2} = local_cellfacenodes(EG[1])
    RT1_coeffs = _P1_INTO_BDM1_COEFFS
    nnf::Int = size(face_rule,2)
    ndofs4component::Int = 2*nnf + 1
    ndofs1::Int = get_ndofs(AT,FE1,EG[1])
    ncells::Int = num_sources(xCellFaces)
    coefficients::Array{Tv,2} = zeros(Tv,ndofs1,6)
    interior_coefficients::Array{Tv,2} = zeros(Tv,2*ndofs1,ncells)

    C = zeros(Tv,2,3)  # vertices
    E = zeros(Tv,2,3)  # edge midpoints
    M = zeros(Tv,2)    # midpoint of current cell
    A = zeros(Tv,2,8)  # integral means of RT1 functions (from analytic formulas)
    b = zeros(Tv,2)    # right-hand side for integral mean
    dof::Int = 0
    det::Tv = 0
    face::Int = 0
    node::Int = 0
    for cell = 1 : ncells

        for f = 1 : nnf
            face = xCellFaces[f,cell]
            for n = 1 : 2
                node = face_rule[n,f]
                for k = 1 : 2
                    # RT0 reconstruction coefficients for node P2 functions on reference element
                    coefficients[ndofs4component*(k-1)+node,2*(f-1)+1] = 1 // 6 * xFaceVolumes[face] * xFaceNormals[k, face]
    
                    # RT1 reconstruction coefficients for node P2 functions on reference element
                    coefficients[ndofs4component*(k-1)+node,2*(f-1)+2] = RT1_coeffs[n] * xFaceVolumes[face] * xFaceNormals[k, face] * xCellFaceSigns[f, cell]
                end
            end
            for k = 1 : 2
                # RT0 reconstruction coefficients for face P2 functions (=face bubbles) on reference element
                coefficients[ndofs4component*(k-1)+f+nnf,2*(f-1)+1] = 2 // 3 * xFaceVolumes[face] * xFaceNormals[k, face]
            end
        end

        # get coordinates of cells
        fill!(M,0)
        fill!(E,0)
        for n = 1 : 3, k = 1 : 2
            C[k,n] = xCoordinates[k,xCellNodes[n,cell]]
            M[k] += C[k,n] / 3
        end
        
        # get edge midpoints
        for f = 1 : nnf
            for n = 1 : 2, k = 1 : 2
                E[k,f] += C[k,face_rule[n,f]] / 2
            end
        end

        # compute integral means of RT1 functions
        for k = 1 : 2
            A[k,1] = (M[k] - C[k,3])/2 * xCellFaceSigns[1, cell]
            A[k,2] = C[k,2] - E[k,2]
            A[k,3] = (M[k] - C[k,1])/2 * xCellFaceSigns[2, cell]
            A[k,4] = C[k,3] - E[k,3]
            A[k,5] = (M[k] - C[k,2])/2 * xCellFaceSigns[3, cell]
            A[k,6] = C[k,1] - E[k,1]
        end
        # directly assign inverted A[1:2,7:8] for faster solve of local systems
        A[2,8] = (E[1,1] - C[1,3]) # A[1,7]
        A[2,7] = -(E[2,1] - C[2,3]) # A[2,7]
        A[1,8] = -(E[1,3] - C[1,2]) # A[1,8]
        A[1,7] = (E[2,3] - C[2,2]) # A[2,8]

        det = A[1,7]*A[2,8] - A[2,7]*A[1,8]
        A[1:2,7:8] ./= det

        # correct integral means with interior RT1 functions
        for k = 1 : 2
            for n = 1 : 3
                # nodal P2 functions have integral mean zero
                dof = (ndofs4component*(k-1) + n)
                fill!(b,0)
                for c = 1 : 2, j = 1 : 6
                    b[c] -= coefficients[dof,j] * A[c,j]
                end
                for k = 1 : 2
                    interior_coefficients[(dof-1)*2+k,cell] = A[k,7]*b[1] + A[k,8]*b[2]
                end

                # face P2 functions have integral mean 1//3
                dof = (ndofs4component*(k-1) + n + nnf)
                fill!(b,0)
                b[k] = xCellVolumes[cell] / 3
                for c = 1 : 2, j = 1 : 6
                    b[c] -= coefficients[dof,j] * A[c,j]
                end
                for k = 1 : 2
                    interior_coefficients[(dof-1)*2+k,cell] = A[k,7]*b[1] + A[k,8]*b[2]
                end
            end

            # cell bubbles have integral mean 1
            dof = ndofs4component*k
            fill!(b,0)
            b[k] = xCellVolumes[cell]
            for k = 1 : 2
                interior_coefficients[(dof-1)*2+k,cell] = A[k,7]*b[1] + A[k,8]*b[2]
            end
        end
    end
    interior_coefficients
end

function ExtendableGrids.instantiate(xgrid::ExtendableGrid{Tv, Ti}, ::Type{ReconstructionCoefficients{FE1,FE2,AT}}) where {Tv, Ti, FE1<:H1P2B{2,2}, FE2<:HDIVBDM2{2}, AT <: ON_CELLS}
    @info "Computing interior reconstruction coefficients for $FE1 > $FE2 ($AT)"
    xCellFaces = xgrid[CellFaces]
    xCellVolumes::Array{Tv,1} = xgrid[CellVolumes]
    xCellFaceSigns = xgrid[CellFaceSigns]
    xFaceVolumes::Array{Tv,1} = xgrid[FaceVolumes]
    xFaceNormals::Array{Tv,2} = xgrid[FaceNormals]
    EG = xgrid[UniqueCellGeometries]

    @assert EG == [Triangle2D]

    face_rule::Array{Int,2} = local_cellfacenodes(EG[1])
    coeffs1 = _P1_INTO_BDM1_COEFFS
    nnf = size(face_rule,2)
    ndofs4component = 2*nnf + 1

    ndofs1::Int = get_ndofs(AT,FE1,EG[1])
    ncells::Int = num_sources(xCellFaces)
    interior_offset::Int = 9
    interior_ndofs::Int = 3
    coefficients::Array{Tv,2} = zeros(Tv,ndofs1,interior_offset)
    interior_coefficients::Array{Tv,2} = zeros(Tv,interior_ndofs*ndofs1,ncells)

    qf = QuadratureRule{Tv,EG[1]}(4)
    weights::Array{Tv,1} = qf.w
    # evaluation of FE1 and FE2 basis
    FES1 = FESpace{FE1,ON_CELLS}(xgrid)
    FES2 = FESpace{FE2,ON_CELLS}(xgrid)
    FEB1 = FEEvaluator(FES1, Identity, qf; T = Tv)
    FEB2 = FEEvaluator(FES2, Identity, qf; T = Tv)
    # evaluation of gradient of P1 functions
    FE3 = H1P1{1}
    FES3 = FESpace{FE3,ON_CELLS}(xgrid)
    FEB3 = FEEvaluator(FES3, Gradient, qf; T = Tv)
    # evaluation of curl of bubble functions
    FE4 = H1BUBBLE{1}
    FES4 = FESpace{FE4,ON_CELLS}(xgrid)
    FEB4 = FEEvaluator(FES4, CurlScalar, qf; T = Tv)

    basisvals1::Array{Tv,3} = FEB1.cvals
    basisvals2::Array{Tv,3} = FEB2.cvals
    basisvals3::Array{Tv,3} = FEB3.cvals
    basisvals4::Array{Tv,3} = FEB4.cvals
    IMM_face = zeros(Tv,interior_ndofs,interior_offset)
    IMM = zeros(Tv,interior_ndofs,interior_ndofs)
    for k = 1 : interior_ndofs
        IMM[k,k] = 1
    end
    lb = zeros(Tv,interior_ndofs)
    lx = zeros(Tv,interior_ndofs)
    temp::Tv = 0
    face = 0
    node = 0
    offset::Int = 0
    IMMfact = lu(IMM)
    for cell = 1 : ncells

        # get reconstruction coefficients for boundary dofs
        for f = 1 : nnf
            face = xCellFaces[f,cell]
            for n = 1 : 2
                node = face_rule[n,f]
                for k = 1 : 2
                    # RT0 reconstruction coefficients for node P2 functions on reference element
                    coefficients[ndofs4component*(k-1)+node,3*(f-1)+1] = 1 // 6 * xFaceVolumes[face] * xFaceNormals[k, face]

                    # 1st BDM2 reconstruction coefficients for node P2 functions on reference element
                    coefficients[ndofs4component*(k-1)+node,3*(f-1)+2] = coeffs1[n] * xFaceVolumes[face] * xFaceNormals[k, face] * xCellFaceSigns[f, cell]

                    # 2nd BDM2 reconstruction coefficients for node P2 functions on reference element
                    coefficients[ndofs4component*(k-1)+node,3*(f-1)+3] = 1 // 90 * xFaceVolumes[face] * xFaceNormals[k, face]
                end
            end
            for k = 1 : 2
                # RT0 reconstruction coefficients for face P2 functions (=face bubbles) on reference element
                coefficients[ndofs4component*(k-1)+f+nnf,3*(f-1)+1] = 2 // 3 * xFaceVolumes[face] * xFaceNormals[k, face]

                # 2nd BDM2 reconstruction coefficients for face P2 functions on reference element
                coefficients[ndofs4component*(k-1)+f+nnf,3*(f-1)+3] = -1 // 45 * xFaceVolumes[face] * xFaceNormals[k, face]
            end
        end

        # update basis
        update_basis!(FEB1,cell)
        update_basis!(FEB2,cell)
        update_basis!(FEB3,cell)
        update_basis!(FEB4,cell)

        # compute local mass matrices
        fill!(IMM,0)
        fill!(IMM_face,0)
        for i in eachindex(weights)
            for dof = 1:interior_ndofs
                # interior FE2 basis functions times grad(P1) of first two P1 functions
                for dof2 = 1 : interior_ndofs - 1
                    temp = 0
                    for k = 1 : 2
                        temp += basisvals2[k,interior_offset + dof,i] * basisvals3[k,dof2,i]
                    end
                    IMM[dof2,dof] += temp * xCellVolumes[cell] * weights[i]
                end
                # interior FE2 basis functions times curl(bubble)
                temp = 0
                for k = 1 : 2
                    temp += basisvals2[k,interior_offset + dof,i] * basisvals4[k,1,i]
                end
                IMM[3,dof] += temp * xCellVolumes[cell] * weights[i]

                # mass matrix of face basis functions x grad(P1) and curl(bubble)
                if dof < 3
                    for dof2 = 1 : interior_offset
                        temp = 0
                        for k = 1 : 2
                            temp += basisvals3[k,dof,i] * basisvals2[k,dof2,i]
                        end
                        IMM_face[dof,dof2] += temp * xCellVolumes[cell] * weights[i]
                    end
                    # mass matrix of face basis functions x interior basis functions
                elseif dof == 3
                    for dof2 = 1 : interior_offset
                        temp = 0
                        for k = 1 : 2
                            temp += basisvals4[k,1,i] * basisvals2[k,dof2,i]
                        end
                        IMM_face[dof,dof2] += temp * xCellVolumes[cell] * weights[i] 
                    end
                end
            end
        end

        # solve local systems
        IMMfact = lu(IMM)
        for dof1 = 1 : ndofs1
            # right-hand side
            fill!(lb,0)
            for i in eachindex(weights)
                for idof = 1:interior_ndofs-1
                    temp = 0
                    for k = 1 : 2
                        temp += basisvals1[k,dof1,i] * basisvals3[k,idof,i]
                    end
                    lb[idof] += temp *  xCellVolumes[cell] * weights[i]
                end
                temp = 0
                for k = 1 : 2
                    temp += basisvals1[k,dof1,i] * basisvals4[k,1,i]
                end
                lb[3] += temp *  xCellVolumes[cell] * weights[i]
            end

            # subtract face interpolation from right-hand side
            for idof = 1 : interior_ndofs, dof2 = 1 : interior_offset
                lb[idof] -= coefficients[dof1,dof2] * IMM_face[idof,dof2]
            end
        
            # solve local system
            ldiv!(lx, IMMfact, lb)
            offset = interior_ndofs*(dof1-1)
            for idof = 1 : interior_ndofs
                interior_coefficients[offset+idof,cell] = lx[idof]
            end
        end
    end
    interior_coefficients
end




##### BOUNDARY COEFFICIENTS #####

function boundary_coefficients!(coefficients, RH::ReconstructionHandler{Tv, Ti, <:H1CR{ncomponents}, <:HDIVRT0{ncomponents}, <:ON_CELLS, EG}, cell) where {Tv, Ti, ncomponents, EG}
    xFaceVolumes = RH.xFaceVolumes
    xFaceNormals = RH.xFaceNormals
    xCellFaces = RH.xCellFaces
    face_rule = local_cellfacenodes(EG)
    nfaces = size(face_rule,2)
    face = 0
    for f = 1 : nfaces
        face = xCellFaces[f,cell]
        for k = 1 : ncomponents
            coefficients[nfaces*(k-1)+f,f] = xFaceVolumes[face] * xFaceNormals[k, face]
        end
    end
    return nothing
end

const _P1_INTO_BDM1_COEFFS = [-1//12, 1//12]

function boundary_coefficients!(coefficients, RH::ReconstructionHandler{Tv, Ti, FE1, FE2, AT, EG}, cell) where {Tv, Ti, FE1<:H1BR{2}, FE2<:HDIVBDM1{2}, AT <: ON_CELLS, EG <: Union{Triangle2D, Quadrilateral2D}}
    xFaceVolumes = RH.xFaceVolumes
    xFaceNormals = RH.xFaceNormals
    xCellFaceSigns = RH.xCellFaceOrientations
    xCellFaces = RH.xCellFaces
    face_rule = local_cellfacenodes(EG)
    nnodes = size(face_rule,1)
    nfaces = size(face_rule,2)
    node = 0
    face = 0
    BDM1_coeffs = _P1_INTO_BDM1_COEFFS
    for f = 1 : nfaces
        face = xCellFaces[f, cell]
        for n = 1 : nnodes
            node = face_rule[n,f]
            for k = 1 : 2
                # RT0 reconstruction coefficients for P1 functions on reference element
                coefficients[nfaces*(k-1)+node,2*(f-1)+1] = 1 // 2 * xFaceVolumes[face] * xFaceNormals[k, face]
                # BDM1 reconstruction coefficients for P1 functions on reference element
                coefficients[nfaces*(k-1)+node,2*(f-1)+2] = BDM1_coeffs[n] * xFaceVolumes[face] * xFaceNormals[k, face] * xCellFaceSigns[f, cell]
            end
        end
        # RT0 reconstruction coefficients for face bubbles on reference element
        coefficients[nfaces*2+f,2*(f-1)+1] = xFaceVolumes[face]
    end
    return nothing
end

function boundary_coefficients!(coefficients, RH::ReconstructionHandler{Tv, Ti, FE1, FE2, AT, EG}, cell) where {Tv, Ti, FE1<:H1BR{2}, FE2<:HDIVRT0{2}, AT <: ON_CELLS, EG <: Union{Triangle2D, Quadrilateral2D}}
    xFaceVolumes = RH.xFaceVolumes
    xFaceNormals = RH.xFaceNormals
    xCellFaces = RH.xCellFaces
    face_rule = local_cellfacenodes(EG)
    nnodes = size(face_rule,1)
    nfaces = size(face_rule,2)
    node = 0
    face = 0
    for f = 1 : nfaces
        face = xCellFaces[f,cell]
        # reconstruction coefficients for P1 functions on reference element
        for n = 1 : nnodes
            node = face_rule[n,f]
            for k = 1 : 2
                coefficients[nfaces*(k-1)+node,f] = 1 // 2 * xFaceVolumes[face] * xFaceNormals[k, face]
            end
        end
        # reconstruction coefficients for face bubbles on reference element
        coefficients[2*nfaces+f,f] = xFaceVolumes[face]
    end
    return nothing
end

function boundary_coefficients!(coefficients, RH::ReconstructionHandler{Tv, Ti, FE1, FE2, AT, EG}, cell) where {Tv, Ti, FE1 <:H1P2B{2,2}, FE2 <:HDIVRT1{2}, AT <: ON_CELLS, EG <: Triangle2D}
    xFaceVolumes = RH.xFaceVolumes
    xFaceNormals = RH.xFaceNormals
    xCellFaceSigns = RH.xCellFaceOrientations
    xCellFaces = RH.xCellFaces
    face_rule = local_cellfacenodes(EG)
    node = 0
    face = 0
    nnf = size(face_rule,2)
    ndofs4component = 2*nnf + 1
    RT1_coeffs = _P1_INTO_BDM1_COEFFS
    for f = 1 : nnf
        face = xCellFaces[f,cell]
        for n = 1 : 2
            node = face_rule[n,f]
            for k = 1 : 2
                # RT0 reconstruction coefficients for node P2 functions on reference element
                coefficients[ndofs4component*(k-1)+node,2*(f-1)+1] = 1 // 6 * xFaceVolumes[face] * xFaceNormals[k, face]

                # RT1 reconstruction coefficients for node P2 functions on reference element
                coefficients[ndofs4component*(k-1)+node,2*(f-1)+2] = RT1_coeffs[n] * xFaceVolumes[face] * xFaceNormals[k, face] * xCellFaceSigns[f, cell]
            end
        end
        for k = 1 : 2
            # RT0 reconstruction coefficients for face P2 functions (=face bubbles) on reference element
            coefficients[ndofs4component*(k-1)+f+nnf,2*(f-1)+1] = 2 // 3 * xFaceVolumes[face] * xFaceNormals[k, face]
        end
    end
    return nothing
end

function boundary_coefficients!(coefficients, RH::ReconstructionHandler{Tv, Ti, FE1, FE2, AT, EG}, cell) where {Tv, Ti, FE1 <:H1P2B{2,2}, FE2 <:HDIVBDM2{2}, AT <: ON_CELLS, EG <: Triangle2D}
    xFaceVolumes = RH.xFaceVolumes
    xFaceNormals = RH.xFaceNormals
    xCellFaceSigns = RH.xCellFaceOrientations
    xCellFaces = RH.xCellFaces
    face_rule = local_cellfacenodes(EG)
    node = 0
    face = 0
    nnf = size(face_rule,2)
    ndofs4component = 2*nnf + 1
    coeffs1 = _P1_INTO_BDM1_COEFFS
    for f = 1 : nnf
        face = xCellFaces[f,cell]
        for n = 1 : 2
            node = face_rule[n,f]
            for k = 1 : 2
                # RT0 reconstruction coefficients for node P2 functions on reference element
                coefficients[ndofs4component*(k-1)+node,3*(f-1)+1] = 1 // 6 * xFaceVolumes[face] * xFaceNormals[k, face]

                # 1st BDM2 reconstruction coefficients for node P2 functions on reference element
                coefficients[ndofs4component*(k-1)+node,3*(f-1)+2] = coeffs1[n] * xFaceVolumes[face] * xFaceNormals[k, face] * xCellFaceSigns[f, cell]

                # 2nd BDM2 reconstruction coefficients for node P2 functions on reference element
                coefficients[ndofs4component*(k-1)+node,3*(f-1)+3] = 1 // 90 * xFaceVolumes[face] * xFaceNormals[k, face]
            end
        end
        for k = 1 : 2
            # RT0 reconstruction coefficients for face P2 functions (=face bubbles) on reference element
            coefficients[ndofs4component*(k-1)+f+nnf,3*(f-1)+1] = 2 // 3 * xFaceVolumes[face] * xFaceNormals[k, face]

            # 2nd BDM2 reconstruction coefficients for face P2 functions on reference element
            coefficients[ndofs4component*(k-1)+f+nnf,3*(f-1)+3] = -1 // 45 * xFaceVolumes[face] * xFaceNormals[k, face]
        end
    end
    return nothing
end


function boundary_coefficients!(coefficients, RH::ReconstructionHandler{Tv, Ti, FE1, FE2, AT, EG}, cell) where {Tv, Ti, FE1 <:H1BR{3}, FE2 <:HDIVRT0{3}, AT <: ON_CELLS, EG <: Tetrahedron3D}
    xFaceVolumes = RH.xFaceVolumes
    xFaceNormals = RH.xFaceNormals
    xCellFaces = RH.xCellFaces
    face_rule = local_cellfacenodes(EG)
    node = 0
    face = 0
    # fill!(coefficients,0.0)
    for f = 1 : 4
        face = xCellFaces[f,cell]
        # reconstruction coefficients for P1 functions on reference element
        for n = 1 : 3
            node = face_rule[n,f]
            for k = 1 : 3
                coefficients[4*(k-1)+node,f] = 1 // 3 * xFaceVolumes[face] * xFaceNormals[k, face]
            end
        end
        # reconstruction coefficients for face bubbles on reference element
        coefficients[12+f,f] = xFaceVolumes[face]
    end
    return nothing
end

const _P1_INTO_BDM1_COEFFS_3D = [-1//36 -1//36 1//18; -1//36 1//18 -1//36; 1//18 -1//36 -1//36]

function boundary_coefficients!(coefficients, RH::ReconstructionHandler{Tv, Ti, FE1, FE2, AT, EG}, cell) where {Tv, Ti, FE1 <:H1BR{3}, FE2 <:HDIVBDM1{3}, AT <: ON_CELLS, EG <: Tetrahedron3D}
    xFaceVolumes = RH.xFaceVolumes
    xFaceNormals = RH.xFaceNormals
    xCellFaces = RH.xCellFaces
    xCellFaceOrientations = RH.xCellFaceOrientations
    face_rule = local_cellfacenodes(EG)
    node = 0
    face = 0
    face_rule = local_cellfacenodes(EG)
    BDM1_coeffs = _P1_INTO_BDM1_COEFFS_3D
    orientation = 0
    index1 = 0
    index2 = 0
    row4orientation1::Array{Int,1} = [2,2,3,1]
    row4orientation2::Array{Int,1} = [1,3,1,2]
    # fill!(coefficients,0.0)
    for f = 1 : 4
        face = xCellFaces[f,cell]
        index1 = 0
        for k = 1 : 3
            for n = 1 : 3
                node = face_rule[n,f]
                # RT0 reconstruction coefficients for P1 functions on reference element
                coefficients[index1+node,index2+1] = 1 // 3 * xFaceNormals[k, face] * xFaceVolumes[face] 
                orientation = xCellFaceOrientations[f,cell]
                # BDM1 reconstruction coefficients for P1 functions on reference element
                coefficients[index1+node,index2+2] = BDM1_coeffs[n, row4orientation1[orientation]] * xFaceNormals[k, face] * xFaceVolumes[face] 
                coefficients[index1+node,index2+3] = BDM1_coeffs[n, row4orientation2[orientation]] * xFaceNormals[k, face] * xFaceVolumes[face] 
            end
            index1 += 4
        end
        # RT0 reconstruction coefficients for face bubbles on reference element
        coefficients[index1+f,index2+1] = xFaceVolumes[face]
        index2 += 3
    end
    return nothing
end
