module GradientRobustMultiPhysics

using Base: Bool
using ExtendableGrids # + some exports from there
export Edge1D, Triangle2D, Parallelogram2D, Tetrahedron3D, Parallelepiped3D
using GridVisualize
using ExtendableSparse
using SuiteSparse
using SparseArrays
using StaticArrays
using DiffResults
using CommonSolve
using LinearAlgebra
using LinearSolve
using ForwardDiff
using Symbolics
using SparseDiffTools
using DocStringExtensions
using Printf
using Logging

include("logging.jl")


include("userdata.jl")
export AbstractDataFunction, AbstractExtendedDataFunction
export UserData, DataFunction, DefaultUserData, eval_data!
export set_time!, is_timedependent, is_itemdependent, is_xrefdependent, is_xdependent
export ∇, div, curl, Δ, H, dt
export config_derivatives!, eval_derivatives!, eval_div, eval_Δ, eval_∇, eval_H, eval_dt, eval_curl

include("quadrature.jl")
export QuadratureRule
export VertexRule
export integrate!, integrate, ref_integrate!

include("functionoperators.jl")
export AbstractFunctionOperator
export Identity, IdentityComponent, IdentityDisc
export ReconstructionIdentity, ReconstructionIdentityDisc
export ReconstructionGradient, ReconstructionGradientDisc
export ReconstructionDivergence
export ReconstructionNormalFlux
export NormalFlux, NormalFluxDisc, TangentFlux, TangentFluxDisc
export Gradient, GradientDisc
export SymmetricGradient, TangentialGradient
export Divergence, ReconstructionDivergence
export CurlScalar, Curl2D, Curl3D
export Laplacian, Hessian, SymmetricHessian
export Trace, Deviator
export NeededDerivatives4Operator, QuadratureOrderShift4Operator
export Dofmap4AssemblyType, DofitemAT4Operator
export DefaultDirichletBoundaryOperator4FE

export DiscontinuityTreatment, Jump, Average, Parent
export OperatorPair, OperatorTriple


include("finiteelements.jl")
export DofMap, CellDofs, FaceDofs, EdgeDofs, BFaceDofs, BEdgeDofs
export DofMapTypes
export AbstractFiniteElement
export FESpace, FESpaces
export get_periodic_coupling_info

export AbstractH1FiniteElement
export H1BUBBLE, L2P0, H1P1, H1P2, H1P2B, H1MINI, H1CR, H1P3, H1Pk
export L2P1
export H1Q1, H1Q2

export AbstractH1FiniteElementWithCoefficients
export H1BR, H1P1TEB

export AbstractHdivFiniteElement
export HDIVRT0, HDIVBDM1, HDIVRT1, HDIVRT1INT, HDIVBDM2
export HDIVRTkENRICH

export AbstractHcurlFiniteElement
export HCURLN0

export get_assemblytype
export get_polynomialorder, get_ndofs, get_ndofs_all
export get_ncomponents, get_edim
export get_basis, get_coefficients, get_basissubset
export reconstruct!

export interpolate! # must be defined separately by each FEdefinition
export nodevalues, continuify
export nodevalues!
export nodevalues_view

export FEVectorBlock, FEVector
export dot, norm, norms
export FEMatrixBlock, FEMatrix, _addnz
export fill!, addblock!, addblock_matmul!, lrmatmul, add!, apply_penalties!

export get_reconstruction_matrix

export displace_mesh,displace_mesh!

include("reconstructions.jl")
export ReconstructionHandler, get_rcoefficients!


include("feevaluator.jl")
export FEEvaluator, update_basis!, eval_febe!


include("actions.jl")
export AbstractAction, Action, MultiplyScalarAction, NoAction, feval_action, fdot_action, fdotv_action, fdotn_action
export set_time!, update_action!, apply_action!
export DefaultUserAction


include("accumvector.jl")
export AccumulatingVector


include("assemblypatterns.jl")
export AssemblyPatternType, AssemblyPreparations
export ItemIntegrator, L2ErrorIntegrator, L2NormIntegrator, L2DifferenceIntegrator
export DiscreteLinearForm
export APT_BilinearForm, APT_SymmetricBilinearForm, APT_LumpedBilinearForm
export DiscreteBilinearForm, DiscreteSymmetricBilinearForm, DiscreteLumpedBilinearForm
export DiscreteNonlinearForm
export prepare_assembly!
export assemble!, evaluate!, evaluate
export AssemblyManager, update_assembly!
export SegmentIntegrator
export PointEvaluator


include("pdeoperators.jl")
export AbstractAssemblyTrigger
export AssemblyInitial, AssemblyEachTimeStep, AssemblyAlways, AssemblyNever
export AbstractPDEOperator

export BackwardEulerTimeDerivative

export BilinearForm
export StiffnessOperator, LaplaceOperator
export HookStiffnessOperator3D, HookStiffnessOperator2D, HookStiffnessOperator1D
export ReactionOperator
export ConvectionOperator, ConvectionRotationFormOperator
export LagrangeMultiplier

export LinearForm
export NonlinearForm

export FVConvectionDiffusionOperator
export DiagonalOperator, CopyOperator
export CustomMatrixOperator

export SchurComplement

export assemble_operator!, eval_assemble!


include("boundarydata.jl")
export BoundaryData
export AbstractBoundaryType, HomogeneousDirichletBoundary, InterpolateDirichletBoundary, BestapproxDirichletBoundary, CorrectDirichletBoundary
export boundarydata!


include("globalconstraints.jl")
export AbstractGlobalConstraint
export FixedIntegralMean
export CombineDofs
export FixedDofs
export apply_constraint!


include("pdedescription.jl")
export PDEDescription
export add_unknown!
export add_operator!, replace_operator!
export add_rhsdata!, replace_rhsdata!
export add_boundarydata!
export add_constraint!


include("solvers.jl")
export SolverConfig
export solve, solve!, assemble!, apply_boundarydata!
export show_statistics

include("solvers_timedependent.jl")
export AbstractTimeIntegrationRule
export BackwardEuler, CrankNicolson
export TimeControlSolver, advance!, advance_until_stationarity!, advance_until_time!

include("diffeq_interface.jl")
export eval_rhs!, eval_jacobian!, mass_matrix, jac_prototype

include("pdeprototypes.jl")
export IncompressibleNavierStokesProblem
export LinearElasticityProblem
export PoissonProblem
export L2BestapproximationProblem
export H1BestapproximationProblem

include("dataexport.jl")
export writeVTK!, writeCSV!
export print_table, print_convergencehistory

include("plots.jl")
export convergencehistory!, plot_convergencehistory

end #module