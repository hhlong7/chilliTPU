// out_stage_pkg.sv - UVM environment for out_stage.
// Status: SKELETON. Build it from the shared kit in tb/common/ (PROJECT_PLAN.md section 6).
//
// Classes to write (in this order):
//   out_stage_item        uvm_sequence_item: one transaction
//   out_stage_seq_*       sequences: smoke, edge (-128/127/0, sizes), random (constrained)
//   out_stage_agent       driver + monitor + sequencer per port group (reuse tb_common stream/axil/bram agents)
//   out_stage_ref_model   reference model (SV int8_ref functions or golden .hex vectors)
//   out_stage_scoreboard  compares every DUT output with the reference; counts checks and errors
//   out_stage_coverage    covergroups (measured in xsim; Verilator ignores covergroups)
//   out_stage_env         builds and connects the above
//   out_stage_test_*      smoke / edge / random tests extending tb_common_pkg::base_test
//
// Every test must end with exactly one line:  PASS out_stage.<test> seed=<s>  or  FAIL ...

`include "uvm_macros.svh"

package out_stage_pkg;
  import uvm_pkg::*;
  // import tb_common_pkg::*;   // enable once tb/common is in place
  // import dnn_pkg::*;

  // TODO

endpackage : out_stage_pkg
