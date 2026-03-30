function params = setup_parameters()
% SETUP_PARAMETERS  Define all model parameters for the MILP sizing problem.
%
% Returns:
%   params — struct with fields for BESS, BTES, DC, HP, economic, candidates

%% Time
params.T  = 96;       % hours (representative day)
params.dt = 1;        % time step [h]

%% BESS Parameters
params.eta_B       = 0.95;     % one-way efficiency (charge & discharge)
                                % RTE = 0.95^2 = 90.25% (Tesla Megapack ≈ 92%)
params.SOC_B_min   = 0.20;     % minimum SOC [frac]
params.SOC_B_max   = 0.80;     % maximum SOC [frac]
params.SOC_B_init  = 0.50;     % initial SOC [frac]
params.gamma_B     = 0.50;     % C-rate [1/h] (2-hour duration)
params.C_EB        = 285;      % investment cost [$/kWh] (Tesla Megapack 2024)
params.Life_B      = 15;       % lifetime [years]
params.C_om_B      = 2.5;      % O&M cost [$/kWh/yr]
params.SOC_tol     = 0.15;     % cyclic SOC tolerance [frac]

%% BTES Parameters — FIX #1: Asymmetric efficiency
% Old: eta_TES = 0.4 (one-way) → RTE = 0.4^2 = 16% (too low!)
% New: asymmetric → RTE = 0.90 × 0.45 = 40.5%
params.eta_ch_TES  = 0.90;     % charging efficiency (heat entering boreholes)
params.eta_dis_TES = 0.45;     % discharge recovery factor (heat extracted)
% Reference: Dutch HT-BTES factsheet, typical recovery 30-50%

params.SOC_TES_min  = 0.10;    % minimum SOC [frac]
params.SOC_TES_max  = 0.90;    % maximum SOC [frac]
params.SOC_TES_init = 0.50;    % initial SOC [frac]
params.gamma_TES    = 0.20;    % C-rate [1/h] (lower for BTES in Arctic)
params.C_ETES       = 0.6;     % investment cost [$/kWhth] (0.6-3 €/kWh range)
params.Life_TES     = 30;      % lifetime [years]
params.C_om_TES     = 0.048;   % O&M cost [$/kWhth/yr] (2-8% of investment)

%% AI Data Center
params.P_DC     = 30;          % data center electrical load [MW]
params.beta_WH  = 0.70;        % waste heat recovery coefficient
params.H_WH_avail = params.beta_WH * params.P_DC;  % available waste heat [MWth]

%% Heat Pump — FIX #3: Add investment cost
params.COP_HP    = 3.5;        % coefficient of performance (Arctic avg)
params.C_HP_cap  = 800;        % investment cost [$/kWth] (range: 500-1500)
params.Life_HP   = 20;         % lifetime [years]
params.C_om_HP   = 16;         % O&M [$/kWth/yr] (2% of investment)

%% Economic
params.disc_rate = 0.06;       % discount rate
params.pen_curt  = 50;         % curtailment penalty [$/MWh]
params.pen_unmet = 2000;       % unmet heat penalty [$/MWhth] (= $2/kWhth)

%% Capital Recovery Factors
r = params.disc_rate;
params.CRF_B   = r*(1+r)^params.Life_B   / ((1+r)^params.Life_B   - 1);
params.CRF_TES = r*(1+r)^params.Life_TES / ((1+r)^params.Life_TES - 1);
params.CRF_HP  = r*(1+r)^params.Life_HP  / ((1+r)^params.Life_HP  - 1);

fprintf('CRF_BESS  = %.4f\n', params.CRF_B);
fprintf('CRF_BTES  = %.4f\n', params.CRF_TES);
fprintf('CRF_HP    = %.4f\n\n', params.CRF_HP);

%% Discrete Candidate Sizes
% Tesla Megapack: 3.9 MWh per unit (2-hour config)
params.EB_cand   = [0, 3.9, 7.8, 11.7, 15.6, 19.5, 23.4, 27.3];  % [MWh]
params.ETES_cand = [0, 20, 50, 100, 150, 200, 300];                % [MWhth]

params.nCandB   = length(params.EB_cand);
params.nCandTES = length(params.ETES_cand);

end
