###################
# QuadratureRules #
###################
#
# here all quadrature rules for the different ElementGeometries are collected
# there are some hard-coded ones for the lowest-order rules (that might be extended later)
# and also generic functions that generate rules of arbitrary order
#
# integrate! allows to intgrate cell-wise (order face-wise etc. depending on the AssemblyType)
# integrate does the same but only returns the full integral and is more memory-friendly

"""
$(TYPEDEF)

A struct that contains the name of the quadrature rule, the reference points and the weights for the parameter-determined element geometry.
"""
abstract type QuadratureRule{T <: Real, ET <: AbstractElementGeometry} end

struct SQuadratureRule{T <: Real, ET <: AbstractElementGeometry, dim, npoints} <: QuadratureRule{T, ET}
    name::String
    xref::Array{SVector{dim,T},1}
    w::Array{T,1}
end


"""
$(TYPEDSIGNATURES)

Custom `eltype` function for `QuadratureRule{T,ET}`.
"""
Base.eltype(::QuadratureRule{T,ET}) where{T <: Real, ET <: AbstractElementGeometry} = [T,ET]

"""
$(TYPEDSIGNATURES)

Custom `show` function for `QuadratureRule{T,ET}` that prints some information.
"""
function Base.show(io::IO, Q::QuadratureRule{T,ET} where{T <: Real, ET <: AbstractElementGeometry})
    npoints = length(Q.xref);
    println("QuadratureRule information");
    println("    shape ; $(eltype(Q)[2])")
	println("     name : $(Q.name)");
	println("  npoints : $(npoints) ($(eltype(Q)[1]))")
end

# sets up a quadrature rule that evaluates at vertices of element geometry
# not optimal from quadrature point of view, but helpful when interpolating
# order of xref matches dof order of H1Pk element
function VertexRule(ET::Type{Edge1D}, order = 1)
    xref = [[0],[1.0]]
    for j = 1:order-1
        push!(xref,[j/order])
    end
    w = ones(Float64, length(xref)) / length(xref)
    return SQuadratureRule{Float64, ET, dim_element(ET), length(w)}("vertex rule edge", xref, w)
end
function VertexRule(ET::Type{Triangle2D}, order = 1)
    xref = [[0, 0], [1.0,0], [0,1.0]]
    lcen = local_celledgenodes(ET)
    for j = 1:order-1
        for edge = 1 : size(lcen,2)
            push!(xref, j/order * xref[lcen[2,edge]] + (1 - j/order) * xref[lcen[1,edge]])
        end
    end
    if order == 3
        push!(xref,[1/3, 1/3])
    end
    if order == 4
        push!(xref,[1/4, 1/4])
        push!(xref,[1/2, 1/4])
        push!(xref,[1/4, 1/1])
    end
    if order > 4
        @warn "VertexRule for order > 4 on $ET not yet implemented"
    end
    w = ones(Float64, length(xref)) / length(xref)
    return SQuadratureRule{Float64, ET, dim_element(ET), length(w)}("vertex rule triangle", xref, w)
end
function VertexRule(ET::Type{Parallelogram2D}, order = 1)
    xref = [[0, 0], [1.0,0], [1.0,1.0], [0,1.0]]
    lcen = local_celledgenodes(ET)
    for j = 1:order-1
        for edge = 1 : size(lcen,2)
            push!(xref, j/order * xref[lcen[2,edge]] + (1 - j/order) * xref[lcen[1,edge]])
        end
    end
    if order > 2
        @warn "VertexRule for order > 2 on $ET not yet implemented"
    end
    w = ones(Float64, length(xref)) / length(xref)
    return SQuadratureRule{Float64, ET, dim_element(ET), length(w)}("vertex rule parallelogram", xref, w)
