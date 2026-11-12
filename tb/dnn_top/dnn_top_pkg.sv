// dnn_top_pkg.sv - UVM environment for dnn_top.
// Status: SKELETON. Build it from the shared kit in tb/common/ (PROJECT_PLAN.md section 6).
//
// Classes to write (in this order):
//   dnn_top_item        uvm_sequence_item: one transaction
//   dnn_top_seq_*       sequences: smoke, edge (-128/127/0, sizes), random (constrained)
//   dnn_top_agent       driver + monitor + sequencer per port group (reuse tb_common stream/axil/bram agents)
//   dnn_top_ref_model   reference model (SV int8_ref functions or golden .hex vectors)
//   dnn_top_scoreboard  compares every DUT output with the reference; counts checks and errors
//   dnn_top_coverage    covergroups (measured in xsim; Verilator ignores covergroups)
//   dnn_top_env         builds and connects the above
//   dnn_top_test_*      smoke / edge / random tests extending tb_common_pkg::base_test
//
// Every test must end with exactly one line:  PASS dnn_top.<test> seed=<s>  or  FAIL ...

`include "uvm_macros.svh"

package dnn_top_pkg;
  import uvm_pkg::*;
  // import tb_common_pkg::*;   // enable once tb/common is in place
  // import dnn_pkg::*;

  // TODO

endpackage : dnn_top_pkg
