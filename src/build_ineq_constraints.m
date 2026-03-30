function [A, b] = build_ineq_constraints(params, idx, nVars, T)
% BUILD_INEQ_CONSTRAINTS  Build inequality constraint matrices A*x <= b.
%
% Constraints:
%   BESS: (1) C-rate, (2-3) charge/discharge ≤ P_B_max, (4-5) binary linking,
%         (6) no simultaneous, (7-8) SOC bounds, (9-10) cyclic SOC
%   BTES: lock-out if P_DC=0, (11) C-rate, (12-13) charge/discharge ≤ H_TES_max,
%         (14-15) binary linking, (16) no simultaneous, (17-18) SOC bounds, (19) cyclic SOC
%   (20) Waste heat bound
%   (21) HP capacity constraint — FIX #3

EB_cand   = params.EB_cand;
ETES_cand = params.ETES_cand;

% Pre-allocate
maxIneq = 2 + 12*T + 12*T + 10 + 24;
A_rows  = zeros(maxIneq, nVars);
b_vals  = zeros(maxIneq, 1);
nIneq   = 0;

% ========== BESS CONSTRAINTS ==========

% (1) C-rate: P_B_max - gamma_B * E_B <= 0
nIneq = nIneq + 1;
A_rows(nIneq, idx.P_B_max) = 1;
A_rows(nIneq, idx.y_B)     = -params.gamma_B * EB_cand;
b_vals(nIneq) = 0;

% (2) Charge power ≤ P_B_max
for t = 1:T
    nIneq = nIneq + 1;
    A_rows(nIneq, idx.P_ch_B(t)) = 1;
    A_rows(nIneq, idx.P_B_max)   = -1;
    b_vals(nIneq) = 0;
end

% (3) Discharge power ≤ P_B_max
for t = 1:T
    nIneq = nIneq + 1;
    A_rows(nIneq, idx.P_dis_B(t)) = 1;
    A_rows(nIneq, idx.P_B_max)    = -1;
    b_vals(nIneq) = 0;
end

% (4) Charge ≤ BigM × z_ch_B (binary linking)
BigM_BESS = params.gamma_B * max(EB_cand);  % tight BigM
for t = 1:T
    nIneq = nIneq + 1;
    A_rows(nIneq, idx.P_ch_B(t)) = 1;
    A_rows(nIneq, idx.z_ch_B(t)) = -BigM_BESS;
    b_vals(nIneq) = 0;
end

% (5) Discharge ≤ BigM × z_dis_B
for t = 1:T
    nIneq = nIneq + 1;
    A_rows(nIneq, idx.P_dis_B(t)) = 1;
    A_rows(nIneq, idx.z_dis_B(t)) = -BigM_BESS;
    b_vals(nIneq) = 0;
end

% (6) No simultaneous charge/discharge: z_ch + z_dis ≤ 1
for t = 1:T
    nIneq = nIneq + 1;
    A_rows(nIneq, idx.z_ch_B(t))  = 1;
    A_rows(nIneq, idx.z_dis_B(t)) = 1;
    b_vals(nIneq) = 1;
end

% (7) SOC lower: SOC_min * E_B - W_B(t) ≤ 0
for t = 1:T
    nIneq = nIneq + 1;
    A_rows(nIneq, idx.y_B)    = params.SOC_B_min * EB_cand;
    A_rows(nIneq, idx.W_B(t)) = -1;
    b_vals(nIneq) = 0;
end

% (8) SOC upper: W_B(t) - SOC_max * E_B ≤ 0
for t = 1:T
    nIneq = nIneq + 1;
    A_rows(nIneq, idx.W_B(t)) = 1;
    A_rows(nIneq, idx.y_B)    = -params.SOC_B_max * EB_cand;
    b_vals(nIneq) = 0;
end

% (9) Cyclic SOC lower: (SOC_init - tol) * E_B - W_B(T) ≤ 0
nIneq = nIneq + 1;
A_rows(nIneq, idx.y_B)    = (params.SOC_B_init - params.SOC_tol) * EB_cand;
A_rows(nIneq, idx.W_B(T)) = -1;
b_vals(nIneq) = 0;

% (10) Cyclic SOC upper: W_B(T) - (SOC_init + tol) * E_B ≤ 0
nIneq = nIneq + 1;
A_rows(nIneq, idx.W_B(T)) = 1;
A_rows(nIneq, idx.y_B)    = -(params.SOC_B_init + params.SOC_tol) * EB_cand;
b_vals(nIneq) = 0;

% ========== BTES CONSTRAINTS ==========

