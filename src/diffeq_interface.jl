#
# Interface to DifferentialEquations.jl
# via TimeControlSolver struct

function diffeq_assembly!(sys::TimeControlSolver, ctime)

    sys.ctime = ctime
    # unpack
    SC =sys.SC
    PDE =sys.PDE
    A =sys.A 
    AM =sys.AM
    b =sys.b
    x =sys.x
    res =sys.res
    X =sys.X
    fixed_dofs = sys.fixed_dofs
    fixed_penalty = SC.user_params[:fixed_penalty]
    subiterations = SC.user_params[:subiterations]

    @debug "DiffEQ-interface: assembly at t = $ctime"

    nsubiterations = length(subiterations)
    for s = 1 : nsubiterations

        ## REASSEMBLE NONLINEAR AND TIME-DEPENDENT DATA
        lhs_erased, rhs_erased = assemble!(A[s],b[s],PDE,SC,X; equations = subiterations[s], min_trigger = AssemblyEachTimeStep, time = ctime)

        # ASSEMBLE TIME-DEPENDENT BOUNDARY DATA at current (already updated) time ctime
        # needs to be done after adding the time derivative, since it overwrittes Data from last timestep
        # if maxiterations > 1 (because X = LastIterate in this case)
        for k = 1 : length(subiterations[s])
            d = subiterations[s][k]
            if any(PDE.BoundaryOperators[d].timedependent) == true
                boundarydata!(X[d],PDE.BoundaryOperators[d]; time = ctime)
            else
                # nothing todo as all boundary data for block d is time-independent
            end
        end    

        # PENALIZE FIXED DOFS
        # (from boundary conditions and constraints)
        eqdof = 0
        eqoffsets =sys.eqoffsets
        for j = 1 : length(fixed_dofs)
            for eq = 1 : length(subiterations[s])
                if fixed_dofs[j] > eqoffsets[s][eq] && fixed_dofs[j] <= eqoffsets[s][eq]+X[subiterations[s][eq]].FES.ndofs
                    eqdof = fixed_dofs[j] - eqoffsets[s][eq]
                    b[s][eq][eqdof] = fixed_penalty * X.entries[fixed_dofs[j]]
                    A[s][eq,eq][eqdof,eqdof] = fixed_penalty

                    x[s].entries[fixed_dofs[j]] = X.entries[fixed_dofs[j]]
                end
            end
        end
        flush!(A[s].entries)

    end
end

"""
Assume the discrete problem is an ODE problem. Provide the 
rhs function for DifferentialEquations.jl.
"""
function eval_rhs!(du, x, sys::TimeControlSolver, ctime)
    # (re)assemble system
    @debug println("DiffEQ-interface: evaluating ODE rhs @time = $ctime")

    diffeq_assembly!(sys, ctime)

    sys.cstep += 1
    # evaluate residual
    SC = sys.SC
    PDE =sys.PDE
    A =sys.A 
    b =sys.b
    X =sys.X
    res = sys.res
    fixed_dofs = sys.fixed_dofs
    eqoffsets =sys.eqoffsets
    eqdof = 0
    subiterations = SC.user_params[:subiterations]

    for s = 1 : length(subiterations)
        # set Dirichlet data and other fixed dofs
        for j = 1 : length(fixed_dofs)
            for eq = 1 : length(subiterations[s])
                if fixed_dofs[j] > eqoffsets[s][eq] && fixed_dofs[j] <= eqoffsets[s][eq]+X[subiterations[s][eq]].FES.ndofs
                    eqdof = fixed_dofs[j] - eqoffsets[s][eq]
                    res[s][eq][eqdof] = 0
                    x[fixed_dofs[j]] = X[subiterations[s][eq]][eqdof]
                end
            end
        end

        # calculate residual
        @views res[s].entries .= A[s].entries*x - b[s].entries
    end

    ## set residual as rhs of ODE
    du .= -vec(sys.res[1].entries)
    nothing
end

"""
Assume the discrete problem is an ODE problem. Provide the 
jacobi matrix calculation function for DifferentialEquations.jl.
"""
function eval_jacobian!(J, u, sys::TimeControlSolver, ctime)
    # _eval_res_jac!(sys,u)
    @debug "DiffEQ-interface: eval_jacobian at t = $ctime"
    sys.X.entries .= u
    diffeq_assembly!(sys, ctime)
    J.=-sys.A[1].entries.cscmatrix
    nothing
end

"""
Get the mass matrix for use with DifferentialEquations.jl.
"""
function mass_matrix(sys::TimeControlSolver)
    @debug "DiffEQ-interface: mass_matrix"
    flush!(sys.AM[1].entries)
    return sys.AM[1].entries.cscmatrix
end

"""
Provide the system matrix as prototype for the Jacobian.
"""
function jac_prototype(sys::TimeControlSolver)
    @debug "DiffEQ-interface: jac_prototype"
    ExtendableSparse.flush!(sys.A[1].entries)
    sys.A[1].entries.cscmatrix
end