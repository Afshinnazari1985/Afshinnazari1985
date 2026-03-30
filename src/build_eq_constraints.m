function [Aeq, beq] = build_eq_constraints(params, idx, nVars, T, P_wind, P_hydro, P_load, H_dem)
% BUILD_EQ_CONSTRAINTS  Build equality constraint matrices Aeq*x = beq.
%
% Constraints:
%   (a) Select exactly one BESS candidate
%   (b) Select exactly one BTES candidate
%   (c) BESS SOC dynamics
%   (d) BESS initial SOC
%   (e) BTES SOC dynamics — FIX #1: asymmetric efficiencies
%   (f) BTES initial SOC
%   (g) Heat pump coupling: H_HP = COP × P_HP
%   (h) Electrical power balance
%   (i) Thermal (heat) balance

dt = params.dt;
nEq = 0;
Aeq_rows = {};
beq_vals = [];

%% (a) Select exactly one BESS candidate: sum(y_B) = 1
row = zeros(1, nVars);
row(idx.y_B) = 1;
nEq = nEq + 1;
Aeq_rows{nEq} = row;
beq_vals(nEq) = 1;

%% (b) Select exactly one BTES candidate: sum(y_TES) = 1
row = zeros(1, nVars);
row(idx.y_TES) = 1;
nEq = nEq + 1;
Aeq_rows{nEq} = row;
beq_vals(nEq) = 1;

%% (c) BESS SOC dynamics
% W_B(t+1) = W_B(t) + eta_B * P_ch(t) * dt - (1/eta_B) * P_dis(t) * dt
for t = 1:T-1
    row = zeros(1, nVars);
    row(idx.W_B(t+1))  =  1;
    row(idx.W_B(t))     = -1;
    row(idx.P_ch_B(t))  = -params.eta_B * dt;
    row(idx.P_dis_B(t)) =  (1/params.eta_B) * dt;
    nEq = nEq + 1;
    Aeq_rows{nEq} = row;
    beq_vals(nEq) = 0;
end

%% (d) BESS initial SOC: W_B(1) = SOC_init * E_B
row = zeros(1, nVars);
row(idx.W_B(1)) = 1;
row(idx.y_B)    = -params.SOC_B_init * params.EB_cand;
nEq = nEq + 1;
Aeq_rows{nEq} = row;
beq_vals(nEq) = 0;

%% (e) BTES SOC dynamics — FIX #1: asymmetric efficiencies
% W_TES(t+1) = W_TES(t) + eta_ch_TES * H_ch(t) * dt - (1/eta_dis_TES) * H_dis(t) * dt
for t = 1:T-1
    row = zeros(1, nVars);
    row(idx.W_TES(t+1))   =  1;
    row(idx.W_TES(t))      = -1;
    row(idx.H_ch_TES(t))   = -params.eta_ch_TES * dt;       % was: -eta_TES
    row(idx.H_dis_TES(t))  =  (1/params.eta_dis_TES) * dt;  % was: (1/eta_TES)
    nEq = nEq + 1;
    Aeq_rows{nEq} = row;
    beq_vals(nEq) = 0;
end

%% (f) BTES initial SOC: W_TES(1) = SOC_TES_init * E_TES
row = zeros(1, nVars);
row(idx.W_TES(1)) = 1;
row(idx.y_TES)    = -params.SOC_TES_init * params.ETES_cand;
nEq = nEq + 1;
Aeq_rows{nEq} = row;
beq_vals(nEq) = 0;

%% (g) Heat pump coupling: COP * P_HP(t) - H_HP(t) = 0
for t = 1:T
    row = zeros(1, nVars);
    row(idx.P_HP(t)) = params.COP_HP;
    row(idx.H_HP(t)) = -1;
    nEq = nEq + 1;
    Aeq_rows{nEq} = row;
    beq_vals(nEq) = 0;
end

%% (h) Electrical power balance
% P_wind + P_hydro + P_dis_B + P_buy = P_load + P_DC + P_HP + P_ch_B + P_curt
for t = 1:T
    row = zeros(1, nVars);
    row(idx.P_dis_B(t)) =  1;
    row(idx.P_buy(t))   =  1;
    row(idx.P_HP(t))    = -1;
    row(idx.P_ch_B(t))  = -1;
    row(idx.P_curt(t))  = -1;
    nEq = nEq + 1;
    Aeq_rows{nEq} = row;
    beq_vals(nEq) = P_load(t) + params.P_DC - P_wind(t) - P_hydro(t);
end

%% (i) Thermal (heat) balance
% H_HP + H_WH + H_dis_TES - H_ch_TES + H_unmet = H_dem
for t = 1:T
    row = zeros(1, nVars);
    row(idx.H_HP(t))      =  1;
    row(idx.H_WH(t))      =  1;
    row(idx.H_dis_TES(t)) =  1;
    row(idx.H_ch_TES(t))  = -1;
    row(idx.H_unmet(t))   =  1;
    nEq = nEq + 1;
    Aeq_rows{nEq} = row;
    beq_vals(nEq) = H_dem(t);
end

%% Assemble
Aeq = zeros(nEq, nVars);
for k = 1:nEq
    Aeq(k,:) = Aeq_rows{k};
end
beq = beq_vals(:);

fprintf('Equality constraints: %d\n', nEq);

end
