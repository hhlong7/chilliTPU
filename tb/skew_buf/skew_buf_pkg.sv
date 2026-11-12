// skew_buf_pkg.sv - UVM environment for skew_buf.
// Status: SKELETON. Build it from the shared kit in tb/common/ (PROJECT_PLAN.md section 6).
//
// Classes to write (in this order):
//   skew_buf_item        uvm_sequence_item: one transaction
//   skew_buf_seq_*       sequences: smoke, edge (-128/127/0, sizes), random (constrained)
//   skew_buf_agent       driver + monitor + sequencer per port group (reuse tb_common stream/axil/bram agents)
//   skew_buf_ref_model   reference model (SV int8_ref functions or golden .hex vectors)
//   skew_buf_scoreboard  compares every DUT output with the reference; counts checks and errors
//   skew_buf_coverage    covergroups (measured in xsim; Verilator ignores covergroups)
//   skew_buf_env         builds and connects the above
//   skew_buf_test_*      smoke / edge / random tests extending tb_common_pkg::base_test
//
// Every test must end with exactly one line:  PASS skew_buf.<test> seed=<s>  or  FAIL ...

`include "uvm_macros.svh"

package skew_buf_pkg;
  import uvm_pkg::*;
  // import tb_common_pkg::*;   // enable once tb/common is in place
  // import dnn_pkg::*;

  // TODO

endpackage : skew_buf_pkg
