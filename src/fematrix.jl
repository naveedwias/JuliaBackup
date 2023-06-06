################
### FEMatrix ###
################
#
# used to store (sparse) matrix representations of PDEOperators for FESpaces
# and can have several matrix blocks (FEMatrixBlock) of different FESpaces
# each matrix block acts like an AbstractArray{T,2}

"""
$(TYPEDEF)

block of an FEMatrix that carries coefficients for an associated pair of FESpaces and can be assigned as an two-dimensional AbstractArray (getindex, setindex, size)
"""
struct FEMatrixBlock{TvM,TiM,TvG,TiG,FETypeX,FETypeY,APTX,APTY} <: AbstractArray{TvM,2}
    name::String
    FESX::FESpace{TvG,TiG,FETypeX,APTX}
    FESY::FESpace{TvG,TiG,FETypeY,APTY}
    offsetX::Int64
    offsetY::Int64
    last_indexX::Int64
    last_indexY::Int64
    entries::AbstractSparseMatrix{TvM,TiM} # shares with parent object
end


function Base.show(io::IO, FEB::FEMatrixBlock; tol = 1e-14)
    @printf(io, "\n");
    for j=1:FEB.offsetX+1:FEB.last_indexX
        for k=1:FEB.offsetY+1:FEB.last_indexY
            if FEB.entries[j,k] > tol
                @printf(io, " +%.1e",FEB.entries[j,k]);
            elseif FEB.entries[j,k] < -tol
                @printf(io, " %.1e",FEB.entries[j,k]);
            else
                @printf(io, " ********");
            end
        end
        @printf(io, "\n");
    end    
end


"""
$(TYPEDEF)

an AbstractMatrix (e.g. an ExtendableSparseMatrix) with an additional layer of several FEMatrixBlock subdivisions each carrying coefficients for their associated pair of FESpaces
"""
struct FEMatrix{TvM,TiM,TvG,TiG,nbrow,nbcol,nbtotal}
    FEMatrixBlocks::Array{FEMatrixBlock{TvM,TiM,TvG,TiG},1}
    entries::AbstractSparseMatrix{TvM,TiM}
end

#Add value to matrix if it is nonzero
@inline function _addnz(ESM::ExtendableSparseMatrix,i,j,v::Tv,fac) where Tv
    if v!=zero(Tv)
        rawupdateindex!(ESM,+,v*fac,i,j)
    end
end

#Add value to matrix if it is nonzero
@inline function _addnz(FEB::FEMatrixBlock,i,j,v::Tv,fac) where Tv
    if v!=zero(Tv)
       rawupdateindex!(FEB.entries,+,v*fac,FEB.offsetX+i,FEB.offsetY+j)
    end
end

function apply_nonzero_pattern!(B::FEMatrixBlock,AT::Type{<:AssemblyType})
    dofmapX = Dofmap4AssemblyType(B.FESX,AT)
    dofmapY = Dofmap4AssemblyType(B.FESY,AT)
    @assert num_sources(dofmapX) == num_sources(dofmapY)
    for item = 1 : num_sources(dofmapX)
        for j = 1 : num_targets(dofmapX,item), k = 1 : num_targets(dofmapY,item)
            rawupdateindex!(B.entries,+,0,B.offsetX+dofmapX[j,item],B.offsetY+dofmapY[k,item])
        end
    end
end

Base.getindex(FEF::FEMatrix,i) = FEF.FEMatrixBlocks[i]
Base.getindex(FEF::FEMatrix{TvM,TiM,TvG,TiG,nbrow,nbcol,nbtotal},i,j) where {TvM,TiM,TvG,TiG,nbrow,nbcol,nbtotal} = FEF.FEMatrixBlocks[(i-1)*nbcol+j]
Base.getindex(FEB::FEMatrixBlock,i::Int,j::Int) = FEB.entries[FEB.offsetX+i,FEB.offsetY+j]
Base.getindex(FEB::FEMatrixBlock,i::Any,j::Any) = FEB.entries[FEB.offsetX.+i,FEB.offsetY.+j]
Base.setindex!(FEB::FEMatrixBlock, v, i::Int, j::Int) = setindex!(FEB.entries,v,FEB.offsetX+i,FEB.offsetY+j)


