%% ========================================================================
%  MILP Optimal Sizing & EMS of BESS and BTES
%  -------------------------------------------------------------------------
%  System : Modified IEEE 14-bus, Narvik Arctic grid
%  RES    : Hakvik Hydro (9.9 MW), Batsvatn Hydro (30 MW),
%           Sildvik Hydro (63 MW), Nygardsfjellet Wind (32.2 MW)
%  Load   : AI Data Center (variable MW) with waste heat recovery
%  Storage: BESS (electrical) + BTES (thermal)
%  -------------------------------------------------------------------------
%  Solver : intlinprog (MATLAB Optimization Toolbox)
%  Method : Discrete candidate sizes → eliminates bilinear SOC*E terms
%           Absolute stored energy W(t) [MWh] instead of fractional SOC
%  -------------------------------------------------------------------------
%  Author : Afshin Nazari  |  UiT The Arctic University of Norway
%  Date   : February 2026
%% ========================================================================
clc; clear; close all;
fprintf('==============================================================\n');
fprintf('  MILP Sizing of BESS & BTES — Narvik AI Data Center System\n');
fprintf('==============================================================\n\n');

%% ====================== 1. PARAMETERS ==================================
T  = 24;        % number of time periods (hours)
% T = 8760;
dt = 1;         % time step [h]

% --- BESS Parameters ---
eta_B       = 0.95;     % one-way efficiency (charge & discharge)
SOC_B_min   = 0.20;     % minimum SOC [frac]
SOC_B_max   = 0.80;     % maximum SOC [frac]
SOC_B_init  = 0.50;     % initial SOC [frac]
gamma_B     = 0.50;     % C-rate [1/h]
C_EB        = 285;      % investment cost [$/kWh]  https://www.tesla.com/megapack/design
Life_B      = 15;       % lifetime [years]  https://www.tesla.com/megapack/design
C_om_B      = 2.5;      % O&M cost [$/kWh/yr]
SOC_tol     = 0.15;     % cyclic SOC tolerance (relaxed)

% --- BTES Parameters ---
% eta_TES = 0.40 models early-stage BTES performance: the surrounding
% ground material has not yet reached thermal equilibrium, leading to
% elevated heat losses. Round-trip efficiency = 0.40^2 = 16%.
% This is conservative; long-term performance recovers toward ~0.80-0.85
% as the borehole field reaches steady thermal state.
% Source: HT-BTES factsheet (topsectorenergie.nl), Arctic ground conditions
eta_TES     = 0.40;     % one-way efficiency (early-stage, low ground saturation)
SOC_TES_min = 0.10;     % minimum SOC [frac]
SOC_TES_max = 0.90;     % maximum SOC [frac]
SOC_TES_init= 0.50;     % initial SOC [frac]
gamma_TES   = 0.20;     % C-rate [1/h]
C_ETES      = 0.60;     % investment cost [$/kWhth]  (HT-BTES: 0.6-3 EUR/kWh)
Life_TES    = 30;       % lifetime [years]
C_om_TES    = 0.048;    % O&M cost [$/kWhth/yr]  (2-8% of investment)

% --- AI Data Center ---
% Sensitivity sweep: test P_DC = 10, 15, 20, 25, 30 MW
% NOTE: H_WH_avail = beta_WH * P_DC.
%   For P_DC >= 29 MW: H_WH_avail >= 20.3 MWth > peak H_dem → BTES thermally redundant.
%   For P_DC <= 20 MW: H_WH_avail < peak H_dem → BTES has thermal value.
P_DC        = 20;
beta_WH     = 0.70;             % waste heat recovery coefficient
H_WH_avail  = beta_WH * P_DC;  % constant available waste heat [MWth]

% --- Heat Pump ---
COP_HP      = 3;        % coefficient of performance (Arctic avg)

% --- Economic Parameters ---
disc_rate   = 0.06;     % discount rate
pen_curt    = 50;       % curtailment penalty [$/MWh]
pen_unmet   = 2000;     % unmet heat penalty [$/MWhth]

% --- Capital Recovery Factors ---
CRF_B   = disc_rate*(1+disc_rate)^Life_B   / ((1+disc_rate)^Life_B   - 1);
CRF_TES = disc_rate*(1+disc_rate)^Life_TES / ((1+disc_rate)^Life_TES - 1);
fprintf('CRF_BESS  = %.4f\n', CRF_B);
fprintf('CRF_BTES  = %.4f\n\n', CRF_TES);

%% =========== 2. DISCRETE CANDIDATE SIZES ================================
% BESS: Tesla Megapack units (3.9 MWh each), 0 = not installed
EB_cand   = [0, 3.9, 7.8, 11.7, 15.6, 19.5, 23.4, 27.3];  % [MWh]

% BTES candidates — justified by daily heat shortfall analysis:
%   At P_DC = 20 MW: H_WH = 14 MWth, avg(H_dem) ≈ 17.4 MWth
%   Daily shortfall ≈ (17.4 - 14.0) × 24 ≈ 82 MWhth/day
%   With eta_TES = 0.40 (early-stage), usable daily charge ≈ 33 MWhth/day
%   Candidates span from sub-daily buffer to seasonal Arctic reserve:
%     0    : No BTES (baseline)
%     50   : ~0.6-day buffer (smallest viable borehole field)
%     150  : ~2-day buffer
%     300  : ~4-day buffer / practical seasonal pre-heating minimum
%     500  : ~1-week buffer
%     800  : ~5-week Arctic winter supplement
%     1200 : ~2-month seasonal storage
%     1800 : ~3-month full Arctic winter storage
ETES_cand = [0, 50, 150, 300, 500, 800, 1200, 1800];  % [MWhth]

nCandB   = length(EB_cand);
nCandTES = length(ETES_cand);

%% ================== 3. DATA PROFILES ====================================
[P_wind, P_hydro, P_load, H_dem, price, T] = load_Narvik_data();
fprintf('Data profiles loaded: T = %d hours\n', T);
fprintf('  Wind:  %.1f - %.1f MW\n', min(P_wind), max(P_wind));
fprintf('  Hydro: %.1f - %.1f MW\n', min(P_hydro), max(P_hydro));
fprintf('  Load:  %.1f - %.1f MW (excl. DC)\n', min(P_load), max(P_load));
fprintf('  Heat:  %.1f - %.1f MWth\n', min(H_dem), max(H_dem));
fprintf('  Price: %.0f - %.0f $/MWh\n\n', min(price), max(price));

% Warn if waste heat exceeds peak demand (BTES becomes thermally redundant)
if H_WH_avail >= max(H_dem)
    fprintf(['  [WARNING] H_WH_avail (%.1f MWth) >= max(H_dem) (%.1f MWth).\n' ...
             '  Waste heat alone covers all heating. BTES will likely be\n' ...
             '  selected as 0 MWhth. Reduce P_DC for meaningful BTES sizing.\n\n'], ...
        H_WH_avail, max(H_dem));
end

%% ================== 3b. PLOT INPUT DATA PROFILES ========================
hours = 1:T;
figure('Name','Input Data Profiles','Position',[50 100 1000 700]);
subplot(3,2,1);
plot(hours, P_wind,  'b-o', 'LineWidth', 1.5, 'MarkerSize', 4);
xlabel('Hour'); ylabel('MW');
title('Wind Generation (Nygårdsfjellet)'); grid on; xlim([1 T]);

