// deskew_buf_pkg.sv - UVM environment for deskew_buf.
// Status: SKELETON. Build it from the shared kit in tb/common/ (PROJECT_PLAN.md section 6).
//
// Classes to write (in this order):
//   deskew_buf_item        uvm_sequence_item: one transaction
//   deskew_buf_seq_*       sequences: smoke, edge (-128/127/0, sizes), random (constrained)
//   deskew_buf_agent       driver + monitor + sequencer per port group (reuse tb_common stream/axil/bram agents)
//   deskew_buf_ref_model   reference model (SV int8_ref functions or golden .hex vectors)
//   deskew_buf_scoreboard  compares every DUT output with the reference; counts checks and errors
//   deskew_buf_coverage    covergroups (measured in xsim; Verilator ignores covergroups)
//   deskew_buf_env         builds and connects the above
//   deskew_buf_test_*      smoke / edge / random tests extending tb_common_pkg::base_test
//
// Every test must end with exactly one line:  PASS deskew_buf.<test> seed=<s>  or  FAIL ...

`include "uvm_macros.svh"

package deskew_buf_pkg;
  import uvm_pkg::*;
  // import tb_common_pkg::*;   // enable once tb/common is in place
  // import dnn_pkg::*;

  // TODO

endpackage : deskew_buf_pkg
