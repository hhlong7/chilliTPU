"""Cycle-level model of the partitioned systolic array (Milestone 1).

Must model the feed port under two assumptions:
  (A) shared feed port: one tenant's input stream on the row wires at a time
  (B) per-partition feed injection
and report total cycles and column utilization for:
  sequential baseline, equal split (paper), proportional split (ours)
over randomized layer mixes and arrival times with fixed seeds.

The result goes in results/cyclemodel.md and decides the headline improvement.
Status: SKELETON.
"""
import sys


def main() -> int:
    print("cyclemodel.py: not implemented yet (Milestone 1)", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
