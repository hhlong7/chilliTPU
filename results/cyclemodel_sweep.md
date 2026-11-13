Sweep: 50 mixes per setting, seed 1, 10800 runs, 38 s

All numbers are cycle-model ESTIMATES (sw/py/cyclemodel.py), not measurements.

Speedup = sequential makespan / policy makespan (>1 is better). Geomean over all mixes; min/max in brackets.

### Overall

| shadow | feed | equal (paper) | proportional (ours) | prop beats equal | util seq → prop |
|---|---|---|---|---|---|
| off | A | 0.72× [0.29, 1.30] | 0.75× [0.27, 1.30] | 62% | 46.1% → 32.2% |
| off | B | 1.10× [0.67, 1.48] | 1.13× [0.67, 1.68] | 64% | 46.1% → 50.7% |
| on | A | 0.61× [0.25, 1.04] | 0.64× [0.27, 1.01] | 58% | 60.1% → 38.3% |
| on | B | 1.04× [0.60, 1.44] | 1.07× [0.60, 1.68] | 63% | 60.1% → 64.4% |

### Proportional speedup by workload (shadow on)

| kind | tenants | feed | batch 1 | batch 8 | batch 32 |
|---|---|---|---|---|---|
| random | 2 | A | 0.83× | 0.80× | 0.80× |
| random | 2 | B | 1.01× | 1.00× | 1.03× |
| random | 4 | A | 0.53× | 0.48× | 0.49× |
| random | 4 | B | 1.02× | 1.00× | 1.03× |
| similar | 2 | A | 0.95× | 0.81× | 0.66× |
| similar | 2 | B | 1.05× | 1.09× | 1.09× |
| similar | 4 | A | 0.73× | 0.43× | 0.36× |
| similar | 4 | B | 1.08× | 1.23× | 1.24× |
| zoo | 2 | A | 0.96× | 0.82× | 0.73× |
| zoo | 2 | B | 1.03× | 1.06× | 1.06× |
| zoo | 4 | A | 0.74× | 0.44× | 0.43× |
| zoo | 4 | B | 1.05× | 1.13× | 1.15× |

### Shared-feed cap (Milestone 1 question)

- shadow off: proportional gets 0.75× with a shared feed (A) vs 1.13× with per-partition feed (B). With a shared feed, partitioning is 25% SLOWER than running the networks one at a time.
- shadow on: proportional gets 0.64× with a shared feed (A) vs 1.07× with per-partition feed (B). With a shared feed, partitioning is 36% SLOWER than running the networks one at a time.
