#!/usr/bin/env bash
# Out-of-context Vivado synthesis for the PE and/or systolic array.
set -euo pipefail

usage() {
  echo "Usage: bash scripts/synth.sh [all|pe|systolic_array]"
  echo "Defaults to both tops. Outputs: build/synth/<top>/"
  echo "Overrides: VIVADO, FPGA_PART (xc7z020clg400-1), CLK_PERIOD_NS (10)."
}

if (( $# > 1 )); then usage >&2; exit 2; fi
case "${1:-all}" in
  all|pe|systolic_array) target="${1:-all}" ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

vivado="${VIVADO:-vivado}"
if [[ -z "${VIVADO:-}" ]] && ! command -v "$vivado" >/dev/null 2>&1; then
  # Standard Windows installations, including this project's MSYS2 setup.
  candidates=()
  if [[ -n "${XILINX_VIVADO:-}" ]]; then
    xilinx_dir="$XILINX_VIVADO"
    if command -v cygpath >/dev/null 2>&1; then xilinx_dir="$(cygpath -u "$xilinx_dir")"; fi
    candidates+=("$xilinx_dir/bin/vivado" "$xilinx_dir/bin/vivado.bat")
  fi
  candidates+=(/c/AMDDesignTools/*/Vivado/bin/vivado.bat /c/Xilinx/Vivado/*/bin/vivado.bat)
  for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate" ]]; then vivado="$candidate"; break; fi
  done
fi
# MSYS2 can launch .bat files even though command -v does not mark them executable.
if ! command -v "$vivado" >/dev/null 2>&1 && [[ ! -f "$vivado" ]]; then
  echo "ERROR: Vivado not found. Set VIVADO to vivado or vivado.bat, or use a Vivado terminal." >&2
  exit 127
fi

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$repo_root"
mkdir -p build/synth
echo "== Synthesizing $target with Vivado (log: build/synth/console.log)"
if ! "$vivado" -mode batch -nojournal -notrace -log build/synth/vivado.log \
    -source scripts/synth.tcl -tclargs "$target" "${FPGA_PART:-xc7z020clg400-1}" \
    "${CLK_PERIOD_NS:-10}" > build/synth/console.log 2>&1; then
  tail -n 30 build/synth/console.log >&2
  echo "FAIL synthesis (see build/synth/console.log)" >&2
  exit 1
fi

echo "PASS synthesis $target"
echo "Checkpoints, netlists, and reports: $repo_root/build/synth/<top>/"
echo "Timing is an unplaced synthesis estimate."
