#!/usr/bin/env bash
# Lint the PE and systolic array without compiling the UVM testbenches.
set -uo pipefail

usage() {
  echo "Usage: bash scripts/lint.sh [all|pe|systolic_array]"
  echo "Defaults to both modules. Set VERILATOR to override the executable."
}

if (( $# > 1 )); then
  usage >&2
  exit 2
fi

case "${1:-all}" in
  all) tops=(pe systolic_array) ;;
  pe|systolic_array) tops=("$1") ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

verilator="${VERILATOR:-verilator}"
if ! command -v "$verilator" >/dev/null 2>&1; then
  echo "ERROR: Verilator not found. Install it or set VERILATOR to its executable." >&2
  exit 127
fi

# Resolve sources relative to the script, regardless of the caller's directory.
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1
cd -- "$repo_root" || exit 1

status=0
for top in "${tops[@]}"; do
  sources=(rtl/pkg/dnn_pkg.sv rtl/pe.sv)
  if [[ "$top" == systolic_array ]]; then
    sources+=(rtl/systolic_array.sv)
  fi

  echo "== Linting $top"
  # Other modules use package constants that this individual top does not need.
  # All other -Wall warnings remain enabled and cause a nonzero exit status.
  if "$verilator" --lint-only --sv -Wall -Wno-UNUSEDPARAM \
      --top-module "$top" "${sources[@]}"; then
    echo "PASS $top"
  else
    echo "FAIL $top"
    status=1
  fi
done

exit "$status"
