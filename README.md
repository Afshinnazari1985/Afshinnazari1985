# MILP Optimal Sizing & Energy Management of BESS and BTES for a Narvik Arctic Grid with AI Data Center

Mixed-Integer Linear Programming (MILP) model for co-optimizing Battery Energy Storage (BESS) and Borehole Thermal Energy Storage (BTES) sizing and operation on a modified IEEE 14-bus grid in Narvik, Norway.

## System Overview

| Component | Specification |
|-----------|---------------|
| Hakvik Hydro | 9.9 MW reservoir (Nordkraft) |
| Batsvatn Hydro | 30 MW reservoir |
| Sildvik Hydro | 63 MW reservoir (Statkraft) |
| Nygardsfjellet Wind | 32.2 MW (14 × Siemens 2.3 MW) |
| AI Data Center | 20 MW load, 70% waste heat recovery |
| BESS | Li-ion candidates: 0–27.3 MWh |
| BTES | Borehole candidates: 0–300 MWhth |
| Heat Pump | COP = 3 |
| District Heating | Arctic demand, peak ~20 MWth |

## Requirements

- MATLAB with Optimization Toolbox (`intlinprog`)

## Usage

```matlab
run('main_MILP.m')
```

## Project Structure

```
main_MILP.m                  % Entry point
load_Narvik_data.m           % Load/generate input profiles
setup_parameters.m           % System and cost parameters
build_variables.m            % Decision variable indexing and bounds
build_objective.m            % Cost function coefficients
build_eq_constraints.m       % Power/thermal balance, SOC dynamics
build_ineq_constraints.m     % C-rate, big-M, SOC bound constraints
extract_results.m            % Unpack solver output
plot_results.m               % Visualization
plot_input_profiles.m        % Input data plots
```

## Data Sources

| Profile | Source | Fallback |
|---------|--------|----------|
| Wind | Renewables.ninja (MERRA-2) | Synthetic winter CF |
| Price | Nord Pool NO4 day-ahead | Synthetic pattern |
| Load | ENTSO-E Transparency (NO4) | Synthetic Nordic load |
| Hydro | ENTSO-E generation (NO4) | Price-responsive dispatch |

## Author

Afshin Nazari — UiT The Arctic University of Norway
