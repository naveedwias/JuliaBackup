#= 

# 201 : Poisson-Problem 2D
([source code](SOURCE_URL))

This example computes the solution ``u`` of the Poisson problem
```math
\begin{aligned}
-\Delta u & = f \quad \text{in } \Omega
\end{aligned}
```
with some right-hand side ``f`` on the unit square domain ``\Omega`` on a given grid.

=#

module Example201_PoissonProblem2D

using GradientRobustMultiPhysics
using ExtendableGrids
using GridVisualize

## right-hand side function
const f = DataFunction([1]; name = "f")

## everything is wrapped in a main function
function main(; verbosity = 0, μ = 1, order = 2, nrefinements = 5, Plotter = nothing)

    ## set log level
    set_verbosity(verbosity)

    ## build/load any grid (here: a uniform-refined 2D unit square into triangles)
    xgrid = uniform_refine(grid_unitsquare(Triangle2D), nrefinements)

    ## create empty PDE description
    Problem = PDEDescription("Poisson problem")

    ## add unknown(s) (here: "u" that gets id 1 for later reference)
    add_unknown!(Problem; unknown_name = "u", equation_name = "Poisson equation")

    ## add left-hand side PDEoperator(s) (here: only Laplacian)
    add_operator!(Problem, [1,1], LaplaceOperator(μ))

    ## add right-hand side data (here: f = [1] in region(s) [1])
    add_rhsdata!(Problem, 1, LinearForm(Identity, f; regions = [1]))

    ## add boundary data (here: zero data for boundary regions 1:4)
    add_boundarydata!(Problem, 1, [1,2,3,4], HomogeneousDirichletBoundary)

    ## choose FESpace to discretise
    FEType = H1Pk{1,2,order}
    FES = FESpace{FEType}(xgrid)
    
    ## solve
    Solution = solve(Problem, FES; show_statistics = true)

    ## plot solution (for e.g. Plotter = PyPlot)
    p = GridVisualizer(; Plotter = Plotter, layout = (1,2), clear = true, resolution = (1000,500))
    scalarplot!(p[1,1], xgrid, view(nodevalues(Solution[1]),1,:), levels = 7, title = "u_h")
    scalarplot!(p[1,2], xgrid, view(nodevalues(Solution[1], Gradient; abs = true),1,:), vscale = 0.8, levels = 0, colorbarticks = 9, title = "∇u_h (abs + quiver)")
    vectorplot!(p[1,2], xgrid, evaluate(PointEvaluator(Solution[1], Gradient)), spacing = 0.1, clear = false)
end

end