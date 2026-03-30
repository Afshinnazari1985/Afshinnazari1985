%% main_MILP.m — Driver Script
% MILP Sizing of BESS & BTES — Narvik AI Data Center System
% Modular version with all fixes applied:
%   Fix 1: Asymmetric BTES efficiency (RTE ≈ 40%)
%   Fix 2: Sildvik removed (local grid only: 39.9 MW hydro)
%   Fix 3: Heat pump investment cost included
%
% Functions:
%   setup_parameters()              → params struct
%   load_Narvik_data()              → P_wind, P_hydro, P_load, H_dem, price, T
%   build_variables(params, T)      → idx, nVars, intcon, lb, ub
%   build_objective(params, idx, nVars, T, price, H_dem) → f
%   build_eq_constraints(params, idx, nVars, T, P_wind, P_hydro, P_load, H_dem) → Aeq, beq
%   build_ineq_constraints(params, idx, nVars, T) → A, b
%   extract_results(x_opt, fval, params, idx, T, P_wind, P_hydro, P_load, H_dem, price) → res
%   plot_results(res, params, T)

clc; clear; close all;

% Ensure paths are set relative to project root
projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(projectRoot, 'src'));
cd(projectRoot);

fprintf('==============================================================\n');
fprintf('  MILP Sizing of BESS & BTES — Narvik AI Data Center System\n');
fprintf('==============================================================\n\n');

%% 1. Setup
params = setup_parameters();

%% 2. Load Data
[P_wind, P_hydro, P_load, H_dem, price, T] = load_Narvik_data();

fprintf('Data profiles loaded: T = %d hours\n', T);
fprintf('  Wind:  %.1f - %.1f MW\n', min(P_wind), max(P_wind));
fprintf('  Hydro: %.1f - %.1f MW\n', min(P_hydro), max(P_hydro));
fprintf('  Load:  %.1f - %.1f MW (excl. DC)\n', min(P_load), max(P_load));
fprintf('  Heat:  %.1f - %.1f MWth\n', min(H_dem), max(H_dem));
fprintf('  Price: %.0f - %.0f $/MWh\n\n', min(price), max(price));

%% 3. Plot Input Profiles
plot_input_profiles(P_wind, P_hydro, P_load, H_dem, price, T, params.P_DC);

%% 4. Build Variables
[idx, nVars, intcon, lb, ub] = build_variables(params, T);

%% 5. Build Objective
[f, ub, H_dem] = build_objective(params, idx, nVars, T, price, H_dem, ub);

%% 6. Build Constraints
[Aeq, beq] = build_eq_constraints(params, idx, nVars, T, P_wind, P_hydro, P_load, H_dem);
[A, b]     = build_ineq_constraints(params, idx, nVars, T);

fprintf('Total variables: %d | Eq: %d | Ineq: %d\n\n', nVars, size(Aeq,1), size(A,1));

%% 7. Solve
fprintf('Solving MILP with intlinprog...\n');
fprintf('--------------------------------------------------------------\n');

options = optimoptions('intlinprog', ...
    'Display',              'iter', ...
    'MaxTime',              600, ...
    'RelativeGapTolerance', 0.01, ...
    'IntegerPreprocess',    'advanced');

[x_opt, fval, exitflag, output] = intlinprog(f, intcon, A, b, Aeq, beq, lb, ub, options);

fprintf('\n--------------------------------------------------------------\n');
if exitflag == 1
    fprintf('Optimal solution found.\n');
elseif exitflag == 2
    fprintf('Feasible solution found (gap tolerance met).\n');
else
    fprintf('WARNING: Solver exit flag = %d\n', exitflag);
    fprintf('  %s\n', output.message);
end

%% 8. Extract & Display Results
if exitflag >= 1
    res = extract_results(x_opt, fval, params, idx, T, ...
                          P_wind, P_hydro, P_load, H_dem, price);

    %% 9. Plot Results
    plot_results(res, params, T);
else
    fprintf('\nOptimization failed. Check constraints and data.\n');
end
