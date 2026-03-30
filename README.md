# MILP Optimal Sizing of BESS and BTES for a Narvik Arctic Microgrid with AI Data Center

[![MATLAB](https://img.shields.io/badge/MATLAB-R2023b%2B-blue.svg)](https://www.mathworks.com/products/matlab.html)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![DOI](https://img.shields.io/badge/DOI-pending-lightgrey.svg)]()

Mixed-Integer Linear Programming (MILP) model for optimal co-sizing of **Battery Energy Storage Systems (BESS)** and **Borehole Thermal Energy Storage (BTES)** integrated with an AI data center in Narvik, Northern Norway. The model jointly optimizes electrical and thermal energy management on a modified IEEE 14-bus Arctic distribution grid.

---

## System Description

| Component | Specification |
|---|---|
| **Hakvik Hydro** | 9.9 MW reservoir (Nordkraft) |
| **Sildvik Hydro** | 63 MW reservoir (Statkraft) |
| **Nygardsfjellet Wind** | 32.2 MW (14 x Siemens SWT-2.3-93) |
| **AI Data Center** | 30 MW electrical load, 70% waste heat recovery |
| **BESS** | Li-ion candidates: 0 -- 27.3 MWh (Tesla Megapack) |
| **BTES** | Borehole Thermal Storage candidates: 0 -- 300 MWhth |
| **Heat Pump** | COP = 3.5, investment-optimized sizing |
| **District Heating** | Arctic winter demand, peak ~20 MWth |

### Architecture

```
                    ┌──────────────┐
    Wind 32.2 MW ──>│              │──> Electrical Load
   Hydro 72.9 MW ──>│  Electrical  │──> AI Data Center (30 MW)
    Grid Purchase ──>│   Balance    │──> BESS Charge
                    │              │──> Heat Pump
                    └──────────────┘
                           │
                    BESS Discharge
                           │
                    ┌──────────────┐
    Waste Heat ────>│              │──> District Heating
    HP Output ─────>│   Thermal    │──> Unmet Heat (penalty)
   BTES Discharge ─>│   Balance    │
                    │              │──> BTES Charge
                    └──────────────┘
```

## MILP Formulation

**Method:** Discrete candidate sizes eliminate bilinear SOC x E terms. Absolute stored energy W(t) [MWh] replaces fractional SOC. All constraints are linear -- pure MILP solved with `intlinprog`.

**Decision variables:** BESS/BTES candidate selection (binary), power/thermal ratings, charge/discharge profiles, SOC trajectories, heat pump operation, grid purchases, curtailment, and unmet heat.

**Objective:** Minimize annualized total cost = Investment (CRF) + O&M + 365 x daily operational costs.

**Key constraints:** Electrical/thermal power balance, SOC dynamics (asymmetric BTES efficiency), C-rate limits, no simultaneous charge/discharge (big-M), SOC bounds, cyclic SOC (relaxed tolerance), waste heat availability, heat pump capacity sizing.

## Project Structure

```
.
├── src/                              # MATLAB source code
│   ├── main_MILP.m                   # Main driver script (run this)
│   ├── setup_parameters.m            # Model parameters and candidates
│   ├── load_Narvik_data.m            # Data loading with CSV/synthetic fallback
│   ├── build_variables.m             # Decision variable indexing and bounds
│   ├── build_objective.m             # Objective function construction
│   ├── build_eq_constraints.m        # Equality constraints (balance, dynamics)
│   ├── build_ineq_constraints.m      # Inequality constraints (limits, big-M)
│   ├── extract_results.m             # Solution extraction and cost breakdown
│   ├── plot_results.m                # 6-panel results visualization
│   ├── plot_input_profiles.m         # Input data overview plots
│   └── MILP_BESS_BTES_Narvik.m       # Legacy single-file version
├── data/                             # Input data (CSV)
│   ├── ninja_wind_68.5039_17.8894_new.csv
│   ├── ninja_wind_68.4500_17.3900_corrected.csv
│   ├── NO4_prices_from_chart_image_15min.csv
│   ├── nordpool_NO4_2026.csv
│   ├── nordpool_NO4_15min_2026.csv
│   └── GUI_TOTAL_LOAD_DAYAHEAD_*.csv
├── docs/                             # Documentation and figures
├── CLAUDE.md                         # AI assistant guidance
├── CITATION.cff                      # Citation metadata
├── LICENSE                           # MIT License
└── README.md                         # This file
```

## Requirements

- **MATLAB** R2023b or later
- **Optimization Toolbox** (for `intlinprog`)

No additional toolboxes or external dependencies are required.

## Quick Start

```matlab
% Clone the repository
% Open MATLAB and navigate to the project root

% Run the optimization
run('src/main_MILP.m')
```

The script automatically:
1. Loads system parameters (BESS, BTES, heat pump, economic)
2. Reads CSV data or generates synthetic winter profiles as fallback
3. Builds the MILP (variables, objective, constraints)
4. Solves with `intlinprog` (600s time limit, 1% gap tolerance)
5. Displays optimal sizing, cost breakdown, and energy summary
6. Generates 7 diagnostic figures

## Key Parameters

| Parameter | Value | Unit | Source |
|---|---|---|---|
| BESS round-trip efficiency | 90.25% | -- | Tesla Megapack |
| BESS SOC limits | 20% -- 80% | fraction | Industry standard |
| BESS C-rate | 0.50 | 1/h | Megapack spec |
| BESS cost | 285 | $/kWh | Tesla Megapack (2024) |
| BTES charge efficiency | 90% | -- | HT-BTES factsheet |
| BTES discharge efficiency | 45% | -- | HT-BTES factsheet |
| BTES RTE | ~40.5% | -- | Derived |
| BTES cost | 0.60 | $/kWhth | HT-BTES factsheet |
| Heat pump COP | 3.5 | -- | Arctic average |
| Discount rate | 6% | -- | Standard |

## Data Sources

| Profile | Primary Source | Fallback |
|---|---|---|
| Wind | [Renewables.ninja](https://www.renewables.ninja/) (MERRA-2) | Synthetic winter CF profile |
| Price | [Nord Pool](https://www.nordpoolgroup.com/) NO4 day-ahead | Synthetic NO4 winter pattern |
| Load | [ENTSO-E Transparency](https://transparency.entsoe.eu/) (NO4) | Synthetic Nordic load pattern |
| Heat | [When2Heat](https://data.open-power-system-data.org/) (OPSD) | Degree-day method |
| Hydro | [ENTSO-E](https://transparency.entsoe.eu/) generation (NO4) | Price-responsive dispatch model |

## Example Output

```
OPTIMAL SIZING RESULTS
  BESS:  E_B = 15.6 MWh, P_B_max = 7.80 MW
  BTES:  E_TES = 100.0 MWhth, H_TES_max = 20.00 MWth
  HP:    Q_HP_cap = 12.50 MWth

  COST BREAKDOWN:
    BESS investment+O&M  = $   xxx,xxx /yr
    BTES investment+O&M  = $    xx,xxx /yr
    HP investment+O&M    = $ x,xxx,xxx /yr
    Grid purchase        = $ x,xxx,xxx /yr
    TOTAL                = $ x,xxx,xxx /yr
```

## Authors

- **Afshin Nazari** -- UiT The Arctic University of Norway

## License

This project is licensed under the MIT License -- see the [LICENSE](LICENSE) file for details.

## Citation

If you use this code in your research, please cite:

```bibtex
@software{nazari2026milp_bess_btes,
  author    = {Nazari, Afshin},
  title     = {{MILP Optimal Sizing of BESS and BTES for a Narvik Arctic
                Microgrid with AI Data Center}},
  year      = {2026},
  url       = {https://github.com/afshinnazari1985/afshinnazari1985}
}
```

## Acknowledgements

- UiT The Arctic University of Norway
- Nordkraft AS (Hakvik hydro data)
- Renewables.ninja, Nord Pool, ENTSO-E, Open Power System Data (public datasets)
