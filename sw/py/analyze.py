"""Turn sim logs, board UART logs, and Vivado reports into tables and plots for the report.

golden.py and vecgen.py prove the hardware computes the right answer.
cyclemodel.py predicts how fast it should be and which design is worth building.
analyze.py puts the prediction next to what the board actually measured.

Rule: every table/plot column is labeled MEASURED or ESTIMATED (PROJECT_PLAN.md section 8).
Status: SKELETON.
"""

import sys


def main() -> int:
    print("analyze.py: not implemented yet (Milestone 5)", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