"""
$(TYPEDSIGNATURES)

Gives the number of FEMatrixBlocks in each column.
"""
nbrows(::FEMatrix{TvM,TiM,TvG,TiG,nbrow,nbcol,nbtotal}) where {TvM,TiM,TvG,TiG,nbrow,nbcol,nbtotal} = nbrow


"""
$(TYPEDSIGNATURES)

Gives the number of FEMatrixBlocks in each row.
"""
nbcols(::FEMatrix{TvM,TiM,TvG,TiG,nbrow,nbcol,nbtotal}) where {TvM,TiM,TvG,TiG,nbrow,nbcol,nbtotal} = nbcol

"""
$(TYPEDSIGNATURES)

Custom `size` function for `FEMatrix` that gives a tuple with the number of rows and columns of the FEBlock overlay
"""
Base.size(::FEMatrix{TvM,TiM,TvG,TiG,nbrow,nbcol,nbtotal}) where {TvM,TiM,TvG,TiG,nbrow,nbcol,nbtotal} = (nbrow,nbcol)


"""
$(TYPEDSIGNATURES)

Custom `length` function for `FEMatrix` that gives the total number of defined FEMatrixBlocks in it
"""
Base.length(::FEMatrix{TvM,TiM,TvG,TiG,nbrow,nbcol,nbtotal}) where {TvM,TiM,TvG,TiG,nbrow,nbcol,nbtotal} = nbtotal

"""
$(TYPEDSIGNATURES)

Custom `size` function for `FEMatrixBlock` that gives a tuple with the size of the block (that coressponds to the number of degrees of freedoms in X and Y)
"""
Base.size(FEB::FEMatrixBlock) = (FEB.last_indexX-FEB.offsetX,FEB.last_indexY-FEB.offsetY)

"""
$(TYPEDSIGNATURES)

Custom `show` function for `FEMatrix` that prints some information on its blocks.
"""
function Base.show(io::IO, FEM::FEMatrix{TvM,TiM,TvG,TiG,nbrow,nbcol,nbtotal}) where {TvM,TiM,TvG,TiG,nbrow,nbcol,nbtotal}
	println(io, "\nFEMatrix information")
    println(io, "====================")
    println(io, "  block |  ndofsX |  ndofsY | name (FETypeX, FETypeY) ")
    for j=1:length(FEM)
        n = mod(j-1,nbrow)+1
        m = Int(ceil(j/nbrow))
        @printf(io, "  [%d,%d] |",m,n);
        @printf(io, "  %6d |",FEM[j].FESX.ndofs);
        @printf(io, "  %6d |",FEM[j].FESY.ndofs);
        @printf(io, " %s (%s, %s)\n",FEM[j].name,FEM[j].FESX.name,FEM[j].FESY.name);
    end    
end

"""
````
FEMatrix{TvM,TiM}(name::String, FES::FESpace{TvG,TiG,FETypeX,APTX}) where {TvG,TiG,FETypeX,APTX}
````

Creates FEMatrix with one square block (FES,FES).
"""
function FEMatrix(FES::FESpace; name = "auto")
    return FEMatrix{Float64,Int64}(FES; name = name)
end
function FEMatrix{TvM}(FES::FESpace; name = "auto") where {TvM}
    return FEMatrix{TvM,Int64}(FES; name = name)
end
function FEMatrix{TvM,TiM}(FES::FESpace{TvG,TiG,FETypeX,APTX}; name = "auto") where {TvM,TiM,TvG,TiG,FETypeX,APTX}
    return FEMatrix{TvM,TiM}([FES], [FES]; name = name)
end

