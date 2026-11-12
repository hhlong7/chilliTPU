// pe_pkg.sv - UVM environment for pe.
// Status: SKELETON. Build it from the shared kit in tb/common/ (PROJECT_PLAN.md section 6).
//
// Classes to write (in this order):
//   pe_item        uvm_sequence_item: one transaction
//   pe_seq_*       sequences: smoke, edge (-128/127/0, sizes), random (constrained)
//   pe_agent       driver + monitor + sequencer per port group (reuse tb_common stream/axil/bram agents)
//   pe_ref_model   reference model (SV int8_ref functions or golden .hex vectors)
//   pe_scoreboard  compares every DUT output with the reference; counts checks and errors
//   pe_coverage    covergroups (measured in xsim; Verilator ignores covergroups)
//   pe_env         builds and connects the above
//   pe_test_*      smoke / edge / random tests extending tb_common_pkg::base_test
//
// Every test must end with exactly one line:  PASS pe.<test> seed=<s>  or  FAIL ...

`include "uvm_macros.svh"

package pe_pkg;
  import uvm_pkg::*;
  // import tb_common_pkg::*;   // enable once tb/common is in place
  // import dnn_pkg::*;

  // TODO

endpackage : pe_pkg
