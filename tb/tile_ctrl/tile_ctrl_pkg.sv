// tile_ctrl_pkg.sv - UVM environment for tile_ctrl.
// Status: SKELETON. Build it from the shared kit in tb/common/ (PROJECT_PLAN.md section 6).
//
// Classes to write (in this order):
//   tile_ctrl_item        uvm_sequence_item: one transaction
//   tile_ctrl_seq_*       sequences: smoke, edge (-128/127/0, sizes), random (constrained)
//   tile_ctrl_agent       driver + monitor + sequencer per port group (reuse tb_common stream/axil/bram agents)
//   tile_ctrl_ref_model   reference model (SV int8_ref functions or golden .hex vectors)
//   tile_ctrl_scoreboard  compares every DUT output with the reference; counts checks and errors
//   tile_ctrl_coverage    covergroups (measured in xsim; Verilator ignores covergroups)
//   tile_ctrl_env         builds and connects the above
//   tile_ctrl_test_*      smoke / edge / random tests extending tb_common_pkg::base_test
//
// Every test must end with exactly one line:  PASS tile_ctrl.<test> seed=<s>  or  FAIL ...

`include "uvm_macros.svh"

package tile_ctrl_pkg;
  import uvm_pkg::*;
  // import tb_common_pkg::*;   // enable once tb/common is in place
  // import dnn_pkg::*;

  // TODO

endpackage : tile_ctrl_pkg