subplot(3,2,2);
plot(hours, P_hydro, 'g-s', 'LineWidth', 1.5, 'MarkerSize', 4);
xlabel('Hour'); ylabel('MW');
title('Hydro Generation (Håkvik+Båtsvatn+Sildvik)'); grid on; xlim([1 T]);

subplot(3,2,3);
plot(hours, P_load,  'k-^', 'LineWidth', 1.5, 'MarkerSize', 4);
xlabel('Hour'); ylabel('MW');
title('Electrical Load (excl. Data Center)'); grid on; xlim([1 T]);

subplot(3,2,4);
plot(hours, H_dem,   'r-d', 'LineWidth', 1.5, 'MarkerSize', 4);
xlabel('Hour'); ylabel('MWth');
title('District Heating Demand'); grid on; xlim([1 T]);

subplot(3,2,5);
plot(hours, price,   'm-v', 'LineWidth', 1.5, 'MarkerSize', 4);
xlabel('Hour'); ylabel('$/MWh');
title('Electricity Price (NO4)'); grid on; xlim([1 T]);

subplot(3,2,6);
bar(hours, [P_wind, P_hydro], 'stacked'); hold on;
plot(hours, P_load + P_DC, 'k--', 'LineWidth', 2);
xlabel('Hour'); ylabel('MW');
title('Supply vs. Demand Overview');
legend('Wind','Hydro','Load+DC','Location','best');
grid on; xlim([0.5 T+0.5]);
sgtitle('Narvik System — Input Data Profiles (Representative Winter Day)');

%% ================== 4. DECISION VARIABLE INDEXING =======================
% All variables packed into a single vector x for intlinprog.
%
% Standard operational variables (T values each):
%   y_B, y_TES          : binary candidate selectors
%   P_B_max, H_TES_max  : power ratings
%   P_ch_B, P_dis_B     : BESS charge/discharge [MW]
%   W_B(1:T)            : BESS energy at START of each period [MWh]
%   W_B_end             : BESS energy AFTER period T (fixes last-period exploit)
%   z_ch_B, z_dis_B     : BESS binary mode indicators
%   H_ch_TES, H_dis_TES : BTES charge/discharge [MWth]
%   W_TES(1:T)          : BTES energy at START of each period [MWhth]
%   W_TES_end           : BTES energy AFTER period T
%   z_ch_TES, z_dis_TES : BTES binary mode indicators
%   H_HP, P_HP          : heat pump thermal output and electricity [MWth, MW]
%   H_WH                : waste heat utilized [MWth]
%   P_buy, P_curt       : grid purchase and curtailment [MW]
%   H_unmet             : unmet heat demand [MWth]

idx = struct();
n = 0;
idx.y_B       = n+1 : n+nCandB;    n = n + nCandB;
idx.y_TES     = n+1 : n+nCandTES;  n = n + nCandTES;
idx.P_B_max   = n+1;                n = n + 1;
idx.H_TES_max = n+1;                n = n + 1;
idx.P_ch_B    = n+1 : n+T;         n = n + T;
idx.P_dis_B   = n+1 : n+T;         n = n + T;
idx.W_B       = n+1 : n+T;         n = n + T;
idx.W_B_end   = n+1;               n = n + 1;   % state after period T
idx.z_ch_B    = n+1 : n+T;         n = n + T;
idx.z_dis_B   = n+1 : n+T;         n = n + T;
idx.H_ch_TES  = n+1 : n+T;         n = n + T;
idx.H_dis_TES = n+1 : n+T;         n = n + T;
idx.W_TES     = n+1 : n+T;         n = n + T;
idx.W_TES_end = n+1;               n = n + 1;   % state after period T
idx.z_ch_TES  = n+1 : n+T;         n = n + T;
idx.z_dis_TES = n+1 : n+T;         n = n + T;
idx.H_HP      = n+1 : n+T;         n = n + T;
idx.P_HP      = n+1 : n+T;         n = n + T;
idx.H_WH      = n+1 : n+T;         n = n + T;
idx.P_buy     = n+1 : n+T;         n = n + T;
idx.P_curt    = n+1 : n+T;         n = n + T;
idx.H_unmet   = n+1 : n+T;         n = n + T;
nVars = n;

fprintf('Total decision variables: %d\n', nVars);
fprintf('  (Binary: %d, Continuous: %d)\n\n', ...
    nCandB + nCandTES + 4*T, nVars - nCandB - nCandTES - 4*T);

%% ================== 5. INTEGER VARIABLE INDICES =========================
intcon = [idx.y_B, idx.y_TES, ...
          idx.z_ch_B, idx.z_dis_B, ...
          idx.z_ch_TES, idx.z_dis_TES];

%% ================== 6. VARIABLE BOUNDS ==================================
lb = zeros(nVars, 1);
ub = inf(nVars, 1);

% Binary bounds [0, 1]
ub(idx.y_B)       = 1;
ub(idx.y_TES)     = 1;
ub(idx.z_ch_B)    = 1;
ub(idx.z_dis_B)   = 1;
ub(idx.z_ch_TES)  = 1;
ub(idx.z_dis_TES) = 1;

% Power/thermal ratings bounded by maximum candidate
ub(idx.P_B_max)   = gamma_B   * max(EB_cand);    % e.g. 13.65 MW
ub(idx.H_TES_max) = gamma_TES * max(ETES_cand);  % e.g. 360 MWth

% BESS energy bounds — physically tight, avoids numerical issues
% (BigM of 1e6 MW causes LP relaxation to be very loose)
ub(idx.P_ch_B)    = gamma_B * max(EB_cand);       % 13.65 MW
ub(idx.P_dis_B)   = gamma_B * max(EB_cand);       % 13.65 MW
ub(idx.W_B)       = SOC_B_max * max(EB_cand);     % 21.84 MWh
ub(idx.W_B_end)   = SOC_B_max * max(EB_cand);     % same bound for T+1 state

% BTES thermal bounds
ub(idx.H_ch_TES)  = gamma_TES * max(ETES_cand);   % 360 MWth
ub(idx.H_dis_TES) = gamma_TES * max(ETES_cand);   % 360 MWth
ub(idx.W_TES)     = SOC_TES_max * max(ETES_cand); % 1620 MWhth
ub(idx.W_TES_end) = SOC_TES_max * max(ETES_cand); % same bound for T+1 state

% Thermal subsystem
ub(idx.H_HP)      = max(H_dem) * 1.5;             % HP output bounded by demand scale
ub(idx.P_HP)      = max(H_dem) * 1.5 / COP_HP;   % HP electricity
ub(idx.H_WH)      = H_WH_avail;                   % bounded by available waste heat

% Grid / curtailment
P_supply_max = max(P_wind) + max(P_hydro) + gamma_B * max(EB_cand);
P_demand_max = max(P_load) + P_DC + max(H_dem)/COP_HP + gamma_B * max(EB_cand);
ub(idx.P_buy)     = P_demand_max;                 % physically bounded grid purchase
ub(idx.P_curt)    = P_supply_max;                 % bounded by max generation
% H_unmet: no upper bound — pen_unmet=$2000/MWh keeps it near zero in optimal
% solutions. A hard cap of max(H_dem) would cause implicit infeasibility when
% large BTES charges compete with heat demand (H_unmet needed > cap).
% ub left at inf (default); lower bound = 0 is enforced by lb.

