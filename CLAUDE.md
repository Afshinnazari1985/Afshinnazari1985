# CLAUDE.md

Guidance for AI assistants working in this repository.

---

## Repository Overview

- **Owner:** Afshin Nazari (UiT The Arctic University of Norway)
- **Project:** MILP Optimal Sizing & Energy Management of BESS and BTES for a Narvik Arctic Grid with AI Data Center
- **Language:** MATLAB (Optimization Toolbox required — `intlinprog`)

## System Description

Modified IEEE 14-bus grid in Narvik, Norway. Key components:

| Component | Specification |
|-----------|---------------|
| Hakvik Hydro | 9.9 MW reservoir (Nordkraft) |
| Batsvatn Hydro | 30 MW reservoir (user-defined) |
| Sildvik Hydro | 63 MW reservoir (Statkraft) |
| Nygardsfjellet Wind | 32.2 MW (14 x Siemens 2.3 MW) |
| AI Data Center | 20 MW electrical load, 70% waste heat recovery |
| BESS | Li-ion (Tesla Megapack candidates: 0–27.3 MWh) |
| BTES | Borehole Thermal Energy Storage (candidates: 0–300 MWhth) |
| Heat Pump | COP = 3, unlimited sizing |
| District Heating | Arctic winter demand, peak ~20 MWth |

## Project Structure

```
/
├── src/                              # MATLAB source code
│   ├── main_MILP.m                   # Main driver script (run this)
│   ├── setup_parameters.m            # Model parameters and candidates
│   ├── load_Narvik_data.m            # Data loading with CSV/synthetic fallback
│   ├── build_variables.m             # Decision variable indexing and bounds
│   ├── build_objective.m             # Objective function construction
│   ├── build_eq_constraints.m        # Equality constraints
│   ├── build_ineq_constraints.m      # Inequality constraints
│   ├── extract_results.m             # Solution extraction and cost breakdown
│   ├── plot_results.m                # Results visualization
│   ├── plot_input_profiles.m         # Input data overview plots
│   └── MILP_BESS_BTES_Narvik.m       # Legacy single-file version
├── data/                             # Input CSV data files
│   ├── ninja_wind_*.csv              # Renewables.ninja wind data
│   ├── NO4_prices_*.csv              # Nord Pool electricity prices
│   ├── nordpool_NO4_*.csv            # Nord Pool price data
│   └── GUI_TOTAL_LOAD_*.csv          # ENTSO-E load data
├── docs/                             # Documentation and figures
├── CLAUDE.md                         # This file
├── CITATION.cff                      # Citation metadata
├── LICENSE                           # MIT License
└── README.md                         # Project documentation
```

CSV data files are optional — the code falls back to synthetic profiles if absent.

## MILP Formulation Summary

**Method:** Discrete candidate sizes eliminate bilinear SOC * E terms. Absolute stored energy W(t) [MWh] replaces fractional SOC. All constraints are linear → pure MILP.

**Decision variables** (packed into single vector `x` for `intlinprog`):
- `y_B(s)` — binary: BESS candidate selection (exactly one selected)
- `y_TES(s)` — binary: BTES candidate selection (exactly one selected)
- `P_B_max`, `H_TES_max` — continuous: power/thermal ratings [MW]
- `P_ch_B(t)`, `P_dis_B(t)`, `W_B(t)` — BESS charge/discharge/energy
- `H_ch_TES(t)`, `H_dis_TES(t)`, `W_TES(t)` — BTES charge/discharge/energy
- `z_ch_B(t)`, `z_dis_B(t)`, `z_ch_TES(t)`, `z_dis_TES(t)` — binary indicators
- `H_HP(t)`, `P_HP(t)`, `H_WH(t)` — heat pump and waste heat
- `P_buy(t)`, `P_curt(t)`, `H_unmet(t)` — grid purchase, curtailment, unmet heat

**Objective:** Minimize annualized total cost = Investment (CRF) + O&M + 365 * daily operational costs.

**Key constraints:** Electrical/thermal power balance, SOC dynamics, C-rate limits, no simultaneous charge/discharge (big-M), SOC bounds, cyclic SOC (relaxed), waste heat availability.

## Running the Code

Requires MATLAB with Optimization Toolbox.

```matlab
% Open MATLAB, navigate to project root, then:
run('src/main_MILP.m')
```

Solver settings: `intlinprog` with 600s time limit, 1% relative gap tolerance, advanced preprocessing.

## Known Issues (Code Review — 2026-03-03)

### CRITICAL — Prevents Execution