"""
````
FEMatrix{TvM,TiM}(FESX, FESY; name = "auto")
````

Creates FEMatrix with one rectangular block (FESX,FESY) if FESX and FESY are single FESpaces, or
a rectangular block matrix with blocks corresponding to the entries of the FESpace vectors FESX and FESY.
Optionally a name for the matrix can be given.
"""
function FEMatrix(FESX::FESpace, FESY::FESpace; name = "auto")
    return FEMatrix{Float64,Int64}(FESX, FESY; name = name)
end
function FEMatrix{TvM}(FESX::FESpace, FESY::FESpace; name = "auto") where {TvM}
    return FEMatrix{TvM,Int64}(FESX, FESY; name = name)
end
function FEMatrix{TvM,TiM}(FESX::FESpace, FESY::FESpace; name = "auto") where {TvM,TiM}
   return FEMatrix{TvM,TiM}([FESX], [FESY]; name = name)
end
function FEMatrix(FES::Array{<:FESpace{TvG,TiG},1}; name = "auto") where {TvG,TiG}
    return FEMatrix{Float64,Int64}(FES; name = name)
end
function FEMatrix{TvM}(FES::Array{<:FESpace{TvG,TiG},1}; name = "auto") where {TvM,TvG,TiG}
    return FEMatrix{TvM,Int64}(FES, FES; name = name)
end
function FEMatrix{TvM,TiM}(FES::Array{<:FESpace{TvG,TiG},1}; name = "auto") where {TvM,TiM,TvG,TiG}
    return FEMatrix{TvM,TiM}(FES, FES; name = name)
end
# main constructor
function FEMatrix{TvM,TiM}(FESX::Array{<:FESpace{TvG,TiG},1}, FESY::Array{<:FESpace{TvG,TiG},1}; name = "auto") where {TvM,TiM,TvG,TiG}
    ndofsX, ndofsY = 0, 0
    for j=1:length(FESX)
        ndofsX += FESX[j].ndofs
    end
    for j=1:length(FESY)
        ndofsY += FESY[j].ndofs
    end
    entries = ExtendableSparseMatrix{TvM,TiM}(ndofsX,ndofsY)

    if name == "auto"
        name = ""
    end

    Blocks = Array{FEMatrixBlock{TvM,TiM,TvG,TiG},1}(undef,length(FESX)*length(FESY))
    offsetX = 0
    offsetY = 0
    for j=1:length(FESX)
        offsetY = 0
        for k=1:length(FESY)
            Blocks[(j-1)*length(FESY)+k] = FEMatrixBlock{TvM,TiM,TvG,TiG,eltype(FESX[j]),eltype(FESY[k]),assemblytype(FESX[j]),assemblytype(FESY[k])}(name * " [$j,$k]", FESX[j], FESY[k], offsetX , offsetY, offsetX+FESX[j].ndofs, offsetY+FESY[k].ndofs, entries)
            offsetY += FESY[k].ndofs
        end    
        offsetX += FESX[j].ndofs
    end    
    
    return FEMatrix{TvM,TiM,TvG,TiG,length(FESX),length(FESY),length(FESX)*length(FESY)}(Blocks, entries)
end

"""
$(TYPEDSIGNATURES)

Custom `fill` function for `FEMatrixBlock` (only fills the block, not the complete FEMatrix).
"""
function Base.fill!(B::FEMatrixBlock{Tv,Ti}, value) where {Tv,Ti}
    cscmat::SparseMatrixCSC{Tv,Ti} = B.entries.cscmatrix
    rows::Array{Int,1} = rowvals(cscmat)
    valsB::Array{Tv,1} = cscmat.nzval
    for col = B.offsetY+1:B.last_indexY
        for r in nzrange(cscmat, col)
            if rows[r] > B.offsetX && rows[r] <= B.last_indexX
                valsB[r] = value
            end
        end
    end
    return nothing
end


