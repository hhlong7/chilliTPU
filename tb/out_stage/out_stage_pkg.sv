// out_stage_pkg.sv - UVM environment for out_stage (D1 requantize, D2 lanes, valid/ready).
//
// One item = one input beat (LANES acc/bias values, keep, and that beat's
// scale/shift/relu) or, on the monitor's output side, one output beat (LANES INT8
// values + keep). The driver holds in_valid until the DUT takes the beat and drives
// out_ready with random backpressure. The scoreboard queues every accepted input
// beat and checks each output beat, in order, against ref_requantize() from
// tb/common/int8_ref.svh (the SV copy of golden.py).
//
// Tests:
//   out_stage_directed_test      golden.py corner cases + every shift around a tie
//   out_stage_vector_test        replays vectors/out_stage/* (make vectors) and checks
//                                int8_ref == golden.py on every value
//   out_stage_random_test        random beats biased to extremes, settings change every row
//   out_stage_backpressure_test  random, back to back, out_ready low 70% of the time
//
// Stimulus uses $urandom (seeded by +verilator+seed / -sv_seed) instead of
// constraints, so the env runs the same way in Verilator and xsim.
//
// Every test ends with exactly one line:  PASS out_stage.<test> seed=<s> ...  or  FAIL ...

`include "uvm_macros.svh"

package out_stage_pkg;
  import uvm_pkg::*;
  import tb_common_pkg::*;

  localparam int LANES   = dnn_pkg::OUT_LANES;
  localparam int ACC_W   = dnn_pkg::ACC_W;
  localparam int BIAS_W  = dnn_pkg::BIAS_W;
  localparam int SCALE_W = dnn_pkg::SCALE_W;
  localparam int SHIFT_W = dnn_pkg::SHIFT_W;
  localparam int DATA_W  = dnn_pkg::DATA_W;

  typedef logic signed [ACC_W-1:0]  acc_t;
  typedef logic signed [BIAS_W-1:0] bias_t;
  typedef logic signed [DATA_W-1:0] data_t;
  typedef logic [SCALE_W-1:0]       scale_t;
  typedef logic [SHIFT_W-1:0]       shift_t;

  `uvm_analysis_imp_decl(_in)
  `uvm_analysis_imp_decl(_out)

  // ------------------------------------------------------------------ item
  class out_stage_item extends uvm_sequence_item;
    acc_t             acc  [LANES];
    bias_t            bias [LANES];
    logic [LANES-1:0] keep;
    scale_t           scale;
    shift_t           shift;
    bit               relu;
    int unsigned      gap;            // idle cycles before this beat (driver only)
    data_t            y    [LANES];   // output side (monitor only)
    `uvm_object_utils(out_stage_item)
    function new(string name = "out_stage_item"); super.new(name); endfunction
    function string convert2string();
      string s = $sformatf("scale=%0d shift=%0d relu=%0b keep=%b", scale, shift, relu, keep);
      for (int l = 0; l < LANES; l++)
        s = {s, $sformatf(" | lane%0d acc=%0d bias=%0d", l, acc[l], bias[l])};
      return s;
    endfunction
  endclass

  // ------------------------------------------------------------------ file helpers (vector test)
  // meta.txt: one key=value per line (vecgen.py). Unknown keys are ignored.
  function automatic bit read_meta(string path, ref int M, ref int N, ref int scale,
                                   ref int shift, ref int relu);
    int fd = $fopen(path, "r");
    string line, key;
    int eq;
    if (fd == 0) return 0;
    while ($fgets(line, fd)) begin
      eq = -1;
      for (int i = 0; i < line.len(); i++)
        if (eq < 0 && line[i] == "=") eq = i;
      if (eq > 0) begin
        key = line.substr(0, eq - 1);
        line = line.substr(eq + 1, line.len() - 1);
        if      (key == "M")     M     = line.atoi();
        else if (key == "N")     N     = line.atoi();
        else if (key == "scale") scale = line.atoi();
        else if (key == "shift") shift = line.atoi();
        else if (key == "relu")  relu  = line.atoi();
      end
    end
    $fclose(fd);
    return 1;
  endfunction

  // .hex: one two's-complement value per line; bits = 8 or 32. Appends sign-extended values.
  function automatic bit read_hex(string path, int bits, ref longint vals[$]);
    int fd = $fopen(path, "r");
    bit [31:0] v;
    if (fd == 0) return 0;
    while ($fscanf(fd, "%h", v) == 1)
      vals.push_back(bits == 8 ? longint'($signed(v[7:0])) : longint'($signed(v)));
    $fclose(fd);
    return 1;
  endfunction

  // ------------------------------------------------------------------ sequences
  class out_stage_base_seq extends uvm_sequence #(out_stage_item);
    int unsigned n_sent;
    int unsigned max_gap;    // each beat waits 0..max_gap idle cycles first
    `uvm_object_utils(out_stage_base_seq)
    function new(string name = "out_stage_base_seq"); super.new(name); endfunction

    // Send one row of N columns, LANES per beat. The last beat's keep marks the real lanes.
    task send_row(longint acc[$], longint bias[$], int unsigned scale, int unsigned shift, bit relu);
      out_stage_item it;
      for (int c = 0; c < acc.size(); c += LANES) begin
        it = out_stage_item::type_id::create("it");
        start_item(it);
        for (int l = 0; l < LANES; l++) begin
          it.keep[l] = (c + l < acc.size());
          it.acc[l]  = it.keep[l] ? acc_t'(acc[c + l])   : acc_t'(0);
          it.bias[l] = it.keep[l] ? bias_t'(bias[c + l]) : bias_t'(0);
        end
        it.scale = scale_t'(scale);
        it.shift = shift_t'(shift);
        it.relu  = relu;
        it.gap   = (max_gap == 0) ? 0 : $urandom_range(0, max_gap);
        finish_item(it);
        n_sent++;
      end
    endtask
  endclass

  // Directed: the same corner cases as test_golden.py / vecgen.py, then every shift around a tie.
  class out_stage_directed_seq extends out_stage_base_seq;
    `uvm_object_utils(out_stage_directed_seq)
    function new(string name = "out_stage_directed_seq"); super.new(name); endfunction
    task body();
      longint i32max = 64'sd2147483647;
      longint i32min = -64'sd2147483648;
      longint h;
      longint v[$], a[$], b[$];
      send_row('{5, -5, 3, -3, 1, -1}, '{0, 0, 0, 0, 0, 0}, 1, 1, 0);          // ties: 3 -2 2 -1 1 0
      send_row('{5, 7, -5, -7}, '{0, 0, 0, 0}, 1, 2, 0);                       // non-ties: 1 2 -1 -2
      send_row('{-1000, -129, -128, 127, 128, 1000}, '{0, 0, 0, 0, 0, 0}, 1, 0, 0);   // saturation
      send_row('{-10, -10, 0, 5}, '{15, 5, 0, -6}, 1, 0, 1);                   // ReLU after bias: 5 0 0 0
      send_row('{i32max, i32min}, '{i32max, i32min}, 1, 31, 0);                // 33-bit sum: 2 -2
      send_row('{i32max, i32min}, '{i32max, i32min}, 65535, 31, 0);            // worst product: 127 -128
      send_row('{99999, -99999}, '{7, 7}, 0, 5, 0);                            // scale 0: 0 0
      send_row('{3, -3, 0}, '{0, 0, 0}, 40, 0, 0);                             // shift 0, odd width: 120 -120 0
      // every shift 1..31: exact ties (+-0.5, +-1.5) and one step either side, ReLU off and on.
      // Each value v is split as acc = v/2, bias = v - v/2 so both fit in INT32.
      for (int sh = 1; sh < 32; sh++) begin
        h = 64'sd1 << (sh - 1);
        v = '{h, -h, 3 * h, -3 * h, h - 1, h + 1, -h - 1, -h + 1};
        a.delete();
        b.delete();
        foreach (v[j]) begin
          a.push_back(v[j] / 2);
          b.push_back(v[j] - v[j] / 2);
        end
        send_row(a, b, 1, sh, 0);
        send_row(a, b, 1, sh, 1);
      end
    endtask
  endclass

  // Random: rows of 1..2*LANES+1 columns; new scale/shift/relu every row.
  class out_stage_random_seq extends out_stage_base_seq;
    int unsigned n_beats = 3000;
    `uvm_object_utils(out_stage_random_seq)
    function new(string name = "out_stage_random_seq"); super.new(name); endfunction

    // full INT32 range, biased toward the extremes
    function longint rand_wide();
      case ($urandom_range(0, 7))
        0:       return -64'sd2147483648;
        1:       return 64'sd2147483647;
        2:       return 0;
        default: return longint'($signed($urandom));
      endcase
    endfunction

    // values whose result lands near the INT8 range for this scale/shift (so not everything saturates)
    function longint rand_near(int unsigned scale, int unsigned shift);
      longint lim = ((64'sd1 << (shift + 8)) / ((scale == 0) ? 1 : scale)) / 2 + 1;
      if (lim > 64'sd2147483647) lim = 64'sd2147483647;
      return (longint'($urandom) % (2 * lim + 1)) - lim;
    endfunction

    task body();
      int unsigned n, scale, shift;
      bit near;
      longint a[$], b[$];
      while (n_sent < n_beats) begin
        case ($urandom_range(0, 3))
          0:       scale = 0;
          1:       scale = 65535;
          default: scale = $urandom_range(1, 65535);
        endcase
        shift = $urandom_range(0, 31);
        near  = $urandom_range(0, 1);
        n     = $urandom_range(1, 2 * LANES + 1);
        a.delete();
        b.delete();
        repeat (n) begin
          a.push_back(near ? rand_near(scale, shift) : rand_wide());
          b.push_back(near ? rand_near(scale, shift) : rand_wide());
        end
        send_row(a, b, scale, shift, $urandom_range(0, 1));
      end
    endtask
  endclass

  // Vector replay: every out_stage case vecgen.py writes. Checks the SV reference against
  // golden.py's y_expected first, then sends the rows through the DUT.
  class out_stage_vector_seq extends out_stage_base_seq;
    string dir = "vectors/out_stage";
    string cases[$] = '{"ties", "non_ties", "saturate", "relu_after_bias", "sum_33bit",
                        "worst_product", "scale0", "random_00", "random_01", "random_02",
                        "random_03", "random_04", "random_05"};
    int unsigned n_ref_checks;
    `uvm_object_utils(out_stage_vector_seq)
    function new(string name = "out_stage_vector_seq"); super.new(name); endfunction
    task body();
      string d;
      int M, N, scale, shift, relu;
      longint acc[$], bias[$], y[$], row[$];
      byte r;
      void'($value$plusargs("VEC_DIR=%s", dir));
      foreach (cases[c]) begin
        d = {dir, "/", cases[c]};
        acc.delete();
        bias.delete();
        y.delete();
        if (!read_meta({d, "/meta.txt"}, M, N, scale, shift, relu) ||
            !read_hex({d, "/acc.hex"}, 32, acc) || !read_hex({d, "/bias.hex"}, 32, bias) ||
            !read_hex({d, "/y_expected.hex"}, 8, y))
          `uvm_fatal("VEC", $sformatf("cannot read %s (run make vectors first)", d))
        if (acc.size() != M * N || bias.size() != N || y.size() != M * N)
          `uvm_fatal("VEC", $sformatf("%s: sizes do not match M=%0d N=%0d", d, M, N))
        for (int m = 0; m < M; m++) begin
          row.delete();
          for (int n = 0; n < N; n++) begin
            r = ref_requantize(acc[m * N + n], bias[n], scale, shift, relu);
            n_ref_checks++;
            if (r != y[m * N + n])
              `uvm_error("REF", $sformatf("%s m=%0d n=%0d: int8_ref=%0d golden.py=%0d",
                                          cases[c], m, n, r, y[m * N + n]))
            row.push_back(acc[m * N + n]);
          end
          send_row(row, bias, scale, shift, relu);
        end
      end
      `uvm_info("VEC", $sformatf("%0d cases, %0d values: int8_ref checked against golden.py",
                                 cases.size(), n_ref_checks), UVM_LOW)
    endtask
  endclass

  // ------------------------------------------------------------------ driver
  class out_stage_driver extends uvm_driver #(out_stage_item);
    virtual out_stage_if vif;
    int unsigned pct_ready = 80;    // out_ready is high this % of cycles (backpressure knob)
    `uvm_component_utils(out_stage_driver)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
      if (!uvm_config_db#(virtual out_stage_if)::get(this, "", "vif", vif)) `uvm_fatal("NOVIF", "no vif")
    endfunction

    task run_phase(uvm_phase phase);
      out_stage_item it;
      vif.in_valid <= 1'b0;  vif.in_keep <= '0;  vif.in_acc <= '0;  vif.in_bias <= '0;
      vif.scale <= '0;  vif.shift <= '0;  vif.relu <= 1'b0;  vif.out_ready <= 1'b0;
      @(posedge vif.rst_n);
      // output side: random backpressure, changed on every falling edge
      fork
        forever begin
          @(negedge vif.clk);
          vif.out_ready <= ($urandom_range(0, 99) < pct_ready);
        end
      join_none
      // input side: hold each beat until the DUT takes it
      @(negedge vif.clk);
      forever begin
        seq_item_port.try_next_item(it);
        if (it == null) begin                 // nothing ready: go idle and wait
          vif.in_valid <= 1'b0;
          seq_item_port.get_next_item(it);
          @(negedge vif.clk);
        end
        if (it.gap > 0) begin
          vif.in_valid <= 1'b0;
          repeat (it.gap) @(negedge vif.clk);
        end
        for (int l = 0; l < LANES; l++) begin
          vif.in_acc[l]  <= it.acc[l];
          vif.in_bias[l] <= it.bias[l];
        end
        vif.in_keep  <= it.keep;
        vif.scale    <= it.scale;
        vif.shift    <= it.shift;
        vif.relu     <= it.relu;
        vif.in_valid <= 1'b1;
        do @(posedge vif.clk); while (vif.in_ready !== 1'b1);   // taken at this edge
        seq_item_port.item_done();
        @(negedge vif.clk);
      end
    endtask
  endclass

  // ------------------------------------------------------------------ monitor
  class out_stage_monitor extends uvm_monitor;
    virtual out_stage_if vif;
    uvm_analysis_port #(out_stage_item) ap_in;    // beats the DUT accepted
    uvm_analysis_port #(out_stage_item) ap_out;   // beats the DUT delivered
    `uvm_component_utils(out_stage_monitor)
    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap_in  = new("ap_in", this);
      ap_out = new("ap_out", this);
    endfunction
    function void build_phase(uvm_phase phase);
      if (!uvm_config_db#(virtual out_stage_if)::get(this, "", "vif", vif)) `uvm_fatal("NOVIF", "no vif")
    endfunction
    task run_phase(uvm_phase phase);
      out_stage_item it;
      forever begin
        @(posedge vif.clk);
        if (vif.rst_n === 1'b1) begin
          if (vif.in_valid === 1'b1 && vif.in_ready === 1'b1) begin
            it = out_stage_item::type_id::create("in");
            for (int l = 0; l < LANES; l++) begin
              it.acc[l]  = $signed(vif.in_acc[l]);
              it.bias[l] = $signed(vif.in_bias[l]);
            end
            it.keep  = vif.in_keep;
            it.scale = vif.scale;
            it.shift = vif.shift;
            it.relu  = vif.relu;
            ap_in.write(it);
          end
          if (vif.out_valid === 1'b1 && vif.out_ready === 1'b1) begin
            it = out_stage_item::type_id::create("out");
            for (int l = 0; l < LANES; l++) it.y[l] = $signed(vif.out_data[l]);
            it.keep = vif.out_keep;
            ap_out.write(it);
          end
        end
      end
    endtask
  endclass

  // ------------------------------------------------------------------ scoreboard (ref model = int8_ref)
  class out_stage_scoreboard extends uvm_scoreboard;
    uvm_analysis_imp_in  #(out_stage_item, out_stage_scoreboard) imp_in;
    uvm_analysis_imp_out #(out_stage_item, out_stage_scoreboard) imp_out;
    out_stage_item pending[$];          // accepted, not yet delivered (in order)
    int unsigned n_in, n_out, n_lanes, n_sat, n_errors;
    `uvm_component_utils(out_stage_scoreboard)
    function new(string name, uvm_component parent);
      super.new(name, parent);
      imp_in  = new("imp_in", this);
      imp_out = new("imp_out", this);
    endfunction

    function void write_in(out_stage_item it);
      pending.push_back(it);
      n_in++;
    endfunction

    function void write_out(out_stage_item it);
      out_stage_item src;
      byte want;
      n_out++;
      if (pending.size() == 0) begin
        n_errors++;
        `uvm_error("SB", $sformatf("output beat %0d with no input beat", n_out))
        return;
      end
      src = pending.pop_front();
      if (it.keep !== src.keep) begin
        n_errors++;
        `uvm_error("SB", $sformatf("beat %0d: keep got %b expected %b", n_out, it.keep, src.keep))
      end
      for (int l = 0; l < LANES; l++) begin
        if (src.keep[l]) begin
          want = ref_requantize(src.acc[l], src.bias[l], src.scale, src.shift, src.relu);
          n_lanes++;
          if (want == 127 || want == -128) n_sat++;
          if (it.y[l] !== want) begin
            n_errors++;
            `uvm_error("SB", $sformatf("beat %0d lane %0d: got %0d expected %0d | %s",
                                       n_out, l, it.y[l], want, src.convert2string()))
          end
        end
      end
    endfunction

    function void check_phase(uvm_phase phase);
      if (pending.size() != 0)
        `uvm_error("SB", $sformatf("%0d accepted beats never came out", pending.size()))
    endfunction
  endclass

`ifndef VERILATOR
  // ------------------------------------------------------------------ coverage (xsim only; Verilator ignores covergroups)
  class out_stage_coverage extends uvm_subscriber #(out_stage_item);
    out_stage_item it;
    covergroup cg;
      cp_shift: coverpoint it.shift { bins zero = {0}; bins one = {1}; bins mid = {[2:30]}; bins max = {31}; }
      cp_scale: coverpoint it.scale { bins zero = {0}; bins one = {1}; bins mid = {[2:65534]}; bins max = {65535}; }
      cp_relu:  coverpoint it.relu;
      cp_keep:  coverpoint it.keep;
      x_shift_relu: cross cp_shift, cp_relu;
    endgroup
    `uvm_component_utils(out_stage_coverage)
    function new(string name, uvm_component parent); super.new(name, parent); cg = new(); endfunction
    function void write(out_stage_item t); it = t; cg.sample(); endfunction
  endclass
`endif

  // ------------------------------------------------------------------ env
  class out_stage_env extends uvm_env;
    out_stage_driver                drv;
    out_stage_monitor               mon;
    out_stage_scoreboard            sb;
    uvm_sequencer #(out_stage_item) sqr;
`ifndef VERILATOR
    out_stage_coverage              cov;
`endif
    `uvm_component_utils(out_stage_env)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
      drv = out_stage_driver::type_id::create("drv", this);
      mon = out_stage_monitor::type_id::create("mon", this);
      sb  = out_stage_scoreboard::type_id::create("sb", this);
      sqr = uvm_sequencer#(out_stage_item)::type_id::create("sqr", this);
`ifndef VERILATOR
      cov = out_stage_coverage::type_id::create("cov", this);
`endif
    endfunction
    function void connect_phase(uvm_phase phase);
      drv.seq_item_port.connect(sqr.seq_item_export);
      mon.ap_in.connect(sb.imp_in);
      mon.ap_out.connect(sb.imp_out);
`ifndef VERILATOR
      mon.ap_in.connect(cov.analysis_export);
`endif
    endfunction
  endclass

  // ------------------------------------------------------------------ tests
  class out_stage_base_test extends uvm_test;
    out_stage_env env;
    int unsigned  seed;
    int unsigned  n_sent;
    int unsigned  pct_ready = 80;
    `uvm_component_utils(out_stage_base_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
      if (!$value$plusargs("SEED=%d", seed)) seed = 0;
      env = out_stage_env::type_id::create("env", this);
    endfunction
    virtual task run_seq(); endtask
    task run_phase(uvm_phase phase);
      phase.raise_objection(this);
      `uvm_info("SEED", $sformatf("seed=%0d", seed), UVM_NONE)
      env.drv.pct_ready = pct_ready;
      run_seq();
      // let the last beats drain out of the 3-stage pipe (with backpressure)
      repeat (2) @(posedge env.drv.vif.clk);
      for (int c = 0; c < 10000 && env.sb.pending.size() != 0; c++) @(posedge env.drv.vif.clk);
      repeat (2) @(posedge env.drv.vif.clk);
      phase.drop_objection(this);
    endtask
    function void report_phase(uvm_phase phase);
      uvm_report_server rs = uvm_report_server::get_server();
      int errs = rs.get_severity_count(UVM_ERROR) + rs.get_severity_count(UVM_FATAL);
      bit ok = (errs == 0) && (n_sent > 0) && (env.sb.n_in == n_sent) && (env.sb.n_out == n_sent);
      $display("%s out_stage.%s seed=%0d beats=%0d lanes=%0d saturated=%0d errors=%0d",
               ok ? "PASS" : "FAIL", get_type_name(), seed, env.sb.n_out, env.sb.n_lanes, env.sb.n_sat, errs);
    endfunction
  endclass

  class out_stage_directed_test extends out_stage_base_test;
    `uvm_component_utils(out_stage_directed_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_seq();
      out_stage_directed_seq seq = out_stage_directed_seq::type_id::create("seq");
      seq.start(env.sqr);
      n_sent = seq.n_sent;
    endtask
  endclass

  class out_stage_vector_test extends out_stage_base_test;
    `uvm_component_utils(out_stage_vector_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_seq();
      out_stage_vector_seq seq = out_stage_vector_seq::type_id::create("seq");
      seq.max_gap = 1;
      seq.start(env.sqr);
      n_sent = seq.n_sent;
    endtask
  endclass

  class out_stage_random_test extends out_stage_base_test;
    `uvm_component_utils(out_stage_random_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_seq();
      out_stage_random_seq seq = out_stage_random_seq::type_id::create("seq");
      seq.max_gap = 2;
      seq.start(env.sqr);
      n_sent = seq.n_sent;
    endtask
  endclass

  class out_stage_backpressure_test extends out_stage_base_test;
    `uvm_component_utils(out_stage_backpressure_test)
    function new(string name, uvm_component parent);
      super.new(name, parent);
      pct_ready = 30;
    endfunction
    task run_seq();
      out_stage_random_seq seq = out_stage_random_seq::type_id::create("seq");
      seq.max_gap = 0;
      seq.start(env.sqr);
      n_sent = seq.n_sent;
    endtask
  endclass

endpackage : out_stage_pkg