%% ================== 7. OBJECTIVE FUNCTION ===============================
% min  CRF_B*(C_EB*1000)*E_B + CRF_TES*(C_ETES*1000)*E_TES   [investment, $/yr]
%    + C_om_B*1000*E_B + C_om_TES*1000*E_TES                  [O&M, $/yr]
%    + 365 * sum_t( price(t)*P_buy(t) + pen_curt*P_curt(t) + pen_unmet*H_unmet(t) )
f = zeros(nVars, 1);

% Investment + O&M costs (combined into candidate coefficients)
f(idx.y_B)   = (CRF_B   * C_EB   * 1000 + C_om_B   * 1000) * EB_cand(:);
f(idx.y_TES) = (CRF_TES * C_ETES * 1000 + C_om_TES * 1000) * ETES_cand(:);

% Operational costs (daily, annualized with *365)
for t = 1:T
    f(idx.P_buy(t))   = 365 * price(t)   * dt;
    f(idx.P_curt(t))  = 365 * pen_curt   * dt;
    f(idx.H_unmet(t)) = 365 * pen_unmet  * dt;
    % For T=8760: remove the *365 multipliers above
end

%% ================== 7b. P_DC = 0 SPECIAL CASE ==========================
% If no data center: disable entire thermal subsystem
if P_DC == 0
    H_dem(:)          = 0;
    ub(idx.H_HP)      = 0;
    ub(idx.P_HP)      = 0;
    ub(idx.H_WH)      = 0;
    ub(idx.H_ch_TES)  = 0;
    ub(idx.H_dis_TES) = 0;
    ub(idx.H_unmet)   = 0;
    fprintf('  NOTE: P_DC = 0 → Thermal subsystem disabled.\n\n');
end

%% ================== 8. EQUALITY CONSTRAINTS (Aeq*x = beq) ==============
nEq = 0;
Aeq_rows = {};
beq_vals = [];

% ---- (a) Select exactly one BESS candidate: sum(y_B) = 1 ----
row = zeros(1, nVars);
row(idx.y_B) = 1;
nEq = nEq + 1;  Aeq_rows{nEq} = row;  beq_vals(nEq) = 1;

% ---- (b) Select exactly one BTES candidate: sum(y_TES) = 1 ----
row = zeros(1, nVars);
row(idx.y_TES) = 1;
nEq = nEq + 1;  Aeq_rows{nEq} = row;  beq_vals(nEq) = 1;

% ---- (c) BESS SOC dynamics: W_B(t+1) = W_B(t) + eta_B*P_ch(t)*dt - P_dis(t)/eta_B*dt
%          for t = 1,...,T-1
for t = 1:T-1
    row = zeros(1, nVars);
    row(idx.W_B(t+1))  =  1;
    row(idx.W_B(t))    = -1;
    row(idx.P_ch_B(t)) = -eta_B * dt;
    row(idx.P_dis_B(t))=  (1/eta_B) * dt;
    nEq = nEq + 1;  Aeq_rows{nEq} = row;  beq_vals(nEq) = 0;
end

% ---- (d) BESS dynamics at t=T: W_B_end = W_B(T) + eta_B*P_ch(T)*dt - P_dis(T)/eta_B*dt
%          Fixes the last-period free-energy exploit: P_ch/P_dis at t=T
%          now have a SOC consequence, closing the energy loop.
row = zeros(1, nVars);
row(idx.W_B_end)   =  1;
row(idx.W_B(T))    = -1;
row(idx.P_ch_B(T)) = -eta_B * dt;
row(idx.P_dis_B(T))=  (1/eta_B) * dt;
nEq = nEq + 1;  Aeq_rows{nEq} = row;  beq_vals(nEq) = 0;

% ---- (e) BESS initial stored energy: W_B(1) = SOC_init * E_B ----
row = zeros(1, nVars);
row(idx.W_B(1)) =  1;
row(idx.y_B)    = -SOC_B_init * EB_cand;
nEq = nEq + 1;  Aeq_rows{nEq} = row;  beq_vals(nEq) = 0;

% ---- (f) BTES SOC dynamics: W_TES(t+1) = W_TES(t) + eta_TES*H_ch(t)*dt - H_dis(t)/eta_TES*dt
%          for t = 1,...,T-1
for t = 1:T-1
    row = zeros(1, nVars);
    row(idx.W_TES(t+1))  =  1;
    row(idx.W_TES(t))    = -1;
    row(idx.H_ch_TES(t)) = -eta_TES * dt;
    row(idx.H_dis_TES(t))=  (1/eta_TES) * dt;
    nEq = nEq + 1;  Aeq_rows{nEq} = row;  beq_vals(nEq) = 0;
end

% ---- (g) BTES dynamics at t=T (fixes last-period exploit for BTES) ----
row = zeros(1, nVars);
row(idx.W_TES_end)   =  1;
row(idx.W_TES(T))    = -1;
row(idx.H_ch_TES(T)) = -eta_TES * dt;
row(idx.H_dis_TES(T))=  (1/eta_TES) * dt;
nEq = nEq + 1;  Aeq_rows{nEq} = row;  beq_vals(nEq) = 0;

% ---- (h) BTES initial stored energy: W_TES(1) = SOC_init * E_TES ----
row = zeros(1, nVars);
row(idx.W_TES(1)) =  1;
row(idx.y_TES)    = -SOC_TES_init * ETES_cand;
nEq = nEq + 1;  Aeq_rows{nEq} = row;  beq_vals(nEq) = 0;

% ---- (i) Heat pump coupling: COP * P_HP(t) = H_HP(t) ----
for t = 1:T
    row = zeros(1, nVars);
    row(idx.P_HP(t)) =  COP_HP;
    row(idx.H_HP(t)) = -1;
    nEq = nEq + 1;  Aeq_rows{nEq} = row;  beq_vals(nEq) = 0;
end

% ---- (j) Electrical power balance ----
%   P_wind(t) + P_hydro(t) + P_dis_B(t) + P_buy(t)
%   = P_load(t) + P_DC + P_HP(t) + P_ch_B(t) + P_curt(t)
for t = 1:T
    row = zeros(1, nVars);
    row(idx.P_dis_B(t)) =  1;
    row(idx.P_buy(t))   =  1;
    row(idx.P_HP(t))    = -1;
    row(idx.P_ch_B(t))  = -1;
    row(idx.P_curt(t))  = -1;
    nEq = nEq + 1;
    Aeq_rows{nEq} = row;
    beq_vals(nEq) = P_load(t) + P_DC - P_wind(t) - P_hydro(t);
end

% ---- (k) Thermal (heat) balance ----
%   H_HP(t) + H_WH(t) + H_dis_TES(t) - H_ch_TES(t) + H_unmet(t) = H_dem(t)
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

% Assemble Aeq matrix
Aeq = zeros(nEq, nVars);
for k = 1:nEq
    Aeq(k,:) = Aeq_rows{k};