% BTES requires Data Center — lock out non-zero candidates if P_DC = 0
if params.P_DC == 0
    for s = 2:params.nCandTES
        nIneq = nIneq + 1;
        A_rows(nIneq, idx.y_TES(s)) = 1;
        b_vals(nIneq) = 0;
    end
    fprintf('  NOTE: P_DC=0 → BTES forced to zero.\n');
end

% (11) C-rate: H_TES_max - gamma_TES * E_TES ≤ 0
nIneq = nIneq + 1;
A_rows(nIneq, idx.H_TES_max) = 1;
A_rows(nIneq, idx.y_TES)     = -params.gamma_TES * ETES_cand;
b_vals(nIneq) = 0;

% (12) BTES charge ≤ H_TES_max
for t = 1:T
    nIneq = nIneq + 1;
    A_rows(nIneq, idx.H_ch_TES(t)) = 1;
    A_rows(nIneq, idx.H_TES_max)   = -1;
    b_vals(nIneq) = 0;
end

% (13) BTES discharge ≤ H_TES_max
for t = 1:T
    nIneq = nIneq + 1;
    A_rows(nIneq, idx.H_dis_TES(t)) = 1;
    A_rows(nIneq, idx.H_TES_max)    = -1;
    b_vals(nIneq) = 0;
end

% (14) BTES charge ≤ BigM × z_ch_TES
BigM_BTES = params.gamma_TES * max(ETES_cand);
for t = 1:T
    nIneq = nIneq + 1;
    A_rows(nIneq, idx.H_ch_TES(t)) = 1;
    A_rows(nIneq, idx.z_ch_TES(t)) = -BigM_BTES;
    b_vals(nIneq) = 0;
end

% (15) BTES discharge ≤ BigM × z_dis_TES
for t = 1:T
    nIneq = nIneq + 1;
    A_rows(nIneq, idx.H_dis_TES(t)) = 1;
    A_rows(nIneq, idx.z_dis_TES(t)) = -BigM_BTES;
    b_vals(nIneq) = 0;
end

% (16) No simultaneous: z_ch_TES + z_dis_TES ≤ 1
for t = 1:T
    nIneq = nIneq + 1;
    A_rows(nIneq, idx.z_ch_TES(t))  = 1;
    A_rows(nIneq, idx.z_dis_TES(t)) = 1;
    b_vals(nIneq) = 1;
end

% (17) SOC lower: SOC_TES_min * E_TES - W_TES(t) ≤ 0
for t = 1:T
    nIneq = nIneq + 1;
    A_rows(nIneq, idx.y_TES)    = params.SOC_TES_min * ETES_cand;
    A_rows(nIneq, idx.W_TES(t)) = -1;
    b_vals(nIneq) = 0;
end

% (18) SOC upper: W_TES(t) - SOC_TES_max * E_TES ≤ 0
for t = 1:T
    nIneq = nIneq + 1;
    A_rows(nIneq, idx.W_TES(t)) = 1;
    A_rows(nIneq, idx.y_TES)    = -params.SOC_TES_max * ETES_cand;
    b_vals(nIneq) = 0;
end

% (19) Cyclic SOC (relaxed)
nIneq = nIneq + 1;
A_rows(nIneq, idx.y_TES)    = (params.SOC_TES_init - params.SOC_tol) * ETES_cand;
A_rows(nIneq, idx.W_TES(T)) = -1;
b_vals(nIneq) = 0;

nIneq = nIneq + 1;
A_rows(nIneq, idx.W_TES(T)) = 1;
A_rows(nIneq, idx.y_TES)    = -(params.SOC_TES_init + params.SOC_tol) * ETES_cand;
b_vals(nIneq) = 0;

% ========== WASTE HEAT CONSTRAINTS ==========

% (20) H_WH(t) ≤ H_WH_avail
for t = 1:T
    nIneq = nIneq + 1;
    A_rows(nIneq, idx.H_WH(t)) = 1;
    b_vals(nIneq) = params.H_WH_avail;
end

% ========== HEAT PUMP CAPACITY CONSTRAINT — FIX #3 ==========

% (21) H_HP(t) ≤ Q_HP_cap  ∀t
for t = 1:T
    nIneq = nIneq + 1;
    A_rows(nIneq, idx.H_HP(t))   =  1;
    A_rows(nIneq, idx.Q_HP_cap)  = -1;
    b_vals(nIneq) = 0;
end

% ========== Trim ==========
A = A_rows(1:nIneq, :);
b = b_vals(1:nIneq);

fprintf('Inequality constraints: %d\n', nIneq);

end
