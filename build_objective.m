function [f, ub, H_dem] = build_objective(params, idx, nVars, T, price, H_dem, ub)
% BUILD_OBJECTIVE  Construct the objective function vector f for min f'*x.
%
% Also handles P_DC=0 thermal disable (modifies ub and H_dem).
%
% Objective components:
%   1. BESS annualized investment + O&M
%   2. BTES annualized investment + O&M
%   3. HP annualized investment + O&M (FIX #3)
%   4. Grid purchase cost (daily × 365)
%   5. Curtailment penalty (daily × 365)
%   6. Unmet heat penalty (daily × 365)

f = zeros(nVars, 1);
dt = params.dt;

%% BESS Investment + O&M (annualized)
% CRF_B * C_EB[$/kWh] * 1000[kWh/MWh] * E_B[MWh] + C_om_B * 1000 * E_B
f(idx.y_B) = (params.CRF_B * params.C_EB * 1000 + params.C_om_B * 1000) ...
             .* params.EB_cand(:);

%% BTES Investment + O&M (annualized)
f(idx.y_TES) = (params.CRF_TES * params.C_ETES * 1000 + params.C_om_TES * 1000) ...
               .* params.ETES_cand(:);

%% HP Investment + O&M (annualized) — FIX #3
% f coefficient for Q_HP_cap [MWth]:
%   CRF_HP * C_HP_cap[$/kWth] * 1000[kW/MW] + C_om_HP[$/kWth/yr] * 1000
f(idx.Q_HP_cap) = params.CRF_HP * params.C_HP_cap * 1000 + params.C_om_HP * 1000;

%% Operational Costs (daily → annualized)
for t = 1:T
    f(idx.P_buy(t))   = 365 * price(t) * dt;          % grid purchase
    f(idx.P_curt(t))  = 365 * params.pen_curt * dt;   % curtailment penalty
    f(idx.H_unmet(t)) = 365 * params.pen_unmet * dt;  % unmet heat penalty
end

%% Thermal Subsystem Disable (P_DC = 0)
if params.P_DC == 0
    H_dem = zeros(T, 1);
    ub(idx.H_HP)      = 0;
    ub(idx.P_HP)      = 0;
    ub(idx.H_WH)      = 0;
    ub(idx.H_ch_TES)  = 0;
    ub(idx.H_dis_TES) = 0;
    ub(idx.H_unmet)   = 0;
    ub(idx.Q_HP_cap)  = 0;
    fprintf('  NOTE: P_DC=0 → Thermal subsystem disabled.\n');
end

end