end
beq = beq_vals(:);
fprintf('Equality constraints: %d\n', nEq);

%% ================== 9. INEQUALITY CONSTRAINTS (A*x <= b) ================
% Pre-allocate generously
% Count: 7T+3 BESS + 4 new BESS end-state bounds + 7T+3 BTES + 4 new BTES end-state + 2T coord + buffer
maxIneq = 16*T + 58;
A_rows  = zeros(maxIneq, nVars);
b_vals  = zeros(maxIneq, 1);
nIneq   = 0;

% ============================================================
% BESS CONSTRAINTS
% ============================================================

% (1) C-rate: P_B_max <= gamma_B * E_B
nIneq = nIneq + 1;
A_rows(nIneq, idx.P_B_max) =  1;
A_rows(nIneq, idx.y_B)     = -gamma_B * EB_cand;
b_vals(nIneq) = 0;

% (2) P_ch_B(t) <= P_B_max
for t = 1:T
    nIneq = nIneq + 1;
    A_rows(nIneq, idx.P_ch_B(t)) =  1;
    A_rows(nIneq, idx.P_B_max)   = -1;
    b_vals(nIneq) = 0;
end

% (3) P_dis_B(t) <= P_B_max
for t = 1:T
    nIneq = nIneq + 1;
    A_rows(nIneq, idx.P_dis_B(t)) =  1;
    A_rows(nIneq, idx.P_B_max)    = -1;
    b_vals(nIneq) = 0;
end

% (4) P_ch_B(t) <= BigM_B * z_ch_B(t)  [tight big-M]
BigM_B = gamma_B * max(EB_cand) + 1;   % 14.65 MW
for t = 1:T
    nIneq = nIneq + 1;
    A_rows(nIneq, idx.P_ch_B(t)) =  1;
    A_rows(nIneq, idx.z_ch_B(t)) = -BigM_B;
    b_vals(nIneq) = 0;
end

% (5) P_dis_B(t) <= BigM_B * z_dis_B(t)
for t = 1:T
    nIneq = nIneq + 1;
    A_rows(nIneq, idx.P_dis_B(t)) =  1;
    A_rows(nIneq, idx.z_dis_B(t)) = -BigM_B;
    b_vals(nIneq) = 0;
end

% (6) No simultaneous charge/discharge: z_ch_B(t) + z_dis_B(t) <= 1
for t = 1:T
    nIneq = nIneq + 1;
    A_rows(nIneq, idx.z_ch_B(t))  = 1;
    A_rows(nIneq, idx.z_dis_B(t)) = 1;
    b_vals(nIneq) = 1;
end

% (7) SOC lower bound: W_B(t) >= SOC_B_min * E_B
for t = 1:T
    nIneq = nIneq + 1;
    A_rows(nIneq, idx.y_B)    =  SOC_B_min * EB_cand;
    A_rows(nIneq, idx.W_B(t)) = -1;
    b_vals(nIneq) = 0;
end

% (8) SOC upper bound: W_B(t) <= SOC_B_max * E_B
for t = 1:T
    nIneq = nIneq + 1;
    A_rows(nIneq, idx.W_B(t)) =  1;
    A_rows(nIneq, idx.y_B)    = -SOC_B_max * EB_cand;
    b_vals(nIneq) = 0;
end

% (9) SOC bounds on W_B_end (end-of-day state, after period T)
%     Explicit min/max bounds prevent SOC_tol from pushing end state outside
%     physical limits if SOC_tol is ever increased beyond 0.30.
%     Lower: W_B_end >= SOC_B_min * E_B
nIneq = nIneq + 1;
A_rows(nIneq, idx.y_B)     =  SOC_B_min * EB_cand;
A_rows(nIneq, idx.W_B_end) = -1;
b_vals(nIneq) = 0;
%     Upper: W_B_end <= SOC_B_max * E_B
nIneq = nIneq + 1;
A_rows(nIneq, idx.W_B_end) =  1;
A_rows(nIneq, idx.y_B)     = -SOC_B_max * EB_cand;
b_vals(nIneq) = 0;

% (10) Cyclic SOC on W_B_end: (SOC_init - tol)*E_B <= W_B_end <= (SOC_init + tol)*E_B
nIneq = nIneq + 1;
A_rows(nIneq, idx.y_B)      =  (SOC_B_init - SOC_tol) * EB_cand;
A_rows(nIneq, idx.W_B_end)  = -1;
b_vals(nIneq) = 0;

nIneq = nIneq + 1;
A_rows(nIneq, idx.W_B_end)  =  1;
A_rows(nIneq, idx.y_B)      = -(SOC_B_init + SOC_tol) * EB_cand;
b_vals(nIneq) = 0;

% ============================================================
% BTES CONSTRAINTS
% ============================================================

% Lock BTES = 0 when P_DC = 0
if P_DC == 0
    for s = 2:nCandTES
        nIneq = nIneq + 1;
        A_rows(nIneq, idx.y_TES(s)) = 1;
        b_vals(nIneq) = 0;
    end
end

% (11) C-rate: H_TES_max <= gamma_TES * E_TES
nIneq = nIneq + 1;
A_rows(nIneq, idx.H_TES_max) =  1;
A_rows(nIneq, idx.y_TES)     = -gamma_TES * ETES_cand;
b_vals(nIneq) = 0;

% (12) H_ch_TES(t) <= H_TES_max
for t = 1:T
    nIneq = nIneq + 1;
    A_rows(nIneq, idx.H_ch_TES(t)) =  1;
    A_rows(nIneq, idx.H_TES_max)   = -1;
    b_vals(nIneq) = 0;
end

% (13) H_dis_TES(t) <= H_TES_max
for t = 1:T
    nIneq = nIneq + 1;
    A_rows(nIneq, idx.H_dis_TES(t)) =  1;
    A_rows(nIneq, idx.H_TES_max)    = -1;
    b_vals(nIneq) = 0;
end

% (14) H_ch_TES(t) <= BigM_TES * z_ch_TES(t)
BigM_TES = gamma_TES * max(ETES_cand) + 1;   % 361 MWth
for t = 1:T
    nIneq = nIneq + 1;
    A_rows(nIneq, idx.H_ch_TES(t)) =  1;
    A_rows(nIneq, idx.z_ch_TES(t)) = -BigM_TES;
    b_vals(nIneq) = 0;
end

% (15) H_dis_TES(t) <= BigM_TES * z_dis_TES(t)
for t = 1:T
    nIneq = nIneq + 1;
    A_rows(nIneq, idx.H_dis_TES(t)) =  1;
    A_rows(nIneq, idx.z_dis_TES(t)) = -BigM_TES;
    b_vals(nIneq) = 0;
end

% (16) No simultaneous charge/discharge: z_ch_TES(t) + z_dis_TES(t) <= 1
for t = 1:T
    nIneq = nIneq + 1;
    A_rows(nIneq, idx.z_ch_TES(t))  = 1;
    A_rows(nIneq, idx.z_dis_TES(t)) = 1;
    b_vals(nIneq) = 1;
end