end
function VertexRule(ET::Type{Tetrahedron3D}, order = 1)
    xref = [[0, 0, 0], [1.0, 0, 0], [0,1.0,0], [0,0,1.0]]
    lcen = local_celledgenodes(ET)
    for j = 1:order-1
        for edge = 1 : size(lcen,2)
            push!(xref, j/order * xref[lcen[2,edge]] + (1 - j/order) * xref[lcen[1,edge]])
        end
    end
    if order > 2
        @warn "VertexRule for order > 2 on $ET not yet implemented"
    end
    w = ones(Float64, length(xref)) / length(xref)
    return SQuadratureRule{Float64, ET, dim_element(ET), length(w)}("vertex rule tetrahedron", xref, w)
end
function VertexRule(ET::Type{Parallelepiped3D}, order = 1)
    xref = [[0, 0, 0], [1.0, 0, 0], [1.0, 1.0, 0], [0, 1.0, 0], [0, 0, 1.0], [1.0, 0, 1], [1.0, 1.0, 1.0], [0, 1.0, 1.0]]
    lcen = local_celledgenodes(ET)
    for j = 1:order-1
        for edge = 1 : size(lcen,2)
            push!(xref, j/order * xref[lcen[2,edge]] + (1 - j/order) * xref[lcen[1,edge]])
        end
    end
    if order > 1
        @warn "VertexRule for order > 2 on $ET not yet implemented"
    end
    w = ones(Float64, length(xref)) / length(xref)
    return SQuadratureRule{Float64, ET, dim_element(ET), length(w)}("vertex rule parallelepiped", xref, w)
end