"""
$(TYPEDSIGNATURES)

Adds FEMatrix B to FEMatrix A.
"""
function add!(A::FEMatrix{Tv,Ti}, B::FEMatrix{Tv,Ti}; factor = 1, transpose::Bool = false) where {Tv,Ti}
    AM::ExtendableSparseMatrix{Tv,Ti} = A.entries
    BM::ExtendableSparseMatrix{Tv,Ti} = B.entries
    cscmat::SparseMatrixCSC{Tv,Ti} = BM.cscmatrix
    rows::Array{Ti,1} = rowvals(cscmat)
    valsB::Array{Tv,1} = cscmat.nzval
    ncols::Int = size(cscmat,2)
    arow::Int = 0
    if transpose
        for col = 1:ncols
            for r in nzrange(cscmat, col)
                arow = rows[r]
                _addnz(AM,col,arow,valsB[r],factor)
            end
        end
    else
        for col = 1:ncols
            for r in nzrange(cscmat, col)
                arow = rows[r]
                _addnz(AM,arow,col,valsB[r],factor)
            end
        end
    end
    return nothing
end


"""
$(TYPEDSIGNATURES)

Adds FEMatrixBlock B to FEMatrixBlock A.
"""
function addblock!(A::FEMatrixBlock{Tv,Ti}, B::FEMatrixBlock{Tv,Ti}; factor = 1, transpose::Bool = false) where {Tv,Ti}
    AM::ExtendableSparseMatrix{Tv,Ti} = A.entries
    BM::ExtendableSparseMatrix{Tv,Ti} = B.entries
    cscmat::SparseMatrixCSC{Tv,Ti} = BM.cscmatrix
    rows::Array{Ti,1} = rowvals(cscmat)
    valsB::Array{Tv,1} = cscmat.nzval
    arow::Int = 0
    acol::Int = 0
    if transpose
        for col = B.offsetY+1:B.last_indexY
            arow = col - B.offsetY + A.offsetX
            for r in nzrange(cscmat, col)
                if rows[r] > B.offsetX && rows[r] <= B.last_indexX
                    acol = rows[r] - B.offsetX + A.offsetY
                    ## add B[rows[r], col] to A[col, rows[r]]
                    _addnz(AM,arow,acol,valsB[r],factor)
                end
            end
        end
    else
        for col = B.offsetY+1:B.last_indexY
            acol = col - B.offsetY + A.offsetY
            for r in nzrange(cscmat, col)
                if rows[r] > B.offsetX && rows[r] <= B.last_indexX
                    arow = rows[r] - B.offsetX + A.offsetX
                    ## add B[rows[r], col] to A[rows[r], col]
                    _addnz(AM,arow,acol,valsB[r],factor)
                end
            end
        end
    end
    return nothing
end

"""
$(TYPEDSIGNATURES)

Adds ExtendableSparseMatrix B to FEMatrixBlock A.
"""
function addblock!(A::FEMatrixBlock{Tv}, B::ExtendableSparseMatrix{Tv,Ti}; factor = 1, transpose::Bool = false) where {Tv, Ti <: Integer}
    addblock!(A, B.cscmatrix; factor = factor, transpose = transpose)
end


"""
$(TYPEDSIGNATURES)

Adds SparseMatrixCSC B to FEMatrixBlock A.
"""
function addblock!(A::FEMatrixBlock{Tv}, cscmat::SparseArrays.SparseMatrixCSC{Tv, Ti}; factor = 1, transpose::Bool = false) where {Tv, Ti <: Integer}
    AM::ExtendableSparseMatrix{Tv,Int64} = A.entries
    rows::Array{Int,1} = rowvals(cscmat)
    valsB::Array{Tv,1} = cscmat.nzval
    arow::Int = 0
    acol::Int = 0
    if transpose
        for col = 1:size(cscmat,2)
            arow = col + A.offsetX
            for r in nzrange(cscmat, col)
                acol = rows[r] + A.offsetY
                _addnz(AM,arow,acol,valsB[r],factor)
                #A[rows[r],col] += B.cscmatrix.nzval[r] * factor
            end
        end
    else
        for col = 1:size(cscmat,2)
            acol = col + A.offsetY
            for r in nzrange(cscmat, col)
                arow = rows[r] + A.offsetX
                _addnz(AM,arow,acol,valsB[r],factor)
                #A[rows[r],col] += B.cscmatrix.nzval[r] * factor
            end
        end
    end
    return nothing