1. **Function `load_Narvik_data()` defined mid-script.** MATLAB requires local functions at the END of a script file. Current placement causes a syntax error. **Fix:** Move the function definition block to the end of the file, or extract to `load_Narvik_data.m`.

### BUGS — Incorrect Results

2. **Hydro dispatch formula mismatch.** `dispatch_frac = 0.20 + 0.50 * price_norm` yields 20%–70%, but the comment says "60% to 90%". Earlier commented-out profiles used 0.55–0.90 range. **Fix:** Change to `dispatch_frac = 0.60 + 0.30 * price_norm`.

3. **Last-period free energy exploit.** SOC dynamics cover `t=1:T-1`, so `P_ch_B(T)` and `P_dis_B(T)` participate in the power balance but have zero SOC impact. The optimizer can discharge at `t=T` for free electricity. **Fix:** Add `W_B(T+1)` state variable with dynamics for `t=T`, apply cyclic constraint to `W_B(T+1)`. Same for BTES.

### INCONSISTENCIES

4. **File header omits Sildvik (63 MW).** Header lists only Hakvik + Batsvatn = 39.9 MW; code uses 102.9 MW total hydro.

5. **`T=24` defined in both script preamble and inside `load_Narvik_data()`.** Redundant; could silently diverge.

### NUMERICAL

6. **BigM variable bounds too large.** `BigM_elec = 1e6` MW for upper bounds on continuous variables (actual values ~10–100 MW). Use physically meaningful bounds instead.

7. **Redundant waste heat inequality constraints.** Already enforced by `ub(idx.H_WH) = H_WH_avail`.

### VERIFIED CORRECT

- SOC dynamics signs (charge adds, discharge removes with efficiency)
- Electrical and thermal power balance equations
- Heat pump coupling (COP * P_HP = H_HP)
- Candidate selection (sum y = 1)
- C-rate, big-M indicator, no-simultaneous-charge/discharge constraints
- SOC bounds via candidate linkage
- Cyclic SOC with tolerance
- Objective function (CRF annualization + O&M + operational)
- Variable indexing, integer variable IDs, zero-candidate handling
- Cost breakdown in results section

## Key Data Sources

| Profile | Primary Source | Fallback |
|---------|---------------|----------|
| Wind | Renewables.ninja (MERRA-2) | Synthetic winter CF profile |
| Price | Nord Pool NO4 day-ahead | Synthetic NO4 winter pattern |
| Load | ENTSO-E Transparency (NO4) | Synthetic Nordic load pattern |
| Heat | When2Heat (Open Power System Data) | Degree-day method (yr.no temps) |
| Hydro | ENTSO-E generation (NO4) | Price-responsive dispatch model |

## Key Parameters

| Parameter | Value | Unit | Source |
|-----------|-------|------|--------|
| BESS efficiency | 0.95 | one-way | Tesla Megapack |
| BESS SOC limits | 0.20–0.80 | fraction | Table 2 |
| BESS C-rate | 0.50 | 1/h | Megapack spec |
| BESS cost | 285 | $/kWh | Tesla Megapack Design |
| BESS lifetime | 15 | years | Tesla Megapack Design |
| BTES efficiency | 0.85 | one-way | HT-BTES factsheet |
| BTES SOC limits | 0.10–0.90 | fraction | HT-BTES factsheet |
| BTES C-rate | 0.20 | 1/h | Arctic assumption |
| BTES cost | 0.60 | $/kWhth | HT-BTES factsheet |
| BTES lifetime | 30 | years | HT-BTES factsheet |
| Heat pump COP | 3.0 | — | Arctic average |
| Waste heat coeff | 0.70 | fraction | Assumption |
| Discount rate | 6% | — | Standard |
| Curtailment penalty | 50 | $/MWh | Assumption |
| Unmet heat penalty | 2000 | $/MWhth | Literature |

## Conventions for AI Assistants

- **MATLAB style:** No classes/OOP — single-script procedural style with index structs.
- **Units:** Electrical in MW/MWh, thermal in MWth/MWhth, cost in $/yr.
- **Commented-out code:** Large blocks of commented alternatives exist for reference; do not delete without asking.
- **Data notes:** Comments with "NEED TO LOOK FOR REAL DATA" indicate parameters awaiting validation.
- Always verify constraint signs against the mathematical formulation comments above each block.
- Test with T=24 before attempting T=8760 (annual horizon).

## Git Workflow

- AI branches: `claude/<task-slug>-<session-id>`
- Commit format: `<type>: <summary>` (types: `feat`, `fix`, `docs`, `refactor`)
- Push: `git push -u origin <branch>`, retry on network failure (4x exponential backoff).

---

*Last updated: 2026-03-03 — Full project analysis and code review.*