"""
````
function QuadratureRule{T,ET}(order::Int) where {T<:Real, ET <: AbstractElementGeometry1D}
````

Constructs 1D quadrature rule of specified order.
"""
function QuadratureRule{T,ET}(order::Int) where {T<:Real, ET <: AbstractElementGeometry1D}
    if order <= 1
        name = "midpoint rule"
        xref = Vector{Array{T,1}}(undef,1);
        xref[1] = ones(T,1) * 1 // 2
        w = [1]
    elseif order == 2
        name = "Simpson's rule"
        xref = Vector{Array{T,1}}(undef,3);
        xref[1] = [0];
        xref[2] = [1//2];
        xref[3] = [1];
        w = [1//6; 2//3; 1//6]     
    else
        name = "generic Gauss rule of order $order"
        xref, w = get_generic_quadrature_Gauss(order)
    end
    return SQuadratureRule{T, ET, dim_element(ET), length(w)}(name, xref, w)
end

"""
````
function QuadratureRule{T,ET}(order::Int) where {T<:Real, ET <: AbstractElementGeometry0D}
````

Constructs 0D quadrature rule of specified order (always point evaluation).
"""
function QuadratureRule{T,ET}(order::Int) where {T<:Real, ET <: AbstractElementGeometry0D}
    name = "point evaluation"
    xref = Vector{Array{T,1}}(undef,1);
    xref[1] = ones(T,1)
    w = [1]
    return SQuadratureRule{T, ET, 1, length(w)}(name, xref, w)
end


"""
````
function QuadratureRule{T,ET}(order::Int) where {T<:Real, ET <: Triangle2D}
````

Constructs quadrature rule on Triangle2D of specified order.
"""
function QuadratureRule{T,ET}(order::Int; force_symmetric_rule::Bool = false) where {T<:Real, ET <: Triangle2D}
  if order <= 1
      name = "midpoint rule"
      xref = Vector{Array{T,1}}(undef,1);
      xref[1] = ones(T,2) * 1 // 3
      w = [1]
  elseif order == 2 # face midpoint rule  
      name = "face midpoints rule"
      xref = Vector{Array{T,1}}(undef,3);
      xref[1] = [1//2,1//2];
      xref[2] = [0//1,1//2];
      xref[3] = [1//2,0//1];
      w = [1//3; 1//3; 1//3]     
  elseif order == 8 || (force_symmetric_rule && order <=8) # symmetric rule
      xref, w, name = get_symmetric_rule(ET, order)
  elseif (order >= 12 && order <= 14) || (force_symmetric_rule && order <=14) # symmetric rule
      xref, w, name = get_symmetric_rule(ET, order)
  else
      name = "generic Stroud rule of order $order"
      xref, w = get_generic_quadrature_Stroud(order)
  end
  return SQuadratureRule{T, ET, dim_element(ET), length(w)}(name, xref, w)
end


"""
````
function QuadratureRule{T,ET}(order::Int) where {T<:Real, ET <: Parallelogram2D}
````

Constructs quadrature rule on Parallelogram2D of specified order.
"""
function QuadratureRule{T,ET}(order::Int) where {T<:Real, ET <: Parallelogram2D}
  if order <= 1
      name = "midpoint rule"
      xref = Vector{Array{T,1}}(undef,1);
      xref[1] = ones(T,2) * 1 // 2
      w = [1]
  else
      name = "generic Gauss tensor rule of order $order"
      xref1D, w1D = get_generic_quadrature_Gauss(order)
      xref = Vector{Array{T,1}}(undef,length(xref1D)^2)
      w = zeros(T,length(xref1D)^2)
      index = 1
      for j = 1 : length(xref1D), k = 1 : length(xref1D)
        xref[index] = zeros(T,2)
        xref[index][1] = xref1D[j][1]
        xref[index][2] = xref1D[k][1]
        w[index] = w1D[j] * w1D[k]
        index += 1
      end
  end
  return SQuadratureRule{T, ET, dim_element(ET), length(w)}(name, xref, w)
end


"""
````
function QuadratureRule{T,ET}(order::Int) where {T<:Real, ET <: Parallelepiped3D}
````

Constructs quadrature rule on Parallelepiped3D of specified order.
"""
function QuadratureRule{T,ET}(order::Int) where {T<:Real, ET <: Parallelepiped3D}
  if order <= 1
      name = "midpoint rule"
      xref = Vector{Array{T,1}}(undef,1);
      xref[1] = ones(T,3) * 1 // 2
      w = [1]
  else
      name = "generic Gauss tensor rule of order $order"
      xref1D, w1D = get_generic_quadrature_Gauss(order)
      xref = Vector{Array{T,1}}(undef,length(xref1D)^3)
      w = zeros(T,length(xref1D)^3)
      index = 1
      for j = 1 : length(xref1D), k = 1 : length(xref1D), l = 1 : length(xref1D)
        xref[index] = zeros(T,3)
        xref[index][1] = xref1D[j][1]
        xref[index][2] = xref1D[k][1]
        xref[index][3] = xref1D[l][1]
        w[index] = w1D[j] * w1D[k] * w1D[l]
        index += 1
      end
  end
  return SQuadratureRule{T, ET, dim_element(ET), length(w)}(name, xref, w)
end


"""
````
function QuadratureRule{T,ET}(order::Int) where {T<:Real, ET <: Tetrahedron3D}
````

Constructs quadrature rule on Tetrahedron3D of specified order.
"""
function QuadratureRule{T,ET}(order::Int; force_symmetric_rule::Bool = false) where {T<:Real, ET <: Tetrahedron3D}
  if order <= 1
      name = "midpoint rule"
      xref = Vector{Array{T,1}}(undef,1);
      xref[1] = ones(T,3) * 1 // 4
      w = [1]
  elseif order == 2
      # Ref
      # P Keast, Moderate degree tetrahedral quadrature formulas, CMAME 55: 339-348 (1986)
      # O. C. Zienkiewicz, The Finite Element Method,  Sixth Edition,
      name = "order 2 rule"
      xref = Vector{Array{T,1}}(undef,4);
      xref[1] = [0.1381966011250105,0.1381966011250105,0.1381966011250105]
      xref[2] = [0.5854101966249685,0.1381966011250105,0.1381966011250105]
      xref[3] = [0.1381966011250105,0.5854101966249685,0.1381966011250105]
      xref[4] = [0.1381966011250105,0.1381966011250105,0.5854101966249685]
      w = ones(T,4) * 1 // 4
  elseif order <= 3 # up to order 3 exact
      # Ref
      # P Keast, Moderate degree tetrahedral quadrature formulas, CMAME 55: 339-348 (1986)
      # O. C. Zienkiewicz, The Finite Element Method,  Sixth Edition,
      name = "order 3 rule"
      xref = Vector{Array{T,1}}(undef,5);
      xref[1] = [1//4,1//4,1//4]
      xref[2] = [1//2,1//6,1//6]
      xref[3] = [1//6,1//6,1//6]
      xref[4] = [1//6,1//6,1//2]
      xref[5] = [1//6,1//2,1//6]
      w = [-4//5,9//20,9//20,9//20,9//20]
  elseif order <= 4 # up to order 4 exact
      # Ref
      # P Keast, Moderate degree tetrahedral quadrature formulas, CMAME 55: 339-348 (1986)
      # O. C. Zienkiewicz, The Finite Element Method,  Sixth Edition,

      name = "order 4 rule"
      xref = Vector{Array{T,1}}(undef,11);
      xref[1]  = [0.2500000000000000, 0.2500000000000000, 0.2500000000000000 ]
      xref[2]  = [0.7857142857142857, 0.0714285714285714, 0.0714285714285714 ]
      xref[3]  = [0.0714285714285714, 0.0714285714285714, 0.0714285714285714 ]
      xref[4]  = [0.0714285714285714, 0.0714285714285714, 0.7857142857142857 ]
      xref[5]  = [0.0714285714285714, 0.7857142857142857, 0.0714285714285714 ]
      xref[6]  = [0.1005964238332008, 0.3994035761667992, 0.3994035761667992 ]
      xref[7]  = [0.3994035761667992, 0.1005964238332008, 0.3994035761667992 ]
      xref[8]  = [0.3994035761667992, 0.3994035761667992, 0.1005964238332008 ]
      xref[9]  = [0.3994035761667992, 0.1005964238332008, 0.1005964238332008 ]
      xref[10] = [0.1005964238332008, 0.3994035761667992, 0.1005964238332008 ]
      xref[11] = [0.1005964238332008, 0.1005964238332008, 0.3994035761667992 ]
      w = [-0.0789333333333333, 0.0457333333333333, 0.0457333333333333, 0.0457333333333333, 0.0457333333333333, 0.1493333333333333, 0.1493333333333333, 0.1493333333333333, 0.1493333333333333, 0.1493333333333333, 0.1493333333333333]

  elseif order <= 8  # symmetric rule
      xref, w, name = get_symmetric_rule(ET, order)
  else
      @warn "no quadrature rule with order $order available, will take order 8 instead"
      xref, w, name = get_symmetric_rule(ET, 8)
      # no higher order generic rule implemented yet
  end
  return SQuadratureRule{T, ET, dim_element(ET), length(w)}(name, xref, w)
end


## recipe taken from:
## "A SET OF SYMMETRIC QUADRATURE RULESON TRIANGLES AND TETRAHEDRA"
## Zhang/Cui/Liu
## Journal of Computational Mathematics, Vol.27, No.1, 2009,89–96
function get_symmetric_rule(::Type{Triangle2D}, order::Int)

    # define abscissas and weights for orbits
    if order <= 1
        weights_S3 = 1.0
        npoints = 1
        name = "symmetric rule order 1"
    elseif order <= 8
        weights_S3 = .1443156076777871682510911104890646
        abscissas_S21 = [.1705693077517602066222935014914645,
                         .0505472283170309754584235505965989,
                         .4592925882927231560288155144941693]
        weights_S21 = [.1032173705347182502817915502921290,
                       .0324584976231980803109259283417806,
                       .0950916342672846247938961043885843]
        abscissas_S111 = [[.2631128296346381134217857862846436, .0083947774099576053372138345392944]]
        weights_S111 = [.0272303141744349942648446900739089]
        npoints = 16
        name = "symmetric rule order 8"
    elseif order <= 14
        weights_S3 = .0585962852260285941278938063477560
        abscissas_S21 = [.0099797608064584324152935295820524,
                         .4799778935211883898105528650883899,
                         .1538119591769669000000000000000000,
                         .0740234771169878100000000000000000,
                         .1303546825033300000000000000000000,
                         .2306172260266531342996053700983831,
                         .4223320834191478241144087137913939]
        weights_S21 = [.0017351512297252675680618638808094,
                       .0261637825586145217778288591819783,
                       .0039197292424018290965208275701454,
                       .0122473597569408660972869899262505,
                       .0281996285032579601073663071515657,
                       .0508870871859594852960348275454540,
                       .0504534399016035991910208971341189]
        abscissas_S111 = [[.7862373859346610033296221140330900,.1906163600319009042461432828653034],
                          [.6305521436606074416224090755688129,.3623231377435471446183267343597729],
                          [.6265773298563063142335123137534265,.2907712058836674150248168174816732],
                          [.9142099849296254122399670993850469,.0711657108777507625475924502924336]]
        weights_S111 = [.0170636442122334512900253993849472,
                        .0096834664255066004075209630934194,
                        .0363857559284850056220113277642717,
                        .0069646633735184124253997225042413]
        npoints = 46
        name = "symmetric rule order 14"
    end

    # collect quadrature points and weights
    xref = Vector{Array{Float64,1}}(undef,npoints);
    w = zeros(Float64,npoints)
    xref[1] = [1//3, 1//3]
    w[1] = weights_S3

    # each abscissa in orbit S21 generates three points
    if length(weights_S21) > 0
        for j = 1 : length(weights_S21)
            xref[1 + (j-1)*3 + 1] = [abscissas_S21[j],abscissas_S21[j]]
            xref[1 + (j-1)*3 + 2] = [abscissas_S21[j],1-2*abscissas_S21[j]]
            xref[1 + (j-1)*3 + 3] = [1-2*abscissas_S21[j],abscissas_S21[j]]
            for k = 1 : 3
                w[1+(j-1)*3 + k] = weights_S21[j]
            end
        end
    end

    # each abscissa in orbit S111 generates six points
    if length(weights_S111) > 0
        offset = 1 + length(weights_S21)*3
        for j = 1 : length(weights_S111)
            xref[offset + (j-1)*6 + 1] = [abscissas_S111[j][1],abscissas_S111[j][2]]
            xref[offset + (j-1)*6 + 2] = [abscissas_S111[j][2],abscissas_S111[j][1]]
            xref[offset + (j-1)*6 + 3] = [abscissas_S111[j][1],1-abscissas_S111[j][1]-abscissas_S111[j][2]]
            xref[offset + (j-1)*6 + 4] = [abscissas_S111[j][2],1-abscissas_S111[j][1]-abscissas_S111[j][2]]
            xref[offset + (j-1)*6 + 5] = [1-abscissas_S111[j][1]-abscissas_S111[j][2],abscissas_S111[j][1]]
            xref[offset + (j-1)*6 + 6] = [1-abscissas_S111[j][1]-abscissas_S111[j][2],abscissas_S111[j][2]]
            for k = 1 : 6
                w[offset + (j-1)*6 + k] = weights_S111[j]
            end
        end
    end

    return xref, w, name
end


## recipe taken from:
## "A SET OF SYMMETRIC QUADRATURE RULESON TRIANGLES AND TETRAHEDRA"
## Zhang/Cui/Liu
## Journal of Computational Mathematics, Vol.27, No.1, 2009,89–96
function get_symmetric_rule(::Type{Tetrahedron3D}, order::Int)

    # define abscissas and weights for orbits
    if order <= 8
        abscissas_S31 = [.0396754230703899012650713295393895,
                         .3144878006980963137841605626971483,
                         .1019866930627033000000000000000000,
                         .1842036969491915122759464173489092]
        weights_S31 = [.0063971477799023213214514203351730,
                       .0401904480209661724881611584798178,
                       .0243079755047703211748691087719226,
                       .0548588924136974404669241239903914]
        abscissas_S22 = [.0634362877545398924051412387018983]
        weights_S22 = [.0357196122340991824649509689966176]
        abscissas_S211 = [[.0216901620677280048026624826249302,.7199319220394659358894349533527348],
                          [.2044800806367957142413355748727453,.5805771901288092241753981713906204]]
        weights_S211 = [.0071831906978525394094511052198038,
                        .0163721819453191175409381397561191]
        npoints = 46
        name = "symmetric rule order 8"
    end

    # collect quadrature points and weights
    xref = Vector{Array{Float64,1}}(undef,npoints);
    w = zeros(Float64,npoints)

    # each abscissa in orbit S31 generates four points
    if length(weights_S31) > 0
        for j = 1 : length(weights_S31)
            xref[(j-1)*4 + 1] = [abscissas_S31[j],abscissas_S31[j],abscissas_S31[j]]
            xref[(j-1)*4 + 2] = [abscissas_S31[j],abscissas_S31[j],1-3*abscissas_S31[j]]
            xref[(j-1)*4 + 3] = [abscissas_S31[j],1-3*abscissas_S31[j],abscissas_S31[j]]
            xref[(j-1)*4 + 4] = [1-3*abscissas_S31[j],abscissas_S31[j],abscissas_S31[j]]
            for k = 1 : 4
                w[(j-1)*4 + k] = weights_S31[j]
            end
        end
    end

    # each abscissa in orbit S22 generates six points
    if length(weights_S22) > 0
        offset = length(weights_S31)*4
        for j = 1 : length(weights_S22)
            xref[offset + (j-1)*6 + 1] = [abscissas_S22[j],abscissas_S22[j],1//2 - abscissas_S22[j]]
            xref[offset + (j-1)*6 + 2] = [abscissas_S22[j],1//2 - abscissas_S22[j],abscissas_S22[j]]
            xref[offset + (j-1)*6 + 3] = [1//2 - abscissas_S22[j],abscissas_S22[j],abscissas_S22[j]]
            xref[offset + (j-1)*6 + 4] = [1//2 - abscissas_S22[j],abscissas_S22[j],1//2-abscissas_S22[j]]
            xref[offset + (j-1)*6 + 5] = [1//2 - abscissas_S22[j],1//2-abscissas_S22[j],abscissas_S22[j]]
            xref[offset + (j-1)*6 + 6] = [abscissas_S22[j],1//2 - abscissas_S22[j],1//2-abscissas_S22[j]]
            for k = 1 : 6
                w[offset + (j-1)*6 + k] = weights_S22[j]
            end
        end
    end

    # each abscissa in orbit S211 generates twelve points
    if length(weights_S211) > 0
        offset = length(weights_S31)*4 + length(weights_S22)*6
        for j = 1 : length(weights_S211)
            a = abscissas_S211[j][1]
            b = abscissas_S211[j][2]
            c = 1 - 2*a - b
            xref[offset + (j-1)*12 + 1] = [a,a,b]
            xref[offset + (j-1)*12 + 2] = [a,b,a]
            xref[offset + (j-1)*12 + 3] = [b,a,a]
            xref[offset + (j-1)*12 + 4] = [a,a,c]
            xref[offset + (j-1)*12 + 5] = [a,c,a]
            xref[offset + (j-1)*12 + 6] = [c,a,a]
            xref[offset + (j-1)*12 + 7] = [a,b,c]
            xref[offset + (j-1)*12 + 8] = [a,c,b]
            xref[offset + (j-1)*12 + 9] = [c,a,b]
            xref[offset + (j-1)*12 + 10] = [b,a,c]
            xref[offset + (j-1)*12 + 11] = [b,c,a]
            xref[offset + (j-1)*12 + 12] = [c,b,a]
            for k = 1 : 12
                w[offset + (j-1)*12 + k] = weights_S211[j]
            end
        end
    end

    return xref, w, name
end



function get_generic_quadrature_Gauss(order::Int)
    ngpts::Int = div(order, 2) + 1
    
    # compute 1D Gauss points on interval [-1,1] and weights
    gamma = (1 : ngpts-1) ./ sqrt.(4 .* (1 : ngpts-1).^2 .- ones(ngpts-1,1) );
    F = eigen(diagm(1 => gamma[:], -1 => gamma[:]));
    r = F.values;
    w = 2*F.vectors[1,:].^2;
    
    # transform to interval [0,1]
    r = .5 .* r .+ .5;
    w = .5 .* w';

    xref = Array{Array{Float64,1}}(undef,length(r))
    for j = 1 : length(r)
        xref[j] = [r[j]];
    end
    
    return xref, w[:]
end
  
# computes quadrature points and weights by Stroud Conical Product rule
function get_generic_quadrature_Stroud(order::Int)
    ngpts::Int = div(order, 2) + 1
    
    # compute 1D Gauss points on interval [-1,1] and weights
    gamma = (1 : ngpts-1) ./ sqrt.(4 .* (1 : ngpts-1).^2 .- ones(ngpts-1,1) );
    F = eigen(diagm(1 => gamma[:], -1 => gamma[:]));
    r = F.values;
    a = 2*F.vectors[1,:].^2;
    
    # compute 1D Gauss-Jacobi Points for Intervall [-1,1] and weights
    delta = -1 ./ (4 .* (1 : ngpts).^2 .- ones(ngpts,1));
    gamma = sqrt.((2 : ngpts) .* (1 : ngpts-1)) ./ (2 .* (2 : ngpts) .- ones(ngpts-1,1));
    F = eigen(diagm(0 => delta[:], 1 => gamma[:], -1 => gamma[:]));
    s = F.values;
    b = 2*F.vectors[1,:].^2;
    
    # transform to interval [0,1]
    r = .5 .* r .+ .5;
    s = .5 .* s .+ .5;
    a = .5 .* a';
    b = .5 .* b';
    
    # apply conical product rule
    # xref[:,[1 2]] = [ s_j , r_i(1-s_j) ] 
    # w = a_i*b_j
    s = repeat(s',ngpts,1)[:];
    r = repeat(r,ngpts,1);
    xref = Array{Array{Float64,1}}(undef,length(s))
    for j = 1 : length(s)
        xref[j] = s[j].*[1,0] - r[j]*(s[j]-1).*[0,1];
    end
    w = a'*b;
    
    return xref, w[:]
end


"""
$(TYPEDSIGNATURES)

Integration that writes result on every item into integral4items.
"""
function integrate!(
    integral4items::AbstractArray{T},
    grid::ExtendableGrid,
    AT::Type{<:AssemblyType},
    integrand::AbstractUserDataType;
    index_offsets = 0,
    time = 0,
    items = [],
    force_quadrature_rule = nothing) where {T}

    if index_offsets == 0
        index_offsets = zeros(Int, integrand.argsizes[1])
    end
    
    order = integrand.bonus_quadorder
    resultdim = integrand.argsizes[1]
    xCoords = grid[Coordinates]
    dim = size(xCoords,1)
    @assert dim == integrand.argsizes[2] || integrand.argsizes[2] == 0
    xItemNodes = grid[GridComponentNodes4AssemblyType(AT)]
    nitems = num_sources(xItemNodes)
    xItemVolumes = grid[GridComponentVolumes4AssemblyType(AT)]
    if AT == ON_EDGES
        xItemRegions = 1:nitems # currently no edge regions are handled, so take something cheap here
    else
        xItemRegions = grid[GridComponentRegions4AssemblyType(AT)]
    end
    xItemGeometries = grid[GridComponentGeometries4AssemblyType(AT)]
    if AT in [ON_FACES, ON_BFACES, ON_IFACES]
        xCellParents = view(grid[FaceCells],1,:)
    elseif AT in [ON_EDGES, ON_BEDGES]
        xEdgeCells = grid[EdgeCells]
        xCellParents = zeros(Int,nitems)
        for edge = 1 : nitems
            xCellParents[edge] = xEdgeCells[1, edge]
        end
        # not working, but would be better
        # xCellParents = view(grid[EdgeCells],1,:)
    else
        xCellParents = 1:nitems
    end
    
    # find proper quadrature rules
    EG = grid[GridComponentUniqueGeometries4AssemblyType(AT)]
    qf = Array{QuadratureRule,1}(undef,length(EG))
    local2global = Array{L2GTransformer,1}(undef,length(EG))
    for j = 1 : length(EG)
        if force_quadrature_rule !== nothing
            qf[j] = force_quadrature_rule;
        else
            qf[j] = QuadratureRule{T,EG[j]}(order);
        end
        local2global[j] = L2GTransformer(EG[j],grid,AT)
    end    
    xrefdim::Int = length(qf[1].xref[1])

    # loop over items
    if items == []
        items = 1 : nitems
    end
    itemET = xItemGeometries[1]
    iEG = 1

    set_time!(integrand, time)
    if typeof(integral4items) <: AbstractArray{T,1}
        for it = 1 : length(items)
            item = items[it]
            for j = 1 : integrand.argsizes[1]
                integral4items[item+index_offsets[j]] = 0
            end

            # find index for CellType
            itemET = xItemGeometries[item]
            iEG = findfirst(isequal(itemET), EG)

            update_trafo!(local2global[iEG],item)
            
            if is_itemdependent(integrand)
                integrand.item[1] = item
                integrand.item[2] = item
                integrand.item[3] = xItemRegions[item]
                integrand.item[4] = xCellParents[item]
            end

            for i in eachindex(qf[iEG].w)
                if is_xdependent(integrand)
                    eval_trafo!(integrand.x, local2global[iEG], qf[iEG].xref[i])
                end
                for j = 1 : xrefdim
                    integrand.xref[j] = qf[iEG].xref[i][j]
                end
                eval_data!(integrand)
                for j = 1 : integrand.argsizes[1]
                    integral4items[item+index_offsets[j]] += integrand.val[j] * qf[iEG].w[i] * xItemVolumes[item];
                end
            end  
        end
    else # <: AbstractArray{T,2}
        fill!(integral4items,0)
        item::Int = 0
        for it = 1 : length(items)
            item = items[it]
            # find index for CellType
            itemET = xItemGeometries[item]
            iEG = findfirst(isequal(itemET), EG)

            update_trafo!(local2global[iEG],item)

            if is_itemdependent(integrand)
                integrand.item[1] = item
                integrand.item[2] = item
                integrand.item[3] = xItemRegions[item]
                integrand.item[4] = xCellParents[item]
            end

            for i in eachindex(qf[iEG].w)
                if is_xdependent(integrand)
                    eval_trafo!(integrand.x, local2global[iEG], qf[iEG].xref[i])
                end
                if is_xrefdependent(integrand)
                    for j = 1 : xrefdim
                        integrand.xref[j] = qf[iEG].xref[i][j]
                    end
                end
                eval_data!(integrand)
                for j = 1 : resultdim
                    integral4items[j,item] += integrand.val[j] * qf[iEG].w[i] * xItemVolumes[item];
                end
            end  
        end
    end
end

"""
$(TYPEDSIGNATURES)

Integration that returns total integral.
"""
function integrate(
    grid::ExtendableGrid,
    AT::Type{<:AssemblyType},
    integrand!::AbstractUserDataType,
    resultdim::Int;
    T = Float64,
    items = [],
    force_quadrature_rule = nothing)

    # quick and dirty : we mask the resulting array as an AbstractArray{T,2} using AccumulatingVector
    # and use the itemwise integration above
    AV = AccumulatingVector{T}(zeros(T,resultdim), 0)

    integrate!(AV, grid, AT, integrand!; items = items, force_quadrature_rule = force_quadrature_rule)

    if resultdim == 1
        return AV.entries[1]
    else
        return AV.entries
    end
end




"""
$(TYPEDSIGNATURES)

Integration for reference basis functions on reference domains (merely for testing stuff).

Note: area of reference geometry is not multiplied
"""
function ref_integrate!(
    integral::AbstractArray,
    EG::Type{<:AbstractElementGeometry},
    order::Int,
    integrand::Function # expected to be like a refbasis function with interface (result,xref)
    )
    
    grid = reference_domain(EG)
    qf = QuadratureRule{eltype(integral),EG}(order)
    result = copy(integral)

    for i in eachindex(qf.w)
        integrand(result, qf.xref[i])
        integral .+= result * qf.w[i];
    end  
end