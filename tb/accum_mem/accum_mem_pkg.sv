// accum_mem_pkg.sv - UVM environment for accum_mem (cross-K-tile INT32 accumulator).
//
// Unlike pe/bram_sdp, accum_mem has valid/ready streams, so one item = one BEAT
// (one output row m of one K tile), not one clock cycle. The driver holds a beat
// until in_ready and randomly drops out_ready (backpressure). The monitor reports
// every handshake. The scoreboard keeps its own accumulator memory: each input beat
// with last=1 predicts one output row, and output rows must come out in order.
//
// An OVF_CHECK item waits for the pipeline to drain, then pulses ovf_clr; the
// scoreboard checks the sticky ovf flag at that moment against its own model.
//
// Every test ends with exactly one line:  PASS accum_mem.<test> seed=<s> ...  or  FAIL ...

`include "uvm_macros.svh"

package accum_mem_pkg;
  import uvm_pkg::*;

  localparam int COLS   = dnn_pkg::COLS;
  localparam int ACC_W  = dnn_pkg::ACC_W;
  localparam int DEPTH  = 64;               // small: rows wrap around the address space
  localparam int ADDR_W = $clog2(DEPTH);

  typedef logic signed [ACC_W-1:0] acc_t;
  typedef logic [ADDR_W-1:0]       addr_t;
  typedef virtual accum_mem_if #(COLS, ACC_W, ADDR_W) vif_t;

  localparam longint ACC_MAX = (longint'(1) <<< (ACC_W - 1)) - 1;
  localparam longint ACC_MIN = -(longint'(1) <<< (ACC_W - 1));

  typedef enum {BEAT, OVF_CHECK} kind_e;

  // ------------------------------------------------------------------ item
  class accum_mem_item extends uvm_sequence_item;
    kind_e       kind = BEAT;
    int unsigned gap;             // driver: idle cycles before this beat
    addr_t       addr;
    bit          first, last;
    acc_t        data [COLS];
    // filled by the monitor
    bit          is_out;          // 0 = input handshake, 1 = output handshake
    bit          ovf;             // OVF_CHECK: flag value just before the clear
    longint unsigned cycle;       // clock cycle of the handshake
    `uvm_object_utils(accum_mem_item)
    function new(string name = "accum_mem_item"); super.new(name); endfunction
    function string convert2string();
      string s = $sformatf("%s addr=%0d first=%0b last=%0b data=", is_out ? "OUT" : "IN", addr, first, last);
      foreach (data[c]) s = {s, $sformatf("%0d ", data[c])};
      return s;
    endfunction
  endclass

  // ------------------------------------------------------------------ sequences
  class accum_mem_base_seq extends uvm_sequence #(accum_mem_item);
    int unsigned n_beats;
    int unsigned pct_gap = 0;     // chance of 1-3 idle cycles before a beat
    int unsigned pct_big = 0;     // chance a value is an extreme (overflow likely)
    `uvm_object_utils(accum_mem_base_seq)
    function new(string name = "accum_mem_base_seq"); super.new(name); endfunction

    function int unsigned rand_gap();
      return ($urandom_range(0, 99) < pct_gap) ? $urandom_range(1, 3) : 0;
    endfunction

    function acc_t rand_val();
      if ($urandom_range(0, 99) < pct_big)
        case ($urandom_range(0, 3))
          0: return acc_t'(ACC_MAX);
          1: return acc_t'(ACC_MIN);
          2: return acc_t'(-1);
          default: return acc_t'($urandom);
        endcase
      // typical partial sum of one K tile: 12 products of |128*128| -> < 2^18
      return acc_t'($signed($urandom_range(0, 1 << 19)) - (1 << 18));
    endfunction

    // one beat with every column set to v
    task beat(addr_t a, bit first, bit last, acc_t v, int unsigned gap = 0);
      accum_mem_item it = accum_mem_item::type_id::create("it");
      start_item(it);
      it.kind = BEAT; it.addr = a; it.first = first; it.last = last; it.gap = gap;
      foreach (it.data[c]) it.data[c] = v;
      finish_item(it);
      n_beats++;
    endtask

    // one layer the way tile_ctrl sends it (D3): K tiles outer, M rows inner,
    // row m at address base+m (wraps), first on tile 0, last on tile k_tiles-1
    task layer(int unsigned m_rows, int unsigned k_tiles, addr_t base);
      for (int unsigned k = 0; k < k_tiles; k++)
        for (int unsigned m = 0; m < m_rows; m++) begin
          accum_mem_item it = accum_mem_item::type_id::create("it");
          start_item(it);
          it.kind  = BEAT;
          it.addr  = addr_t'(base + m);
          it.first = (k == 0);
          it.last  = (k == k_tiles - 1);
          it.gap   = rand_gap();
          foreach (it.data[c]) it.data[c] = rand_val();
          finish_item(it);
          n_beats++;
        end
    endtask

    // drain, then pulse ovf_clr; the scoreboard checks ovf at that moment
    task ovf_check();
      accum_mem_item it = accum_mem_item::type_id::create("chk");
      start_item(it);
      it.kind = OVF_CHECK;
      finish_item(it);
    endtask
  endclass

  // Directed: one feature per block, each closed by an ovf_check.
  class accum_mem_directed_seq extends accum_mem_base_seq;
    `uvm_object_utils(accum_mem_directed_seq)
    function new(string name = "accum_mem_directed_seq"); super.new(name); endfunction
    task body();
      layer(4, 1, 0);           // single K tile: first and last on the same beat
      layer(5, 3, 10);          // 3 K tiles back-to-back, no gaps
      layer(1, 4, 20);          // M = 1: every beat hits the address just written -> forwarding
      layer(2, 3, 30);          // M = 2: hazard is 2 beats apart, plain BRAM read works
      layer(3, 2, DEPTH - 2);   // addresses DEPTH-2, DEPTH-1, 0
      layer(3, 2, 0);           // reuse addresses: first must ignore the old contents
      ovf_check();              // nothing overflowed -> expect ovf = 0

      // positive overflow: INT32 max - 15 + 32 wraps (data still checked, wrapped like RTL)
      beat(40, 1, 0, acc_t'(ACC_MAX - 15));
      beat(40, 0, 1, 32);
      ovf_check();              // expect 1, then cleared

      // negative overflow, through the forwarding path (same address back-to-back)
      beat(41, 1, 0, acc_t'(ACC_MIN));
      beat(41, 0, 0, -1);
      beat(41, 0, 1, 5);
      ovf_check();              // expect 1

      // extremes that do NOT overflow: max + min = -1
      beat(42, 1, 0, acc_t'(ACC_MAX));
      beat(42, 0, 1, acc_t'(ACC_MIN));
      ovf_check();              // expect 0: the clear above really cleared it
    endtask
  endclass

  // Random: random layer shapes and addresses, idle gaps, occasional extreme values.
  class accum_mem_random_seq extends accum_mem_base_seq;
    int unsigned n_layers = 40;
    `uvm_object_utils(accum_mem_random_seq)
    function new(string name = "accum_mem_random_seq"); super.new(name); endfunction
    task body();
      for (int i = 0; i < n_layers; i++) begin
        int unsigned m = ($urandom_range(0, 3) == 0) ? 1 : $urandom_range(2, 8);   // M = 1 often
        layer(m, $urandom_range(1, 6), addr_t'($urandom_range(0, DEPTH - 1)));
        if (i % 8 == 7) ovf_check();
      end
      ovf_check();
    endtask
  endclass

  // ------------------------------------------------------------------ driver
  class accum_mem_driver extends uvm_driver #(accum_mem_item);
    vif_t vif;
    int unsigned pct_ready = 100;   // out_ready high probability each cycle (backpressure knob)
    `uvm_component_utils(accum_mem_driver)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
      if (!uvm_config_db#(vif_t)::get(this, "", "vif", vif)) `uvm_fatal("NOVIF", "no vif")
    endfunction

    task run_phase(uvm_phase phase);
      vif.in_valid <= 0; vif.in_addr <= 0; vif.in_first <= 0; vif.in_last <= 0;
      foreach (vif.in_data[c]) vif.in_data[c] <= '0;
      vif.out_ready <= 0; vif.ovf_clr <= 0;
      @(posedge vif.rst_n);
      fork drive_out_ready(); join_none
      forever begin
        accum_mem_item it;
        @(negedge vif.clk);
        vif.in_valid <= 0;                       // default: idle (overridden below if a beat is ready)
        vif.ovf_clr  <= 0;
        seq_item_port.try_next_item(it);
        if (it == null) continue;
        if (it.kind == OVF_CHECK) begin
          wait_drained();
          @(negedge vif.clk);
          vif.ovf_clr <= 1;                      // high for exactly one rising edge
        end else begin
          repeat (it.gap) @(negedge vif.clk);
          vif.in_valid <= 1; vif.in_addr <= it.addr; vif.in_first <= it.first; vif.in_last <= it.last;
          foreach (it.data[c]) vif.in_data[c] <= it.data[c];
          do @(posedge vif.clk); while (vif.in_ready !== 1'b1);   // hold until accepted
        end
        seq_item_port.item_done();
      end
    endtask

    task drive_out_ready();
      forever begin
        @(negedge vif.clk);
        vif.out_ready <= ($urandom_range(0, 99) < pct_ready);
      end
    endtask

    // pipeline is empty once out_valid has been low for 3 cycles with no input
    task wait_drained();
      int quiet = 0;
      while (quiet < 3) begin
        @(posedge vif.clk);
        quiet = (vif.out_valid === 1'b1) ? 0 : quiet + 1;
      end
    endtask
  endclass

  // ------------------------------------------------------------------ monitor
  class accum_mem_monitor extends uvm_monitor;
    vif_t vif;
    uvm_analysis_port #(accum_mem_item) ap;
    `uvm_component_utils(accum_mem_monitor)
    function new(string name, uvm_component parent); super.new(name, parent); ap = new("ap", this); endfunction
    function void build_phase(uvm_phase phase);
      if (!uvm_config_db#(vif_t)::get(this, "", "vif", vif)) `uvm_fatal("NOVIF", "no vif")
    endfunction
    task run_phase(uvm_phase phase);
      longint unsigned cyc = 0;
      forever begin
        @(posedge vif.clk);
        if (vif.rst_n !== 1'b1) continue;
        cyc++;
        if (vif.in_valid === 1'b1 && vif.in_ready === 1'b1) begin
          accum_mem_item it = accum_mem_item::type_id::create("in");
          it.is_out = 0; it.cycle = cyc;
          it.addr = vif.in_addr; it.first = vif.in_first; it.last = vif.in_last;
          foreach (it.data[c]) it.data[c] = vif.in_data[c];
          ap.write(it);
        end
        if (vif.out_valid === 1'b1 && vif.out_ready === 1'b1) begin
          accum_mem_item it = accum_mem_item::type_id::create("out");
          it.is_out = 1; it.cycle = cyc; it.addr = vif.out_addr;
          foreach (it.data[c]) it.data[c] = vif.out_data[c];
          ap.write(it);
        end
        if (vif.ovf_clr === 1'b1) begin
          accum_mem_item it = accum_mem_item::type_id::create("ovf");
          it.kind = OVF_CHECK; it.cycle = cyc; it.ovf = vif.ovf;
          ap.write(it);
        end
      end
    endtask
  endclass

  // ------------------------------------------------------------------ reference model + scoreboard
  class accum_mem_scoreboard extends uvm_scoreboard;
    uvm_analysis_imp #(accum_mem_item, accum_mem_scoreboard) imp;
    acc_t          acc [DEPTH][COLS];   // model of the accumulator memory
    accum_mem_item exp_q [$];           // predicted output rows, in order
    bit            ovf;                 // model of the sticky flag
    int unsigned   n_in, n_out, n_errors, n_fwd, n_ovf_checks, n_ovf_events;
    longint unsigned prev_cycle;
    addr_t         prev_addr;
    `uvm_component_utils(accum_mem_scoreboard)
    function new(string name, uvm_component parent); super.new(name, parent); imp = new("imp", this); endfunction

    function void write(accum_mem_item it);
      if (it.kind == OVF_CHECK) check_ovf(it);
      else if (!it.is_out)      predict(it);
      else                      compare(it);
    endfunction

    // input beat: add to the model; a last beat predicts one output row
    function void predict(accum_mem_item it);
      accum_mem_item exp = accum_mem_item::type_id::create("exp");
      bit beat_ovf = 0;
      n_in++;
      // same address on the very next cycle = the case the forwarding path handles
      if (!it.first && n_in > 1 && it.cycle == prev_cycle + 1 && it.addr == prev_addr) n_fwd++;
      prev_cycle = it.cycle; prev_addr = it.addr;
      exp.is_out = 1; exp.addr = it.addr;
      foreach (it.data[c]) begin
        longint old  = it.first ? 0 : longint'(acc[it.addr][c]);
        longint wide = old + longint'(it.data[c]);
        if (wide > ACC_MAX || wide < ACC_MIN) beat_ovf = 1;
        exp.data[c]       = acc_t'(wide);        // wraps to 32 bits like the RTL
        acc[it.addr][c]   = exp.data[c];
      end
      if (beat_ovf) begin ovf = 1; n_ovf_events++; end
      if (it.last) exp_q.push_back(exp);
    endfunction

    // output row: must be the oldest prediction
    function void compare(accum_mem_item it);
      accum_mem_item exp;
      n_out++;
      if (exp_q.size() == 0) begin
        n_errors++;
        `uvm_error("SB", $sformatf("unexpected output row: %s", it.convert2string()))
        return;
      end
      exp = exp_q.pop_front();
      if (it.addr !== exp.addr || it.data != exp.data) begin
        n_errors++;
        `uvm_error("SB", $sformatf("row %0d mismatch\n  got      %s\n  expected %s",
                   n_out, it.convert2string(), exp.convert2string()))
      end
    endfunction

    function void check_ovf(accum_mem_item it);
      n_ovf_checks++;
      if (it.ovf !== ovf) begin
        n_errors++;
        `uvm_error("SB", $sformatf("ovf check %0d: ovf=%0b expected %0b", n_ovf_checks, it.ovf, ovf))
      end
      ovf = 0;   // the pulse clears it
    endfunction

    function void check_phase(uvm_phase phase);
      if (exp_q.size() != 0)
        `uvm_error("SB", $sformatf("%0d predicted rows never came out (first: %s)",
                   exp_q.size(), exp_q[0].convert2string()))
    endfunction
  endclass

`ifndef VERILATOR
  // ------------------------------------------------------------------ coverage (xsim only)
  class accum_mem_coverage extends uvm_subscriber #(accum_mem_item);
    accum_mem_item it;
    covergroup cg;
      cp_tag:  coverpoint {it.first, it.last} iff (it.kind == BEAT && !it.is_out);
      cp_ovf:  coverpoint it.ovf iff (it.kind == OVF_CHECK);
      cp_addr: coverpoint it.addr iff (it.kind == BEAT && !it.is_out) { bins lo = {0}; bins hi = {DEPTH - 1}; bins mid = default; }
    endgroup
    `uvm_component_utils(accum_mem_coverage)
    function new(string name, uvm_component parent); super.new(name, parent); cg = new(); endfunction
    function void write(accum_mem_item t); it = t; cg.sample(); endfunction
  endclass
`endif

  // ------------------------------------------------------------------ env
  class accum_mem_env extends uvm_env;
    accum_mem_driver                drv;
    accum_mem_monitor               mon;
    accum_mem_scoreboard            sb;
    uvm_sequencer #(accum_mem_item) sqr;
`ifndef VERILATOR
    accum_mem_coverage              cov;
`endif
    `uvm_component_utils(accum_mem_env)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
      drv = accum_mem_driver::type_id::create("drv", this);
      mon = accum_mem_monitor::type_id::create("mon", this);
      sb  = accum_mem_scoreboard::type_id::create("sb", this);
      sqr = uvm_sequencer#(accum_mem_item)::type_id::create("sqr", this);
`ifndef VERILATOR
      cov = accum_mem_coverage::type_id::create("cov", this);
`endif
    endfunction
    function void connect_phase(uvm_phase phase);
      drv.seq_item_port.connect(sqr.seq_item_export);
      mon.ap.connect(sb.imp);
`ifndef VERILATOR
      mon.ap.connect(cov.analysis_export);
`endif
    endfunction
  endclass

  // ------------------------------------------------------------------ tests
  class accum_mem_base_test extends uvm_test;
    accum_mem_env env;
    int unsigned  seed;
    int unsigned  n_sent;
    int unsigned  min_fwd = 0;      // directed test demands the forwarding path was used
    `uvm_component_utils(accum_mem_base_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
      if (!$value$plusargs("SEED=%d", seed)) seed = 0;
      env = accum_mem_env::type_id::create("env", this);
    endfunction
    virtual task run_seq(); endtask
    task run_phase(uvm_phase phase);
      phase.raise_objection(this);
      `uvm_info("SEED", $sformatf("seed=%0d", seed), UVM_NONE)
      run_seq();
      env.drv.wait_drained();          // every predicted row has had time to come out
      phase.drop_objection(this);
    endtask
    function void report_phase(uvm_phase phase);
      uvm_report_server rs = uvm_report_server::get_server();
      int errs = rs.get_severity_count(UVM_ERROR) + rs.get_severity_count(UVM_FATAL);
      bit ok = (errs == 0) && (n_sent > 0) && (env.sb.n_in == n_sent) && (env.sb.n_out > 0)
               && (env.sb.n_fwd >= min_fwd);
      $display("%s accum_mem.%s seed=%0d beats_in=%0d rows_out=%0d fwd_cases=%0d ovf_checks=%0d ovf_events=%0d errors=%0d",
               ok ? "PASS" : "FAIL", get_type_name(), seed, env.sb.n_in, env.sb.n_out,
               env.sb.n_fwd, env.sb.n_ovf_checks, env.sb.n_ovf_events, errs);
    endfunction
  endclass

  class accum_mem_directed_test extends accum_mem_base_test;
    `uvm_component_utils(accum_mem_directed_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_seq();
      accum_mem_directed_seq seq = accum_mem_directed_seq::type_id::create("seq");
      min_fwd = 1;
      env.drv.pct_ready = 60;
      seq.start(env.sqr);
      n_sent = seq.n_beats;
    endtask
  endclass

  class accum_mem_random_test extends accum_mem_base_test;
    `uvm_component_utils(accum_mem_random_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    virtual function void knobs(accum_mem_random_seq seq);
      env.drv.pct_ready = 70;
      seq.pct_gap = 30;
      seq.pct_big = 2;
    endfunction
    task run_seq();
      accum_mem_random_seq seq = accum_mem_random_seq::type_id::create("seq");
      knobs(seq);
      seq.start(env.sqr);
      n_sent = seq.n_beats;
    endtask
  endclass

  // Heavy backpressure, no idle gaps: stage 1 stalls on last rows, in_ready drops.
  class accum_mem_backpressure_test extends accum_mem_random_test;
    `uvm_component_utils(accum_mem_backpressure_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void knobs(accum_mem_random_seq seq);
      env.drv.pct_ready = 25;
      seq.pct_gap = 0;
      seq.pct_big = 2;
    endfunction
  endclass

endpackage : accum_mem_pkg
