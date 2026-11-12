#!/usr/bin/env bash
# run_tests.sh <tb> <sim-binary> [verilator|xsim]
# Runs every "<test> <seed>" line in tb/<tb>/tests.txt, checks for a PASS line,
# and prints a summary. Exit status is non-zero if any test fails.
set -u
tb="$1"; simv="$2"; sim="${3:-verilator}"
tests="tb/$tb/tests.txt"
logdir="build/$tb"
mkdir -p "$logdir"

if ! grep -qvE '^\s*(#|$)' "$tests" 2>/dev/null; then
  echo "SKIP $tb: no tests listed in $tests"
  exit 0
fi

pass=0; fail=0
while read -r test seed _; do
  [[ -z "${test:-}" || "$test" == \#* ]] && continue
  seed="${seed:-1}"
  log="$logdir/${test}_${seed}.log"
  if [[ "$sim" == "xsim" ]]; then
    (cd "$logdir/xsim" && xsim "$simv" -R -testplusarg "UVM_TESTNAME=$test" -testplusarg "SEED=$seed" \
       -sv_seed "$seed") > "$log" 2>&1
  else
    "$simv" "+UVM_TESTNAME=$test" "+SEED=$seed" "+verilator+seed+$seed" "+UVM_NO_RELNOTES" > "$log" 2>&1
  fi
  rc=$?
  if [[ $rc -eq 0 ]] && grep -q "^PASS " "$log" && ! grep -qE "^UVM_(ERROR|FATAL) @" "$log"; then
    pass=$((pass+1)); grep "^PASS " "$log"
  else
    fail=$((fail+1)); echo "FAIL $tb.$test seed=$seed (exit=$rc, log: $log)"
    grep -E "^FAIL |^UVM_(ERROR|FATAL) @|Assertion failed|%Error" "$log" | head -5 | sed 's/^/    /'
  fi
done < "$tests"

echo "== $tb: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
