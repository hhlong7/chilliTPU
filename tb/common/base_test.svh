// base_test.svh - base class for every test.
// Status: SKELETON (included from tb_common_pkg.sv).
//
// TODO:
//   - read +SEED plusarg and print it at start
//   - global timeout (uvm_root::set_timeout)
//   - report_phase: print exactly one 'PASS <tb>.<test> seed=<s>' or 'FAIL ...' line
//     based on UVM_ERROR/UVM_FATAL counts and scoreboard check counts (0 checks = FAIL)
