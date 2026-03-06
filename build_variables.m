function [idx, nVars, intcon, lb, ub] = build_variables(params, T)
% BUILD_VARIABLES  Create decision variable indexing, integer declarations, and bounds.
%
% Inputs:
%   params — parameter struct from setup_parameters()
%   T      — number of time steps
%
% Returns:
%   idx    — struct with index ranges for each variable group
%   nVars  — total number of decision variables
%   intcon — indices of integer (binary) variables
%   lb, ub — lower and upper bound vectors

nCandB   = params.nCandB;
nCandTES = params.nCandTES;

%% Variable Indexing
idx = struct();
n = 0;

idx.y_B       = n+1 : n+nCandB;       n = n + nCandB;      % BESS candidate selection
idx.y_TES     = n+1 : n+nCandTES;     n = n + nCandTES;    % BTES candidate selection
idx.P_B_max   = n+1;                   n = n + 1;           % BESS power rating [MW]
idx.H_TES_max = n+1;                   n = n + 1;           % BTES power rating [MWth]
idx.Q_HP_cap  = n+1;                   n = n + 1;           % HP thermal capacity [MWth] — FIX #3
idx.P_ch_B    = n+1 : n+T;            n = n + T;           % BESS charge power
idx.P_dis_B   = n+1 : n+T;            n = n + T;           % BESS discharge power
idx.W_B       = n+1 : n+T;            n = n + T;           % BESS stored energy
idx.z_ch_B    = n+1 : n+T;            n = n + T;           % BESS charge binary
idx.z_dis_B   = n+1 : n+T;            n = n + T;           % BESS discharge binary
idx.H_ch_TES  = n+1 : n+T;            n = n + T;           % BTES charge power
idx.H_dis_TES = n+1 : n+T;            n = n + T;           % BTES discharge power
idx.W_TES     = n+1 : n+T;            n = n + T;           % BTES stored energy
idx.z_ch_TES  = n+1 : n+T;            n = n + T;           % BTES charge binary
idx.z_dis_TES = n+1 : n+T;            n = n + T;           % BTES discharge binary
idx.H_HP      = n+1 : n+T;            n = n + T;           % HP heat output
idx.P_HP      = n+1 : n+T;            n = n + T;           % HP electricity consumption
idx.H_WH      = n+1 : n+T;            n = n + T;           % waste heat utilized
idx.P_buy     = n+1 : n+T;            n = n + T;           % grid purchase
idx.P_curt    = n+1 : n+T;            n = n + T;           % curtailment
idx.H_unmet   = n+1 : n+T;            n = n + T;           % unmet heat

nVars = n;

fprintf('Total decision variables: %d\n', nVars);
fprintf('  (Binary: %d, Continuous: %d)\n', ...
    nCandB + nCandTES + 4*T, nVars - nCandB - nCandTES - 4*T);

%% Integer Variable Indices (binary)
intcon = [idx.y_B, idx.y_TES, ...
          idx.z_ch_B, idx.z_dis_B, ...
          idx.z_ch_TES, idx.z_dis_TES];

%% Bounds
lb = zeros(nVars, 1);
ub = inf(nVars, 1);

% --- Binary [0,1] ---
ub(idx.y_B)       = 1;
ub(idx.y_TES)     = 1;
ub(idx.z_ch_B)    = 1;
ub(idx.z_dis_B)   = 1;
ub(idx.z_ch_TES)  = 1;
ub(idx.z_dis_TES) = 1;

% --- Tight physical bounds ---
EB_max   = max(params.EB_cand);
ETES_max = max(params.ETES_cand);

ub(idx.P_B_max)   = params.gamma_B   * EB_max;        % C-rate × largest candidate
ub(idx.H_TES_max) = params.gamma_TES * ETES_max;      % C-rate × largest candidate
ub(idx.Q_HP_cap)  = max(20) + params.gamma_TES * ETES_max;  % max H_dem + max BTES charge

% BESS operational
ub(idx.P_ch_B)    = params.gamma_B * EB_max;           % tight: limited by C-rate
ub(idx.P_dis_B)   = params.gamma_B * EB_max;
ub(idx.W_B)       = params.SOC_B_max * EB_max;

% BTES operational
ub(idx.H_ch_TES)  = params.gamma_TES * ETES_max;
ub(idx.H_dis_TES) = params.gamma_TES * ETES_max;
ub(idx.W_TES)     = params.SOC_TES_max * ETES_max;

% Heat pump — bounded by max possible heat output
max_HP_heat = 20 + params.gamma_TES * ETES_max;  % H_dem_peak + max BTES charge
ub(idx.H_HP)  = max_HP_heat;
ub(idx.P_HP)  = max_HP_heat / params.COP_HP;

% Waste heat — hard physical limit
ub(idx.H_WH) = params.H_WH_avail;

% Grid purchase — max possible deficit
ub(idx.P_buy) = 44 + params.P_DC + params.gamma_B*EB_max + max_HP_heat/params.COP_HP;

% Curtailment — max possible surplus
ub(idx.P_curt) = 10.5 + 35.9 + params.gamma_B*EB_max;  % max_wind + max_hydro + BESS

% Unmet heat — can exceed H_dem if BTES is simultaneously charging
ub(idx.H_unmet) = 20 + params.gamma_TES * ETES_max;

end