end

function apply_penalties!(A::ExtendableSparseMatrix, fixed_dofs, penalty)
    for dof in fixed_dofs
        A[dof,dof] = penalty
    end
    flush!(A)
    return nothing
end

"""
$(TYPEDSIGNATURES)

Adds matrix-matrix product B times C to FEMatrixBlock A.
"""
function addblock_matmul!(A::FEMatrixBlock{Tv}, cscmatB::SparseMatrixCSC{Tv,Ti}, cscmatC::SparseMatrixCSC{Tv,Ti}; factor = 1, transposed::Bool = false) where {Tv,Ti}
    AM::ExtendableSparseMatrix{Tv,Int64} = A.entries
    rowsB::Array{Ti,1} = rowvals(cscmatB)
    rowsC::Array{Ti,1} = rowvals(cscmatC)
    valsB::Array{Tv,1} = cscmatB.nzval
    valsC::Array{Tv,1} = cscmatC.nzval
    bcol::Int = 0
    row::Int = 0
    arow::Int = 0
    if transposed # add (B*C)'= C'*B' to A
        for i = 1:size(cscmatC, 2)
            arow = i + A.offsetX
            for crow in nzrange(cscmatC, i)
                for j in nzrange(cscmatB, rowsC[crow])
                    acol = rowsB[j] + A.offsetY
                    # add b[j,crow]*c[crow,i] to a[i,j]
                    _addnz(AM,arow,acol,valsB[j]*valsC[crow],factor)
                end
            end
        end
    else # add B*C to A
        for j = 1:size(cscmatC, 2)
            acol = j + A.offsetY
            for crow in nzrange(cscmatC, j)
                for i in nzrange(cscmatB, rowsC[crow])
                    arow = rowsB[i] + A.offsetX
                    # add b[i,crow]*c[crow,j] to a[i,j]
                    _addnz(AM,arow,acol,valsB[i]*valsC[crow],factor)
                end
            end
        end
    end
    return nothing
end

"""
$(TYPEDSIGNATURES)

Adds matrix-vector product B times b (or B' times b if transposed = true) to FEVectorBlock a.
"""
function addblock_matmul!(a::FEVectorBlock{Tv}, B::FEMatrixBlock{Tv,Ti}, b::FEVectorBlock{Tv}; factor = 1, transposed::Bool = false) where {Tv,Ti}
    cscmat::SparseMatrixCSC{Tv,Ti} = B.entries.cscmatrix
    rows::Array{Ti,1} = rowvals(cscmat)
    valsB::Array{Tv,1} = cscmat.nzval
    row::Int = 0
    if transposed
        brow::Int = 0
        acol::Int = 0
        for col = B.offsetY+1:B.last_indexY
            acol = col-B.offsetY+a.offset
            for r in nzrange(cscmat, col)
                row = rows[r]
                if row > B.offsetX && row <= B.last_indexX
                    brow = row - B.offsetX + b.offset
                    a.entries[acol] += valsB[r] * b.entries[brow] * factor 
                end
            end
        end
    else
        bcol::Int = 0
        arow::Int = 0
        for col = B.offsetY+1:B.last_indexY
            bcol = col-B.offsetY+b.offset
            for r in nzrange(cscmat, col)
                row = rows[r]
                if row > B.offsetX && row <= B.last_indexX
                    arow = row - B.offsetX + a.offset
                    a.entries[arow] += valsB[r] * b.entries[bcol] * factor 
                end
            end
        end
    end
    return nothing
