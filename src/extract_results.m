function res = extract_results(x_opt, fval, params, idx, T, P_wind, P_hydro, P_load, H_dem, price)
% EXTRACT_RESULTS  Extract optimal values from solution vector and display summary.
%
% Returns:
%   res — struct with all solution profiles and cost components

dt = params.dt;

fprintf('\n==============================================================\n');
fprintf('                 OPTIMAL SIZING RESULTS\n');
fprintf('==============================================================\n');

%% Selected Candidates
y_B_sol   = round(x_opt(idx.y_B));
sel_B     = find(y_B_sol == 1);
res.E_B   = params.EB_cand(sel_B);
res.P_B   = x_opt(idx.P_B_max);

y_TES_sol  = round(x_opt(idx.y_TES));
sel_TES    = find(y_TES_sol == 1);
res.E_TES  = params.ETES_cand(sel_TES);
res.H_TES  = x_opt(idx.H_TES_max);

res.Q_HP   = x_opt(idx.Q_HP_cap);

fprintf('\n  BESS:\n');
fprintf('    Energy capacity  E_B     = %.1f MWh\n', res.E_B);
fprintf('    Power rating     P_B_max = %.2f MW\n', res.P_B);
fprintf('    C-rate check:    P/E     = %.3f (limit: %.2f)\n', ...
    res.P_B/max(res.E_B, 0.01), params.gamma_B);

fprintf('\n  BTES:\n');
fprintf('    Thermal capacity E_TES     = %.1f MWhth\n', res.E_TES);
fprintf('    Thermal power    H_TES_max = %.2f MWth\n', res.H_TES);
fprintf('    C-rate check:    H/E       = %.3f (limit: %.2f)\n', ...
    res.H_TES/max(res.E_TES, 0.01), params.gamma_TES);

fprintf('\n  Heat Pump:\n');
fprintf('    Thermal capacity Q_HP_cap  = %.2f MWth\n', res.Q_HP);

%% Cost Breakdown
res.inv_B   = (params.CRF_B * params.C_EB * 1000 + params.C_om_B * 1000) * res.E_B;
res.inv_TES = (params.CRF_TES * params.C_ETES * 1000 + params.C_om_TES * 1000) * res.E_TES;
res.inv_HP  = (params.CRF_HP * params.C_HP_cap * 1000 + params.C_om_HP * 1000) * res.Q_HP;

res.P_buy_sol   = x_opt(idx.P_buy);
res.P_curt_sol  = x_opt(idx.P_curt);
res.H_unmet_sol = x_opt(idx.H_unmet);

res.cost_buy   = 365 * sum(price .* res.P_buy_sol * dt);
res.cost_curt  = 365 * sum(params.pen_curt * res.P_curt_sol * dt);
res.cost_unmet = 365 * sum(params.pen_unmet * res.H_unmet_sol * dt);
res.fval       = fval;

fprintf('\n  COST BREAKDOWN:\n');
fprintf('    BESS investment+O&M  = $%12.0f /yr\n', res.inv_B);
fprintf('    BTES investment+O&M  = $%12.0f /yr\n', res.inv_TES);
fprintf('    HP investment+O&M    = $%12.0f /yr\n', res.inv_HP);
fprintf('    Grid purchase        = $%12.0f /yr\n', res.cost_buy);
fprintf('    Curtailment penalty  = $%12.0f /yr\n', res.cost_curt);
fprintf('    Unmet heat penalty   = $%12.0f /yr\n', res.cost_unmet);
fprintf('    TOTAL                = $%12.0f /yr\n', fval);

%% Operational Profiles
res.P_ch_B    = x_opt(idx.P_ch_B);
res.P_dis_B   = x_opt(idx.P_dis_B);
res.W_B       = x_opt(idx.W_B);
res.H_ch_TES  = x_opt(idx.H_ch_TES);
res.H_dis_TES = x_opt(idx.H_dis_TES);
res.W_TES     = x_opt(idx.W_TES);
res.H_HP      = x_opt(idx.H_HP);
res.P_HP      = x_opt(idx.P_HP);
res.H_WH      = x_opt(idx.H_WH);

% SOC fractions
if res.E_B > 0
    res.SOC_B = res.W_B / res.E_B;
else
    res.SOC_B = zeros(T, 1);
end
if res.E_TES > 0
    res.SOC_TES = res.W_TES / res.E_TES;
else
    res.SOC_TES = zeros(T, 1);
end

% Store input profiles for plotting
res.P_wind  = P_wind;
res.P_hydro = P_hydro;
res.P_load  = P_load;
res.H_dem   = H_dem;
res.price   = price;

%% Daily Energy Summary
fprintf('\n  DAILY ENERGY SUMMARY:\n');
fprintf('    Total wind generation    = %.1f MWh\n',   sum(P_wind)*dt);
fprintf('    Total hydro generation   = %.1f MWh\n',   sum(P_hydro)*dt);
fprintf('    Total elec demand (w/DC) = %.1f MWh\n',   sum(P_load + params.P_DC)*dt);
fprintf('    Total heat demand        = %.1f MWhth\n', sum(H_dem)*dt);
fprintf('    Grid purchase            = %.1f MWh\n',   sum(res.P_buy_sol)*dt);
fprintf('    Curtailed energy         = %.1f MWh\n',   sum(res.P_curt_sol)*dt);
fprintf('    Unmet heat               = %.1f MWhth\n', sum(res.H_unmet_sol)*dt);
fprintf('    BESS charge total        = %.1f MWh\n',   sum(res.P_ch_B)*dt);
fprintf('    BESS discharge total     = %.1f MWh\n',   sum(res.P_dis_B)*dt);
fprintf('    BTES charge total        = %.1f MWhth\n', sum(res.H_ch_TES)*dt);
fprintf('    BTES discharge total     = %.1f MWhth\n', sum(res.H_dis_TES)*dt);
fprintf('    Waste heat utilized      = %.1f MWhth\n', sum(res.H_WH)*dt);
fprintf('    HP heat output           = %.1f MWhth\n', sum(res.H_HP)*dt);
fprintf('    HP elec consumption      = %.1f MWh\n',   sum(res.P_HP)*dt);

end
