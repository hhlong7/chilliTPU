// bram_sdp_pkg.sv - UVM environment for bram_sdp.
// Status: SKELETON. Build it from the shared kit in tb/common/ (PROJECT_PLAN.md section 6).
//
// Classes to write (in this order):
//   bram_sdp_item        uvm_sequence_item: one transaction
//   bram_sdp_seq_*       sequences: smoke, edge (-128/127/0, sizes), random (constrained)
//   bram_sdp_agent       driver + monitor + sequencer per port group (reuse tb_common stream/axil/bram agents)
//   bram_sdp_ref_model   reference model (SV int8_ref functions or golden .hex vectors)
//   bram_sdp_scoreboard  compares every DUT output with the reference; counts checks and errors
//   bram_sdp_coverage    covergroups (measured in xsim; Verilator ignores covergroups)
//   bram_sdp_env         builds and connects the above
//   bram_sdp_test_*      smoke / edge / random tests extending tb_common_pkg::base_test
//
// Every test must end with exactly one line:  PASS bram_sdp.<test> seed=<s>  or  FAIL ...

`include "uvm_macros.svh"

package bram_sdp_pkg;
  import uvm_pkg::*;
  // import tb_common_pkg::*;   // enable once tb/common is in place
  // import dnn_pkg::*;

  // TODO

endpackage : bram_sdp_pkg
