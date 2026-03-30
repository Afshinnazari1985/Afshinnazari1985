function plot_input_profiles(P_wind, P_hydro, P_load, H_dem, price, T, P_DC)
% PLOT_INPUT_PROFILES  Plot the 6-panel input data overview figure.
hours = 1:T;

figure('Name', 'Input Data Profiles', 'Position', [50 100 1000 700]);

subplot(3,2,1);
plot(hours, P_wind, 'b-o', 'LineWidth', 1.5, 'MarkerSize', 4);
xlabel('Hour'); ylabel('MW');
title('Wind Generation (Nygårdsfjellet)');
grid on; xlim([1 T]);

subplot(3,2,2);
plot(hours, P_hydro, 'g-s', 'LineWidth', 1.5, 'MarkerSize', 4);
xlabel('Hour'); ylabel('MW');
title('Hydro Generation (Håkvik + Båtsvatn)');
grid on; xlim([1 T]);

subplot(3,2,3);
plot(hours, P_load, 'k-^', 'LineWidth', 1.5, 'MarkerSize', 4);
xlabel('Hour'); ylabel('MW');
title('Electrical Load (excl. Data Center)');
grid on; xlim([1 T]);

subplot(3,2,4);
plot(hours, H_dem, 'r-d', 'LineWidth', 1.5, 'MarkerSize', 4);
xlabel('Hour'); ylabel('MWth');
title('District Heating Demand');
grid on; xlim([1 T]);

subplot(3,2,5);
plot(hours, price, 'm-v', 'LineWidth', 1.5, 'MarkerSize', 4);
xlabel('Hour'); ylabel('$/MWh');
title('Electricity Price (NO4)');
grid on; xlim([1 T]);

subplot(3,2,6);
bar(hours, [P_wind, P_hydro], 'stacked'); hold on;
plot(hours, P_load + P_DC, 'k--', 'LineWidth', 2);
xlabel('Hour'); ylabel('MW');
title('Supply vs. Demand Overview');
legend('Wind', 'Hydro', 'Load+DC', 'Location', 'best');
grid on; xlim([0.5 T+0.5]);

sgtitle('Narvik System — Input Data Profiles (Representative Winter Day)');

end