% (17) SOC lower bound: W_TES(t) >= SOC_TES_min * E_TES
for t = 1:T
    nIneq = nIneq + 1;
    A_rows(nIneq, idx.y_TES)    =  SOC_TES_min * ETES_cand;
    A_rows(nIneq, idx.W_TES(t)) = -1;
    b_vals(nIneq) = 0;
end

% (18) SOC upper bound: W_TES(t) <= SOC_TES_max * E_TES
for t = 1:T
    nIneq = nIneq + 1;
    A_rows(nIneq, idx.W_TES(t)) =  1;
    A_rows(nIneq, idx.y_TES)    = -SOC_TES_max * ETES_cand;
    b_vals(nIneq) = 0;
end

% (19) SOC bounds on W_TES_end (end-of-day state, after period T)
%     Lower: W_TES_end >= SOC_TES_min * E_TES
nIneq = nIneq + 1;
A_rows(nIneq, idx.y_TES)     =  SOC_TES_min * ETES_cand;
A_rows(nIneq, idx.W_TES_end) = -1;
b_vals(nIneq) = 0;
%     Upper: W_TES_end <= SOC_TES_max * E_TES
nIneq = nIneq + 1;
A_rows(nIneq, idx.W_TES_end) =  1;
A_rows(nIneq, idx.y_TES)     = -SOC_TES_max * ETES_cand;
b_vals(nIneq) = 0;

% (20) Cyclic SOC on W_TES_end
nIneq = nIneq + 1;
A_rows(nIneq, idx.y_TES)      =  (SOC_TES_init - SOC_tol) * ETES_cand;
A_rows(nIneq, idx.W_TES_end)  = -1;
b_vals(nIneq) = 0;

nIneq = nIneq + 1;
A_rows(nIneq, idx.W_TES_end)  =  1;
A_rows(nIneq, idx.y_TES)      = -(SOC_TES_init + SOC_tol) * ETES_cand;
b_vals(nIneq) = 0;

% ============================================================
% BESS–BTES COORDINATED DISPATCH CONSTRAINTS
% ============================================================
% Physical rationale: In the Arctic data-center HESS, BESS and BTES
% should charge/discharge in coordinated modes driven by electricity price.
%
% Low-price hours  → BESS charges (z_ch_B=1) AND BTES charges (z_ch_TES=1)
% High-price hours → BESS discharges (z_dis_B=1) AND BTES discharges (z_dis_TES=1)
%
% Constraint A: BTES does not discharge while BESS is charging
%   z_ch_B(t) + z_dis_TES(t) <= 1
%   Prevents: cheap-electricity period (BESS charging) wasted by BTES discharge.
%
% Constraint B: BTES does not charge (via HP) while BESS is discharging
%   z_dis_B(t) + z_ch_TES(t) <= 1
%   Prevents: expensive-electricity period (BESS discharging) burdened by HP load.
%   NOTE: This blocks HP-based BTES charging during discharge hours, but BTES
%   can still receive free waste heat regardless (waste heat is not electrical).

% Constraint A
for t = 1:T
    nIneq = nIneq + 1;
    A_rows(nIneq, idx.z_ch_B(t))   = 1;
    A_rows(nIneq, idx.z_dis_TES(t))= 1;
    b_vals(nIneq) = 1;
end

% Constraint B
for t = 1:T
    nIneq = nIneq + 1;
    A_rows(nIneq, idx.z_dis_B(t))  = 1;
    A_rows(nIneq, idx.z_ch_TES(t)) = 1;
    b_vals(nIneq) = 1;
end

% ============================================================
% Trim to actual count
% ============================================================
if nIneq > maxIneq
    error('maxIneq too small: need %d, allocated %d. Increase maxIneq.', nIneq, maxIneq);
end
A = A_rows(1:nIneq, :);
b = b_vals(1:nIneq);
fprintf('Inequality constraints: %d\n', nIneq);
fprintf('Total constraints: %d\n\n', nEq + nIneq);

%% ================== 10. SOLVE WITH intlinprog ===========================
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

