"""Write .hex test vectors and expected outputs for the testbenches and the board.

Output: vectors/<case>/x.hex, w.hex, bias.hex, y_expected.hex, meta.json (+ meta.txt for SV).
Format (PROJECT_PLAN.md section 5): one value per line, two's-complement hex,
zero-padded to the type width, row-major.

Edge cases to include: -128 / 127 extremes, all zeros, M/K/N not multiples of
the array size, K > ROWS, N > COLS. Random cases use fixed, printed seeds.

Status: SKELETON.
"""
import sys


def main() -> int:
    print("vecgen.py: not implemented yet (Milestone 1)", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
