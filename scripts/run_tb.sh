#!/usr/bin/env bash
# Run the standalone array regression using Icarus Verilog, without UVM.
set -euo pipefail

usage() {
  echo "Usage: bash scripts/run_tb.sh [all | ROWS COLS [DATA_W [PSUM_W]]]"
  echo "Default: six cases including 12x12, 1x1, and a 4-bit datapath."
  echo "Example: bash scripts/run_tb.sh 12 12"
  echo "Overrides: IVERILOG, VVP. Logs: build/systolic_array/<configuration>/"
}

if (( $# == 1 )) && [[ "$1" == -h || "$1" == --help ]]; then usage; exit 0; fi
if (( $# == 0 )) || { (( $# == 1 )) && [[ "$1" == all ]]; }; then
  configs=("3 2 8 32" "1 1 8 32" "1 4 8 32" "4 1 8 32" "12 12 8 32" "2 3 4 16")
elif (( $# >= 2 && $# <= 4 )); then
  for value in "$@"; do
    if [[ ! "$value" =~ ^[1-9][0-9]*$ ]]; then
      echo "ERROR: dimensions and widths must be positive decimal integers." >&2
      exit 2
    fi
  done
  data_w="${3:-8}"
  psum_w="${4:-32}"
  # The directed vectors and int reference model support these widths.
  if (( data_w < 4 || data_w > 8 || psum_w < 2*data_w || psum_w > 32 )); then
    echo "ERROR: directed test requires 4 <= DATA_W <= 8 and 2*DATA_W <= PSUM_W <= 32." >&2
    exit 2
  fi
  configs=("$1 $2 $data_w $psum_w")
else
  usage >&2
  exit 2
fi

iverilog="${IVERILOG:-iverilog}"
vvp="${VVP:-vvp}"
for tool in "$iverilog" "$vvp"; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "ERROR: $tool not found. Install Icarus Verilog or set IVERILOG and VVP." >&2
    exit 127
  fi
done

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$repo_root"
top=tb_systolic_array_directed
sources=(rtl/pkg/dnn_pkg.sv rtl/pe.sv rtl/systolic_array.sv tb/systolic_array/tb_directed.sv)

run_case() {
  local rows="$1" cols="$2" data_w="$3" psum_w="$4"
  local out_dir="build/systolic_array/${rows}x${cols}_d${data_w}_p${psum_w}"
  mkdir -p "$out_dir"
  echo "== TB ${rows}x${cols}, DATA_W=$data_w, PSUM_W=$psum_w"
  if ! "$iverilog" -g2012 -s "$top" \
      "-P$top.ROWS=$rows" "-P$top.COLS=$cols" \
      "-P$top.DATA_W=$data_w" "-P$top.PSUM_W=$psum_w" \
      -o "$out_dir/sim.vvp" "${sources[@]}" > "$out_dir/compile.log" 2>&1; then
    tail -n 20 "$out_dir/compile.log" >&2
    echo "FAIL compile (see $out_dir/compile.log)" >&2
    return 1
  fi
  if ! "$vvp" "$out_dir/sim.vvp" > "$out_dir/run.log" 2>&1; then
    tail -n 20 "$out_dir/run.log" >&2
    echo "FAIL simulation (see $out_dir/run.log)" >&2
    return 1
  fi
  if ! grep -q '^PASS systolic_array[.]directed ' "$out_dir/run.log"; then
    cat "$out_dir/run.log" >&2
    echo "FAIL: simulation did not print PASS" >&2
    return 1
  fi
  grep '^PASS systolic_array[.]directed ' "$out_dir/run.log"
}

status=0
for config in "${configs[@]}"; do
  read -r rows cols data_w psum_w <<< "$config"
  run_case "$rows" "$cols" "$data_w" "$psum_w" || status=1
done
if (( status == 0 )); then echo "== TB PASS"; else echo "== TB FAIL"; fi
exit "$status"