%% ================== 11. EXTRACT & DISPLAY RESULTS =======================
if exitflag >= 1
    fprintf('\n==============================================================\n');
    fprintf('                 OPTIMAL SIZING RESULTS\n');
    fprintf('==============================================================\n');

    % Selected candidates
    y_B_sol   = round(x_opt(idx.y_B));
    sel_B     = find(y_B_sol == 1);
    E_B_opt   = EB_cand(sel_B);
    P_B_opt   = x_opt(idx.P_B_max);

    y_TES_sol = round(x_opt(idx.y_TES));
    sel_TES   = find(y_TES_sol == 1);
    E_TES_opt = ETES_cand(sel_TES);
    H_TES_opt = x_opt(idx.H_TES_max);

    fprintf('\n  BESS:\n');
    fprintf('    Energy capacity  E_B     = %.1f MWh\n', E_B_opt);
    fprintf('    Power rating     P_B_max = %.2f MW\n', P_B_opt);
    fprintf('    C-rate check:    P/E     = %.3f (limit: %.2f)\n', ...
        P_B_opt / max(E_B_opt, 0.01), gamma_B);

    fprintf('\n  BTES:\n');
    fprintf('    Thermal capacity E_TES     = %.1f MWhth\n', E_TES_opt);
    fprintf('    Thermal power    H_TES_max = %.2f MWth\n', H_TES_opt);
    fprintf('    C-rate check:    H/E       = %.3f (limit: %.2f)\n', ...
        H_TES_opt / max(E_TES_opt, 0.01), gamma_TES);
    fprintf('    Round-trip eff.  eta^2     = %.2f (%.0f%%)\n', ...
        eta_TES^2, eta_TES^2 * 100);

    % Cost breakdown
    inv_B   = (CRF_B   * C_EB   * 1000 + C_om_B   * 1000) * E_B_opt;
    inv_TES = (CRF_TES * C_ETES * 1000 + C_om_TES * 1000) * E_TES_opt;
    P_buy_sol   = x_opt(idx.P_buy);
    P_curt_sol  = x_opt(idx.P_curt);
    H_unmet_sol = x_opt(idx.H_unmet);
    cost_buy   = 365 * sum(price .* P_buy_sol   * dt);
    cost_curt  = 365 * sum(pen_curt  * P_curt_sol  * dt);
    cost_unmet = 365 * sum(pen_unmet * H_unmet_sol * dt);

    fprintf('\n  COST BREAKDOWN:\n');
    fprintf('    BESS investment+O&M  = $%12.0f /yr\n', inv_B);
    fprintf('    BTES investment+O&M  = $%12.0f /yr\n', inv_TES);
    fprintf('    Grid purchase        = $%12.0f /yr\n', cost_buy);
    fprintf('    Curtailment penalty  = $%12.0f /yr\n', cost_curt);
    fprintf('    Unmet heat penalty   = $%12.0f /yr\n', cost_unmet);
    fprintf('    TOTAL                = $%12.0f /yr\n', fval);

    % Extract operational profiles
    P_ch_B_sol    = x_opt(idx.P_ch_B);
    P_dis_B_sol   = x_opt(idx.P_dis_B);
    W_B_sol       = x_opt(idx.W_B);
    W_B_end_sol   = x_opt(idx.W_B_end);
    H_ch_TES_sol  = x_opt(idx.H_ch_TES);
    H_dis_TES_sol = x_opt(idx.H_dis_TES);
    W_TES_sol     = x_opt(idx.W_TES);
    W_TES_end_sol = x_opt(idx.W_TES_end);
    H_HP_sol      = x_opt(idx.H_HP);
    P_HP_sol      = x_opt(idx.P_HP);
    H_WH_sol      = x_opt(idx.H_WH);

    % SOC fractions (T+1 points, including end state)
    W_B_full   = [W_B_sol;   W_B_end_sol];
    W_TES_full = [W_TES_sol; W_TES_end_sol];
    if E_B_opt > 0
        SOC_B_sol   = W_B_full   / E_B_opt;
    else
        SOC_B_sol   = zeros(T+1, 1);
    end
    if E_TES_opt > 0
        SOC_TES_sol = W_TES_full / E_TES_opt;
    else
        SOC_TES_sol = zeros(T+1, 1);
    end

    fprintf('\n  DAILY ENERGY SUMMARY:\n');
    fprintf('    Total wind generation    = %.1f MWh\n',  sum(P_wind)   * dt);
    fprintf('    Total hydro generation   = %.1f MWh\n',  sum(P_hydro)  * dt);
    fprintf('    Total elec demand (w/DC) = %.1f MWh\n',  sum(P_load+P_DC) * dt);
    fprintf('    Total heat demand        = %.1f MWhth\n', sum(H_dem)    * dt);
    fprintf('    Grid purchase            = %.1f MWh\n',  sum(P_buy_sol)   * dt);
    fprintf('    Curtailed energy         = %.1f MWh\n',  sum(P_curt_sol)  * dt);
    fprintf('    Unmet heat               = %.1f MWhth\n', sum(H_unmet_sol) * dt);
    fprintf('    BESS charge / discharge  = %.1f / %.1f MWh\n', ...
        sum(P_ch_B_sol)*dt, sum(P_dis_B_sol)*dt);
    fprintf('    BTES charge / discharge  = %.1f / %.1f MWhth\n', ...
        sum(H_ch_TES_sol)*dt, sum(H_dis_TES_sol)*dt);
    fprintf('    Waste heat utilized      = %.1f MWhth\n', sum(H_WH_sol)  * dt);
    fprintf('    HP heat output / elec    = %.1f MWhth / %.1f MWh\n', ...
        sum(H_HP_sol)*dt, sum(P_HP_sol)*dt);

    %% ============== 12. PLOTTING =========================================
    hours    = 1:T;
    hours_T1 = 1:T+1;   % extended axis for SOC plots

    % Figure 1: Electrical Power Balance
    figure('Name','Electrical Balance','Position',[50 400 900 500]);
    supply = [P_wind, P_hydro, P_dis_B_sol, P_buy_sol];
    bar(hours, supply, 'stacked'); hold on;
    P_total_dem = P_load + P_DC + P_HP_sol + P_ch_B_sol;
    plot(hours, P_total_dem, 'k-o', 'LineWidth', 2, 'MarkerSize', 4);
    hold off;
    xlabel('Hour'); ylabel('Power [MW]');
    title('Electrical Power Balance — Narvik System');
    legend('Wind','Hydro','BESS Discharge','Grid Purchase','Total Demand', ...
        'Location','northwest');
    grid on; xlim([0.5 T+0.5]);

    % Figure 2: BESS Operation
    figure('Name','BESS Operation','Position',[50 50 900 450]);
    subplot(2,1,1);
    bar(hours, P_ch_B_sol,  'FaceColor', [0.2 0.6 0.2]); hold on;
    bar(hours, -P_dis_B_sol,'FaceColor', [0.8 0.2 0.2]); hold off;
    ylabel('Power [MW]');
    title(sprintf('BESS Operation (E_B = %.0f MWh, P_{max} = %.1f MW)', E_B_opt, P_B_opt));
    legend('Charge','Discharge','Location','best'); grid on; xlim([0.5 T+0.5]);
    subplot(2,1,2);
    plot(hours_T1, SOC_B_sol*100, 'b-o', 'LineWidth', 2, 'MarkerSize', 4); hold on;
    yline(SOC_B_min*100, 'r--', 'SOC_{min}', 'LineWidth', 1.5);
    yline(SOC_B_max*100, 'r--', 'SOC_{max}', 'LineWidth', 1.5);
    hold off;
    xlabel('Hour (T+1 = end-of-day state)'); ylabel('SOC [%]');
    title('BESS State of Charge'); grid on; xlim([0.5 T+1.5]); ylim([0 100]);

    % Figure 3: BTES Operation
    figure('Name','BTES Operation','Position',[500 50 900 450]);
    subplot(2,1,1);
    bar(hours, H_ch_TES_sol,  'FaceColor', [0.9 0.5 0.1]); hold on;
    bar(hours, -H_dis_TES_sol,'FaceColor', [0.1 0.5 0.9]); hold off;
    ylabel('Thermal Power [MWth]');
    title(sprintf('BTES Operation (E_{TES} = %.0f MWhth, H_{max} = %.1f MWth, \\eta^2 = %.0f%%)', ...
        E_TES_opt, H_TES_opt, eta_TES^2*100));
    legend('Charge','Discharge','Location','best'); grid on; xlim([0.5 T+0.5]);
    subplot(2,1,2);
    plot(hours_T1, SOC_TES_sol*100, 'm-o', 'LineWidth', 2, 'MarkerSize', 4); hold on;
    yline(SOC_TES_min*100, 'r--', 'SOC_{min}', 'LineWidth', 1.5);
    yline(SOC_TES_max*100, 'r--', 'SOC_{max}', 'LineWidth', 1.5);
    hold off;
    xlabel('Hour (T+1 = end-of-day state)'); ylabel('SOC [%]');
    title('BTES State of Charge'); grid on; xlim([0.5 T+1.5]); ylim([0 100]);

    % Figure 4: Thermal Balance
    figure('Name','Thermal Balance','Position',[100 200 900 450]);
    supply_th = [H_HP_sol, H_WH_sol, H_dis_TES_sol, H_unmet_sol];
    bar(hours, supply_th, 'stacked'); hold on;
    plot(hours, H_dem + H_ch_TES_sol, 'k-o', 'LineWidth', 2, 'MarkerSize', 4);
    hold off;
    xlabel('Hour'); ylabel('Thermal Power [MWth]');
    title('Thermal (Heat) Balance — Narvik District Heating');
    legend('HP Output','Waste Heat','BTES Discharge','Unmet Heat', ...
        'Demand + BTES Charge','Location','northwest');
    grid on; xlim([0.5 T+0.5]);

    % Figure 5: Price vs. Grid Purchase
    figure('Name','Price vs Grid','Position',[200 300 900 400]);
    yyaxis left;
    bar(hours, max(P_buy_sol, 0), 'FaceColor', [0.4 0.7 0.9], 'FaceAlpha', 0.7);
    ylabel('Grid Purchase [MW]');
    yyaxis right;
    plot(hours, price, 'r-s', 'LineWidth', 2, 'MarkerSize', 5);
    ylabel('Price [$/MWh]');
    xlabel('Hour');
    title('Grid Purchase vs. Electricity Price');
    legend('Grid Purchase','Elec Price','Location','best');
    grid on; xlim([0.5 T+0.5]);

    % Figure 6: Cost Breakdown Pie
    figure('Name','Cost Breakdown','Position',[300 250 500 400]);
    costs  = [inv_B, inv_TES, cost_buy, cost_curt, cost_unmet];
    labels = {'BESS Inv+O&M','BTES Inv+O&M','Grid Purchase','Curtailment','Unmet Heat'};
    nonzero = costs > 0.01;
    pie(costs(nonzero), labels(nonzero));
    title('Annualized Cost Breakdown');

    fprintf('\n==============================================================\n');
    fprintf('  Optimization complete. 6 figures generated.\n');
    fprintf('==============================================================\n');