end

"""
$(TYPEDSIGNATURES)

Adds matrix-vector product B times b to FEVectorBlock a.
"""
function addblock_matmul!(a::AbstractVector{Tv}, B::FEMatrixBlock{Tv,Ti}, b::AbstractVector{Tv}; factor = 1, transposed::Bool = false) where {Tv,Ti}
    cscmat::SparseMatrixCSC{Tv,Ti} = B.entries.cscmatrix
    rows::Array{Ti,1} = rowvals(cscmat)
    valsB::Array{Tv,1} = cscmat.nzval
    bcol::Int = 0
    row::Int = 0
    arow::Int = 0
    if transposed
        for col = B.offsetY+1:B.last_indexY
            bcol = col-B.offsetY
            for r in nzrange(cscmat, col)
                row = rows[r]
                if row > B.offsetX && row <= B.last_indexX
                    arow = row - B.offsetX
                    a[bcol] += valsB[r] * b[arow] * factor 
                end
            end
        end
    else
        for col = B.offsetY+1:B.last_indexY
            bcol = col-B.offsetY
            for r in nzrange(cscmat, col)
                row = rows[r]
                if row > B.offsetX && row <= B.last_indexX
                    arow = row - B.offsetX
                    a[arow] += valsB[r] * b[bcol] * factor 
                end
            end
        end
    end
    return nothing
end



"""
$(TYPEDSIGNATURES)

Adds matrix-vector product B times b to FEVectorBlock a.
"""
function addblock_matmul!(a::FEVectorBlock{Tv}, B::ExtendableSparseMatrix{Tv,Ti}, b::FEVectorBlock{Tv}; factor = 1) where {Tv, Ti <: Integer}
    cscmat::SparseMatrixCSC{Tv,Ti} = B.cscmatrix
    rows::Array{Ti,1} = rowvals(cscmat)
    valsB::Array{Tv,1} = cscmat.nzval
    bcol::Int = 0
    arow::Int = 0
    for col = 1:size(B,2)
        bcol = col+b.offset
        for r in nzrange(cscmat, col)
            arow = rows[r] + a.offset
            a.entries[arow] += valsB[r] * b.entries[bcol] * factor
        end
    end
    return nothing
end



"""
$(TYPEDSIGNATURES)

Computes vector'-matrix-vector product a'*B*b.
"""
function lrmatmul(a::AbstractVector{Tv}, B::ExtendableSparseMatrix{Tv,Ti}, b::AbstractVector{Tv}; factor = 1) where {Tv, Ti <: Integer}
    cscmat::SparseMatrixCSC{Tv,Ti} = B.cscmatrix
    valsB::Array{Tv,1} = cscmat.nzval
    rows::Array{Ti,1} = rowvals(cscmat)
    result = 0.0
    for col = 1:size(B,2)
        for r in nzrange(B.cscmatrix, col)
            result += valsB[r] * b[col] * factor * a[rows[r]]
        end
    end
    return result
end


"""
$(TYPEDSIGNATURES)

Computes vector'-matrix-vector product (a1-a2)'*B*(b1-b2).
"""
function ldrdmatmul(a1::AbstractVector{Tv}, a2::AbstractVector{Tv}, B::ExtendableSparseMatrix{Tv,Ti}, b1::AbstractVector{Tv}, b2::AbstractVector{Tv}; factor = 1) where {Tv, Ti <: Integer}
    cscmat::SparseMatrixCSC{Tv,Ti} = B.cscmatrix
    valsB::Array{Tv,1} = cscmat.nzval
    rows::Array{Ti,1} = rowvals(cscmat)
    result = 0.0
    for col = 1:size(B,2)
        for r in nzrange(B.cscmatrix, col)
            result += valsB[r] * (b1[col] - b2[col]) * factor * (a1[rows[r]] - a2[rows[r]])
        end
    end
    return result
end