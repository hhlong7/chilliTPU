// accum_mem_pkg.sv - UVM environment for accum_mem.
// Status: SKELETON. Build it from the shared kit in tb/common/ (PROJECT_PLAN.md section 6).
//
// Classes to write (in this order):
//   accum_mem_item        uvm_sequence_item: one transaction
//   accum_mem_seq_*       sequences: smoke, edge (-128/127/0, sizes), random (constrained)
//   accum_mem_agent       driver + monitor + sequencer per port group (reuse tb_common stream/axil/bram agents)
//   accum_mem_ref_model   reference model (SV int8_ref functions or golden .hex vectors)
//   accum_mem_scoreboard  compares every DUT output with the reference; counts checks and errors
//   accum_mem_coverage    covergroups (measured in xsim; Verilator ignores covergroups)
//   accum_mem_env         builds and connects the above
//   accum_mem_test_*      smoke / edge / random tests extending tb_common_pkg::base_test
//
// Every test must end with exactly one line:  PASS accum_mem.<test> seed=<s>  or  FAIL ...

`include "uvm_macros.svh"

package accum_mem_pkg;
  import uvm_pkg::*;
  // import tb_common_pkg::*;   // enable once tb/common is in place
  // import dnn_pkg::*;

  // TODO

endpackage : accum_mem_pkg