else
    fprintf('\nOptimization failed. Check constraints and data.\n');
end


%% ========================================================================
%% LOCAL FUNCTION — must remain at the END of this script file
%% ========================================================================
function [P_wind, P_hydro, P_load, H_dem, price, T] = load_Narvik_data()
%% load_Narvik_data  — Load all input profiles for MILP optimization
%
%  Loads 5 input profiles. Uses real CSV data when available; falls back
%  to documented synthetic profiles otherwise.
%
%  DATA SOURCES:
%  [S1] Wind:  Renewables.ninja (NASA MERRA-2) — Pfenninger & Staffell (2016)
%  [S2] Price: Nord Pool Data Portal, NO4 day-ahead prices
%  [S3] Load:  ENTSO-E Transparency Platform, Actual Total Load NO4
%  [S4] Heat:  When2Heat (Open Power System Data), Ruhnau et al. (2019)
%  [S5] Hydro: Price-responsive reservoir model / ENTSO-E generation
%
%  OUTPUT: 24×1 column vectors (representative winter day)

T = 24;
fprintf('Loading Narvik data profiles...\n');
fprintf('--------------------------------------------------------------\n');

%% 1. WIND
P_wind_nameplate = 32.2;  % MW (14 × Siemens 2.3 MW, Nygårdsfjellet)
wind_file = 'ninja_wind_68.4500_17.3900_corrected.csv';
if isfile(wind_file)
    fprintf('  Wind:  Loading from Renewables.ninja CSV...\n');
    data_wind  = readtable(wind_file, 'HeaderLines', 3);
    P_jan      = data_wind.electricity(1:744);
    P_wind     = mean(reshape(P_jan, 24, []), 2);
    fprintf('         Range: %.1f - %.1f MW (CF=%.0f%%)\n', ...
        min(P_wind), max(P_wind), mean(P_wind)/P_wind_nameplate*100);
else
    fprintf('  Wind:  [SYNTHETIC] CSV not found.\n');
    fprintf('         Download: https://www.renewables.ninja/ (68.45N,17.39E)\n');
    winter_CF = [0.52 0.50 0.48 0.45 0.43 0.40 0.38 0.35 ...
                 0.33 0.30 0.28 0.27 0.28 0.30 0.35 0.40 ...
                 0.45 0.50 0.55 0.58 0.56 0.52 0.48 0.45]';
    P_wind = P_wind_nameplate * winter_CF;
end

%% 2. ELECTRICITY PRICE
price_file = 'nordpool_NO4_2024.csv';
if isfile(price_file)
    fprintf('  Price: Loading from Nord Pool CSV...\n');
    data_price = readtable(price_file);
    if ismember('NO4', data_price.Properties.VariableNames)
        price_EUR_h = data_price.NO4;
    elseif ismember('Price', data_price.Properties.VariableNames)
        price_EUR_h = data_price.Price;
    else
        numcols = varfun(@isnumeric, data_price, 'OutputFormat', 'uniform');
        price_EUR_h = data_price{:, find(numcols, 1)};
    end
    price_jan = price_EUR_h(1:744);
    price = mean(reshape(price_jan, 24, []), 2) * 1.08;  % EUR → USD
    fprintf('         Range: %.1f - %.1f $/MWh\n', min(price), max(price));
else
    fprintf('  Price: [SYNTHETIC] CSV not found.\n');
    fprintf('         Download: https://data.nordpoolgroup.com/ (NO4, 2024)\n');
    % NO4 winter pattern: low at night, peaks at morning (h7-9) and evening (h17-19)
    price_EUR = [30 28 25 23 22 25 35 55 65 60 55 50 ...
                 48 50 55 60 72 80 70 58 48 40 35 32]';
    price = price_EUR * 1.08;
end

%% 3. ELECTRICAL LOAD
% Supported file formats (checked in priority order):
%   1. 'time_series_60min_singleindex.csv'  — OPSD Time Series (Zenodo 8423312)
%      Column: 'NO_4_load_actual_entsoe_transparency' [MW], time: 'utc_timestamp'
%   2. 'entsoe_NO4_load_2024.csv'           — ENTSO-E Transparency direct export
%      Columns: 'ActualTotalLoad' or 'Value' [MW]
opsd_file = 'time_series_60min_singleindex.csv';   % OPSD / Zenodo 8423312
load_file = 'entsoe_NO4_load_2024.csv';
scale_factor = 0.055;   % NO4 region → Narvik grid (pop. 18,700 + LKAB industrial)

if isfile(opsd_file)
    fprintf('  Load:  Loading from OPSD time series CSV (Zenodo 8423312)...\n');
    % VariableNamingRule 'preserve' keeps underscores and dots in column names
    data_load = readtable(opsd_file, 'VariableNamingRule', 'preserve');

    opsd_col = 'NO_4_load_actual_entsoe_transparency';
    if ismember(opsd_col, data_load.Properties.VariableNames)
        load_NO4 = data_load.(opsd_col);
    else
        % Fallback: first numeric column (some OPSD exports differ slightly)
        numcols  = varfun(@isnumeric, data_load, 'OutputFormat', 'uniform');
        load_NO4 = data_load{:, find(numcols, 1)};
        fprintf('  [WARN] Column ''%s'' not found; using first numeric column.\n', opsd_col);
    end

    % OPSD data often contains NaN gaps — fill by linear interpolation
    t_idx  = (1:numel(load_NO4))';
    valid  = ~isnan(load_NO4);
    if any(~valid)
        load_NO4 = interp1(t_idx(valid), load_NO4(valid), t_idx, 'linear', 'extrap');
        fprintf('         Interpolated %d NaN gaps in NO4 load.\n', sum(~valid));
    end

    % Use first 744 hours (January) — representative Arctic winter day
    if numel(load_NO4) < 744
        error('OPSD file too short: need ≥744 rows for January average, got %d.', numel(load_NO4));
    end
    load_jan    = load_NO4(1:744);
    load_winter = mean(reshape(load_jan, 24, []), 2);   % 24×1 hourly average
    P_load      = load_winter * scale_factor;
    fprintf('         NO4 Jan avg: %.0f - %.0f MW  →  Narvik (×%.3f): %.1f - %.1f MW\n', ...
        min(load_winter), max(load_winter), scale_factor, min(P_load), max(P_load));

