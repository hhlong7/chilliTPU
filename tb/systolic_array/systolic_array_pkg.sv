// systolic_array_pkg.sv - UVM environment for systolic_array.
// Status: SKELETON. Build it from the shared kit in tb/common/ (PROJECT_PLAN.md section 6).
//
// Classes to write (in this order):
//   systolic_array_item        uvm_sequence_item: one transaction
//   systolic_array_seq_*       sequences: smoke, edge (-128/127/0, sizes), random (constrained)
//   systolic_array_agent       driver + monitor + sequencer per port group (reuse tb_common stream/axil/bram agents)
//   systolic_array_ref_model   reference model (SV int8_ref functions or golden .hex vectors)
//   systolic_array_scoreboard  compares every DUT output with the reference; counts checks and errors
//   systolic_array_coverage    covergroups (measured in xsim; Verilator ignores covergroups)
//   systolic_array_env         builds and connects the above
//   systolic_array_test_*      smoke / edge / random tests extending tb_common_pkg::base_test
//
// Every test must end with exactly one line:  PASS systolic_array.<test> seed=<s>  or  FAIL ...

`include "uvm_macros.svh"

package systolic_array_pkg;
  import uvm_pkg::*;
  // import tb_common_pkg::*;   // enable once tb/common is in place
  // import dnn_pkg::*;

  // TODO

endpackage : systolic_array_pkg
