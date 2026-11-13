// dnn_pkg.sv - shared parameters and types for the whole accelerator.
//
// SINGLE SOURCE OF TRUTH (with spec/regmap.yaml). Mirrored in sw/py/spec.py.
// Change a value here only through a `spec-change` PR (PROJECT_PLAN.md section 5),
// then update sw/py/spec.py in the same PR.
//
// Requantize values frozen 2026-11-12 (see results/log.md).

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

  // ---------------- Requantize (frozen 2026-11-12, D1/D2). Must match sw/py/spec.py.
  //   s   = acc + bias                       (33-bit, no wraparound)
  //   r   = relu ? max(s, 0) : s
  //   p   = r * scale                        (scale is UNSIGNED)
  //   q   = shift > 0 ? (p + (1 << (shift-1))) >>> shift : p    (round half up, toward +inf)
  //   out = clamp(q, -128, 127)
  parameter int BIAS_W    = ACC_W;  // INT32 bias, added once after the last K tile
  parameter int SCALE_W   = 16;     // unsigned
  parameter int SHIFT_W   = 5;      // shift 0..31
  parameter int OUT_LANES = 2;      // requantize lanes in out_stage (2 DSP48E1 each)

  // ---------------- Types ----------------
  typedef logic signed [DATA_W-1:0] data_t;
  typedef logic signed [PROD_W-1:0] prod_t;
  typedef logic signed [PSUM_W-1:0] psum_t;
  typedef logic signed [ACC_W-1:0]  acc_t;

  localparam int TENANT_W = (MAX_TENANTS > 1) ? $clog2(MAX_TENANTS) : 1;
  typedef logic [TENANT_W-1:0] tenant_id_t;

endpackage : dnn_pkg