elseif isfile(load_file)
    fprintf('  Load:  Loading from ENTSO-E CSV...\n');
    data_load = readtable(load_file);
    if ismember('ActualTotalLoad', data_load.Properties.VariableNames)
        load_NO4 = data_load.ActualTotalLoad;
    elseif ismember('Value', data_load.Properties.VariableNames)
        load_NO4 = data_load.Value;
    else
        numcols  = varfun(@isnumeric, data_load, 'OutputFormat', 'uniform');
        load_NO4 = data_load{:, find(numcols, 1)};
    end
    load_jan    = load_NO4(1:744);
    load_winter = mean(reshape(load_jan, 24, []), 2);
    P_load      = load_winter * scale_factor;
    fprintf('         Narvik scaled (×%.3f): %.1f - %.1f MW\n', scale_factor, min(P_load), max(P_load));

else
    fprintf('  Load:  [SYNTHETIC] No CSV found.\n');
    fprintf('         Option 1 (OPSD): https://zenodo.org/records/8423312\n');
    fprintf('                          File: time_series_60min_singleindex.csv\n');
    fprintf('         Option 2 (ENTSO-E): https://transparency.entsoe.eu/ (NO4, 2024)\n');
    % Nordic load pattern: morning ramp 06-09, evening peak 17-20
    P_load = [22 21 21 21 22 25 30 35 38 40 41 40 ...
              39 38 37 36 38 42 44 43 40 35 28 24]';
end

%% 4. HEAT DEMAND
heat_file = 'when2heat_singleindex.csv';
if isfile(heat_file)
    fprintf('  Heat:  Loading from When2Heat CSV...\n');
    data_heat = readtable(heat_file);
    if ismember('NO_heat_demand_total', data_heat.Properties.VariableNames)
        H_norm = data_heat.NO_heat_demand_total;
    elseif ismember('NO_heat_demand_space', data_heat.Properties.VariableNames)
        H_norm = data_heat.NO_heat_demand_space;
    else
        numcols = varfun(@isnumeric, data_heat, 'OutputFormat', 'uniform');
        H_norm  = data_heat{:, find(numcols, 1)};
    end
    H_jan  = H_norm(1:744);
    H_winter_norm = mean(reshape(H_jan, 24, []), 2);
    H_dem  = H_winter_norm / max(H_winter_norm) * 20;   % scale to peak 20 MWth
    fprintf('         Narvik DH: %.1f - %.1f MWth\n', min(H_dem), max(H_dem));
else
    fprintf('  Heat:  [SYNTHETIC] Degree-day method.\n');
    fprintf('         Download: https://data.open-power-system-data.org/when2heat/\n');
    % Narvik January: T_indoor=21°C, T_outdoor coldest 04h (-12°C), warmest 13h (-4°C)
    T_indoor  = 21;
    T_outdoor = [-10 -11 -12 -12 -12 -11 -9 -7 -6 -5 -4 -4 ...
                  -4  -5  -6  -7  -8  -9 -10 -10 -10 -10 -10 -10]';
    H_dem_raw = T_indoor - T_outdoor;
    H_dem     = H_dem_raw / max(H_dem_raw) * 20;   % peak = 20 MWth
end

%% 5. HYDRO GENERATION
P_hydro_hakvik   =  9.9;   % MW [Nordkraft, verified]
P_hydro_batsvatn = 30.0;   % MW [user-defined]
P_hydro_sildvik  = 63.0;   % MW [Statkraft, commissioned 1975]
P_hydro_total    = P_hydro_hakvik + P_hydro_batsvatn + P_hydro_sildvik;  % 102.9 MW

hydro_file = 'entsoe_NO4_hydro_2024.csv';
if isfile(hydro_file)
    fprintf('  Hydro: Loading from ENTSO-E CSV...\n');
    data_hydro = readtable(hydro_file);
    NO4_hydro_cap = 4000;   % MW (NO4 total installed hydro capacity)
    if ismember('HydroReservoir', data_hydro.Properties.VariableNames)
        hydro_NO4 = data_hydro.HydroReservoir;
    elseif ismember('Value', data_hydro.Properties.VariableNames)
        hydro_NO4 = data_hydro.Value;
    else
        numcols  = varfun(@isnumeric, data_hydro, 'OutputFormat', 'uniform');
        hydro_NO4 = data_hydro{:, find(numcols, 1)};
    end
    hydro_jan = hydro_NO4(1:744);
    hydro_winter = mean(reshape(hydro_jan, 24, []), 2);
    P_hydro = hydro_winter * (P_hydro_total / NO4_hydro_cap);
else
    fprintf('  Hydro: [SYNTHETIC] Price-responsive dispatch model.\n');
    % Norwegian reservoir hydro: dispatch fraction linearly proportional to
    % normalized price, ranging from 60% (off-peak) to 90% (peak).
    % This matches observed Norwegian hydro scheduling practices.
    % Ref: Helseth et al. (2015), Energies 8(12).
    price_norm    = (price - min(price)) / (max(price) - min(price));
    dispatch_frac = 0.60 + 0.30 * price_norm;   % 60% to 90% of installed capacity
    P_hydro       = dispatch_frac .* P_hydro_total;
end

fprintf('  Hydro: %.1f - %.1f MW (installed: %.1f MW)\n', ...
    min(P_hydro), max(P_hydro), P_hydro_total);

%% SUMMARY
fprintf('--------------------------------------------------------------\n');
fprintf('  PROFILE SUMMARY (representative winter day, T=%d h):\n', T);
fprintf('  Wind:  %.1f-%.1f MW  (CF≈%.0f%%)\n', ...
    min(P_wind), max(P_wind), mean(P_wind)/P_wind_nameplate*100);
fprintf('  Hydro: %.1f-%.1f MW  (installed %.1f MW)\n', ...
    min(P_hydro), max(P_hydro), P_hydro_total);
fprintf('  Load:  %.1f-%.1f MW  (excl. DC, daily %.0f MWh)\n', ...
    min(P_load), max(P_load), sum(P_load));
fprintf('  Heat:  %.1f-%.1f MWth (daily %.0f MWhth)\n', ...
    min(H_dem), max(H_dem), sum(H_dem));
fprintf('  Price: %.1f-%.1f $/MWh (avg %.1f $/MWh)\n', ...
    min(price), max(price), mean(price));

% Data source status
fprintf('\n  DATA SOURCES:\n');
% For load: OPSD file takes priority over ENTSO-E direct export
if isfile(opsd_file)
    load_source = 'OPSD Zenodo 8423312 [S3]';
    load_real   = true;
elseif isfile(load_file)
    load_source = 'ENTSO-E Load [S3]';
    load_real   = true;
else
    load_source = 'ENTSO-E Load [S3]';
    load_real   = false;
end
files   = {wind_file, price_file, '',        heat_file, hydro_file};
sources = {'Renewables.ninja [S1]', 'Nord Pool NO4 [S2]', ...
           load_source, 'When2Heat [S4]', 'ENTSO-E Hydro [S5]'};
for i = 1:5
    if i == 3
        status = load_real;
    else
        status = isfile(files{i});
    end
    if status
        fprintf('    %-30s  REAL DATA\n', sources{i});
    else
        fprintf('    %-30s  SYNTHETIC\n', sources{i});
    end
end
fprintf('--------------------------------------------------------------\n\n');
end
