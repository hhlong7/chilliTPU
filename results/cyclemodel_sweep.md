Sweep: 50 mixes per setting, seed 1, 10800 runs, 27 s

All numbers are cycle-model ESTIMATES (sw/py/cyclemodel.py), not measurements.

Speedup = sequential makespan / policy makespan (>1 is better). Geomean over all mixes; min/max in brackets.

### Overall

| shadow | feed | equal (paper) | proportional (ours) | prop beats equal | util seq → prop |
|---|---|---|---|---|---|
| off | A | 0.65× [0.28, 1.31] | 0.69× [0.26, 1.31] | 63% | 52.9% → 35.0% |
| off | B | 1.10× [0.67, 1.48] | 1.13× [0.67, 1.68] | 56% | 52.9% → 58.4% |
| on | A | 0.58× [0.25, 1.04] | 0.61× [0.24, 1.03] | 58% | 65.0% → 39.9% |
| on | B | 1.05× [0.60, 1.45] | 1.08× [0.60, 1.68] | 67% | 65.0% → 69.9% |

### Proportional speedup by workload (shadow on)

| kind | tenants | feed | batch 1 | batch 8 | batch 32 |
|---|---|---|---|---|---|
| random | 2 | A | 0.83× | 0.80× | 0.80× |
| random | 2 | B | 1.01× | 1.00× | 1.03× |
| random | 4 | A | 0.53× | 0.48× | 0.49× |
| random | 4 | B | 1.02× | 1.00× | 1.03× |
| similar | 2 | A | 0.84× | 0.78× | 0.65× |
| similar | 2 | B | 1.06× | 1.10× | 1.07× |
| similar | 4 | A | 0.56× | 0.41× | 0.36× |
| similar | 4 | B | 1.11× | 1.23× | 1.24× |
| zoo | 2 | A | 0.90× | 0.79× | 0.73× |
| zoo | 2 | B | 1.06× | 1.08× | 1.06× |
| zoo | 4 | A | 0.56× | 0.43× | 0.41× |
| zoo | 4 | B | 1.10× | 1.13× | 1.14× |

### Shared-feed cap (Milestone 1 question)

- shadow off: proportional gets 0.69× with a shared feed (A) vs 1.13× with per-partition feed (B). With a shared feed, partitioning is 31% SLOWER than running the networks one at a time.
- shadow on: proportional gets 0.61× with a shared feed (A) vs 1.08× with per-partition feed (B). With a shared feed, partitioning is 39% SLOWER than running the networks one at a time.
