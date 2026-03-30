function plot_results(res, params, T)
% PLOT_RESULTS  Generate 6 result figures from the optimization solution.

hours = 1:T;

%% Figure 1: Electrical Power Balance
figure('Name', 'Electrical Balance', 'Position', [50 400 900 500]);

supply = [res.P_wind, res.P_hydro, res.P_dis_B, max(res.P_buy_sol, 0)];
bar(hours, supply, 'stacked'); hold on;
P_total_dem = res.P_load + params.P_DC + res.P_HP + res.P_ch_B;
plot(hours, P_total_dem, 'k-o', 'LineWidth', 2, 'MarkerSize', 4);
hold off;

xlabel('Hour'); ylabel('Power [MW]');
title('Electrical Power Balance — Narvik System');
legend('Wind', 'Hydro', 'BESS Discharge', 'Grid Purchase', 'Total Demand', ...
       'Location', 'northwest');
grid on; xlim([0.5 T+0.5]);

%% Figure 2: BESS Operation
figure('Name', 'BESS Operation', 'Position', [50 50 900 450]);

subplot(2,1,1);
bar(hours, res.P_ch_B, 'FaceColor', [0.2 0.6 0.2]); hold on;
bar(hours, -res.P_dis_B, 'FaceColor', [0.8 0.2 0.2]); hold off;
ylabel('Power [MW]');
title(sprintf('BESS Operation (E_B = %.0f MWh, P_{max} = %.1f MW)', res.E_B, res.P_B));
legend('Charge', 'Discharge', 'Location', 'best');
grid on; xlim([0.5 T+0.5]);

subplot(2,1,2);
plot(hours, res.SOC_B*100, 'b-o', 'LineWidth', 2, 'MarkerSize', 4); hold on;
yline(params.SOC_B_min*100, 'r--', 'SOC_{min}', 'LineWidth', 1.5);
yline(params.SOC_B_max*100, 'r--', 'SOC_{max}', 'LineWidth', 1.5);
hold off;
xlabel('Hour'); ylabel('SOC [%]');
title('BESS State of Charge');
grid on; xlim([0.5 T+0.5]); ylim([0 100]);

%% Figure 3: BTES Operation
figure('Name', 'BTES Operation', 'Position', [500 50 900 450]);

subplot(2,1,1);
bar(hours, res.H_ch_TES, 'FaceColor', [0.9 0.5 0.1]); hold on;
bar(hours, -res.H_dis_TES, 'FaceColor', [0.1 0.5 0.9]); hold off;
ylabel('Thermal Power [MWth]');
title(sprintf('BTES Operation (E_{TES} = %.0f MWhth, H_{max} = %.1f MWth)', ...
    res.E_TES, res.H_TES));
legend('Charge', 'Discharge', 'Location', 'best');
grid on; xlim([0.5 T+0.5]);

subplot(2,1,2);
plot(hours, res.SOC_TES*100, 'm-o', 'LineWidth', 2, 'MarkerSize', 4); hold on;
yline(params.SOC_TES_min*100, 'r--', 'SOC_{min}', 'LineWidth', 1.5);
yline(params.SOC_TES_max*100, 'r--', 'SOC_{max}', 'LineWidth', 1.5);
hold off;
xlabel('Hour'); ylabel('SOC [%]');
title('BTES State of Charge');
grid on; xlim([0.5 T+0.5]); ylim([0 100]);

%% Figure 4: Thermal Balance
figure('Name', 'Thermal Balance', 'Position', [100 200 900 450]);

supply_th = [res.H_HP, res.H_WH, res.H_dis_TES, res.H_unmet_sol];
bar(hours, supply_th, 'stacked'); hold on;
plot(hours, res.H_dem + res.H_ch_TES, 'k-o', 'LineWidth', 2, 'MarkerSize', 4);
hold off;
xlabel('Hour'); ylabel('Thermal Power [MWth]');
title('Thermal (Heat) Balance — Narvik District Heating');
legend('HP Output', 'Waste Heat', 'BTES Discharge', 'Unmet Heat', ...
       'Demand + BTES Charge', 'Location', 'northwest');
grid on; xlim([0.5 T+0.5]);

%% Figure 5: Price & Grid Purchase
figure('Name', 'Price vs Grid', 'Position', [200 300 900 400]);

yyaxis left;
P_buy_plot = max(res.P_buy_sol, 0);
bar(hours, P_buy_plot, 'FaceColor', [0.4 0.7 0.9], 'FaceAlpha', 0.7);
ylabel('Grid Purchase [MW]');
ylim([0, max(P_buy_plot) + 1]);

yyaxis right;
plot(hours, res.price, 'r-s', 'LineWidth', 2, 'MarkerSize', 5);
ylabel('Price [$/MWh]');

xlabel('Hour');
title('Grid Purchase vs. Electricity Price');
legend('Grid Purchase', 'Elec Price', 'Location', 'best');
grid on; xlim([0.5 T+0.5]);

%% Figure 6: Cost Breakdown Pie
figure('Name', 'Cost Breakdown', 'Position', [300 250 500 400]);

costs  = [res.inv_B, res.inv_TES, res.inv_HP, res.cost_buy, res.cost_curt, res.cost_unmet];
labels = {'BESS Inv+O&M', 'BTES Inv+O&M', 'HP Inv+O&M', ...
          'Grid Purchase', 'Curtailment', 'Unmet Heat'};

nonzero = costs > 0.01;
if any(nonzero)
    pie(costs(nonzero), labels(nonzero));
    title('Annualized Cost Breakdown');
else
    text(0.5, 0.5, 'All costs = $0', 'HorizontalAlignment', 'center');
end

fprintf('\n==============================================================\n');
fprintf('  Optimization complete. 7 figures generated.\n');
fprintf('==============================================================\n');

end
