// dnn_pkg.sv - shared parameters and types for the whole accelerator.
//
// SINGLE SOURCE OF TRUTH (with spec/regmap.yaml). Mirrored in sw/py/spec.py.
// Change a value here only through a `spec-change` PR (PROJECT_PLAN.md section 5),
// then update sw/py/spec.py in the same PR.
//
// Values marked TBD are proposals until the group freezes the spec in Week 1.

package dnn_pkg;

  // ---------------- Array geometry ----------------
  parameter int ROWS        = 12;   // reduction dimension K per tile
  parameter int COLS        = 12;   // output channels N per tile
  parameter int MAX_TENANTS = 4;    // design for N tenants, verify/demo 2

  // ---------------- Data widths ----------------
  parameter int DATA_W = 8;         // INT8 weights and activations (signed)
  parameter int PROD_W = 2*DATA_W;  // 16-bit signed product
  parameter int PSUM_W = 32;        // in-array partial sum (min 19 for 12 rows)
  parameter int ACC_W  = 32;        // INT32 cross-tile accumulation

  // ---------------- Requantize: out = clamp(round((relu(acc+bias)*scale) >> shift), -128, 127)
  parameter int BIAS_W  = ACC_W;    // TBD
  parameter int SCALE_W = 16;       // TBD: proposed unsigned 16-bit
  parameter int SHIFT_W = 5;        // TBD: proposed 5-bit shift
  // TBD: rounding rule (proposed: add 1 << (shift-1), then arithmetic shift right)

  // ---------------- Types ----------------
  typedef logic signed [DATA_W-1:0] data_t;
  typedef logic signed [PROD_W-1:0] prod_t;
  typedef logic signed [PSUM_W-1:0] psum_t;
  typedef logic signed [ACC_W-1:0]  acc_t;

  localparam int TENANT_W = (MAX_TENANTS > 1) ? $clog2(MAX_TENANTS) : 1;
  typedef logic [TENANT_W-1:0] tenant_id_t;

endpackage : dnn_pkg
