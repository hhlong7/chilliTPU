// pe_pkg.sv - UVM environment for pe (D4: global en, weight shift chain + shadow, piped Mul_En).
//
// One item = the PE inputs for one clock cycle. The driver applies an item on the
// falling edge; the monitor samples every rising edge (inputs about to be
// registered, plus the outputs left by the previous edge). The scoreboard keeps a
// cycle-accurate reference model of the PE and checks all four outputs every cycle.
//
// Stimulus uses $urandom (seeded by +verilator+seed / -sv_seed) instead of
// constraints, so the env runs the same way in Verilator and xsim.
//
// Every test ends with exactly one line:  PASS pe.<test> seed=<s> ...  or  FAIL ...

`include "uvm_macros.svh"

package pe_pkg;
  import uvm_pkg::*;

  localparam int DATA_W = dnn_pkg::DATA_W;
  localparam int PSUM_W = dnn_pkg::PSUM_W;

  typedef logic signed [DATA_W-1:0] data_t;
  typedef logic signed [PSUM_W-1:0] psum_t;

  // ------------------------------------------------------------------ item
  class pe_item extends uvm_sequence_item;
    // inputs
    bit    en = 1, w_load, w_swap, mul_en_in = 1;
    data_t w_in, a_in;
    psum_t psum_in;
    // outputs (filled by the monitor)
    data_t w_out, a_out;
    bit    mul_en_out;
    psum_t psum_out;
    `uvm_object_utils(pe_item)
    function new(string name = "pe_item"); super.new(name); endfunction
    function string convert2string();
      return $sformatf("en=%0b w_load=%0b w_swap=%0b w_in=%0d mul_en=%0b a_in=%0d psum_in=%0d | w_out=%0d mul_en_out=%0b a_out=%0d psum_out=%0d",
                       en, w_load, w_swap, w_in, mul_en_in, a_in, psum_in, w_out, mul_en_out, a_out, psum_out);
    endfunction
  endclass

  // ------------------------------------------------------------------ sequences
  class pe_base_seq extends uvm_sequence #(pe_item);
    int unsigned n_sent;
    `uvm_object_utils(pe_base_seq)
    function new(string name = "pe_base_seq"); super.new(name); endfunction

    // send one cycle of inputs
    task cyc(bit en = 1, bit w_load = 0, bit w_swap = 0, data_t w_in = 0,
             bit mul_en = 1, data_t a = 0, psum_t psum = 0);
      pe_item it = pe_item::type_id::create("it");
      start_item(it);
      it.en = en; it.w_load = w_load; it.w_swap = w_swap; it.w_in = w_in;
      it.mul_en_in = mul_en; it.a_in = a; it.psum_in = psum;
      finish_item(it);
      n_sent++;
    endtask

    // load a weight into the shadow register, then make it active
    task load_weight(data_t w);
      cyc(.w_load(1), .w_in(w));
      cyc(.w_swap(1));
    endtask

    function data_t rand_data();
      case ($urandom_range(0, 7))   // bias toward the extremes
        0: return data_t'(-128);
        1: return data_t'(127);
        2: return data_t'(0);
        default: return data_t'($urandom);
      endcase
    endfunction

    function psum_t rand_psum();
      case ($urandom_range(0, 7))
        0: return psum_t'(32'h8000_0000);       // INT32 min
        1: return psum_t'(32'h7FFF_FFFF);       // INT32 max (sum wraps like the RTL)
        2: return psum_t'(0);
        3: return psum_t'($signed($urandom_range(0, 1 << 20)) - (1 << 19));
        default: return psum_t'($urandom);
      endcase
    endfunction
  endclass

  // Directed: every corner product, Mul_En off, stalls, load during compute, load+swap together.
  class pe_directed_seq extends pe_base_seq;
    `uvm_object_utils(pe_directed_seq)
    function new(string name = "pe_directed_seq"); super.new(name); endfunction
    task body();
      data_t corners[5] = '{-128, -1, 0, 1, 127};
      foreach (corners[i]) begin
        load_weight(corners[i]);
        foreach (corners[j]) begin
          cyc(.a(corners[j]), .psum(0));
          cyc(.a(corners[j]), .psum(1000));
          cyc(.a(corners[j]), .psum(-1000));
        end
      end
      // Mul_En off: psum passes through, a still forwarded
      load_weight(127);
      repeat (4) cyc(.mul_en(0), .a(127), .psum(42));
      // stall for several cycles with changing inputs: outputs must hold
      cyc(.a(5), .psum(7));
      repeat (5) cyc(.en(0), .a(rand_data()), .psum(rand_psum()), .mul_en(1'($urandom)));
      cyc(.a(-3), .psum(9));
      // load the next weight while computing (shadow), swap later
      cyc(.w_load(1), .w_in(-128), .a(10), .psum(0));
      cyc(.a(10), .psum(0));                 // still uses 127
      cyc(.w_swap(1), .a(10), .psum(0));
      cyc(.a(10), .psum(0));                 // now -128
      // load and swap on the same cycle: active takes the OLD shadow value
      cyc(.w_load(1), .w_swap(1), .w_in(55), .a(2));
      cyc(.a(2));                            // still -128
      cyc(.w_swap(1), .a(2));
      cyc(.a(2));                            // now 55
      // weight load during a stall still shifts
      cyc(.en(0), .w_load(1), .w_in(-7));
      cyc(.w_swap(1));
      cyc(.a(-128), .psum(psum_t'(32'h7FFF_FFFF)));   // wrap-around matches 32-bit RTL
      repeat (3) cyc();
    endtask
  endclass

  // Random: every input random each cycle, with tunable rates.
  class pe_random_seq extends pe_base_seq;
    int unsigned n_cycles = 2000;
    int unsigned pct_en = 85, pct_load = 15, pct_swap = 10, pct_mul_en = 80;
    `uvm_object_utils(pe_random_seq)
    function new(string name = "pe_random_seq"); super.new(name); endfunction
    task body();
      repeat (n_cycles)
        cyc(.en($urandom_range(0, 99) < pct_en), .w_load($urandom_range(0, 99) < pct_load),
            .w_swap($urandom_range(0, 99) < pct_swap), .w_in(rand_data()),
            .mul_en($urandom_range(0, 99) < pct_mul_en), .a(rand_data()), .psum(rand_psum()));
    endtask
  endclass

  // ------------------------------------------------------------------ driver
  class pe_driver extends uvm_driver #(pe_item);
    virtual pe_if vif;
    `uvm_component_utils(pe_driver)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
      if (!uvm_config_db#(virtual pe_if)::get(this, "", "vif", vif)) `uvm_fatal("NOVIF", "no vif")
    endfunction
    task run_phase(uvm_phase phase);
      vif.en <= 0; vif.w_load <= 0; vif.w_swap <= 0; vif.w_in <= 0;
      vif.mul_en_in <= 0; vif.a_in <= 0; vif.psum_in <= 0;
      @(posedge vif.rst_n);
      forever begin
        pe_item it;
        seq_item_port.get_next_item(it);
        @(negedge vif.clk);
        vif.en <= it.en; vif.w_load <= it.w_load; vif.w_swap <= it.w_swap; vif.w_in <= it.w_in;
        vif.mul_en_in <= it.mul_en_in; vif.a_in <= it.a_in; vif.psum_in <= it.psum_in;
        seq_item_port.item_done();
      end
    endtask
  endclass

  // ------------------------------------------------------------------ monitor
  class pe_monitor extends uvm_monitor;
    virtual pe_if vif;
    uvm_analysis_port #(pe_item) ap;
    `uvm_component_utils(pe_monitor)
    function new(string name, uvm_component parent); super.new(name, parent); ap = new("ap", this); endfunction
    function void build_phase(uvm_phase phase);
      if (!uvm_config_db#(virtual pe_if)::get(this, "", "vif", vif)) `uvm_fatal("NOVIF", "no vif")
    endfunction
    task run_phase(uvm_phase phase);
      forever begin
        @(posedge vif.clk);
        if (vif.rst_n === 1'b1) begin
          pe_item it = pe_item::type_id::create("mon");
          it.en = vif.en; it.w_load = vif.w_load; it.w_swap = vif.w_swap; it.w_in = vif.w_in;
          it.mul_en_in = vif.mul_en_in; it.a_in = vif.a_in; it.psum_in = vif.psum_in;
          it.w_out = vif.w_out; it.mul_en_out = vif.mul_en_out; it.a_out = vif.a_out; it.psum_out = vif.psum_out;
          ap.write(it);
        end
      end
    endtask
  endclass

  // ------------------------------------------------------------------ reference model + scoreboard
  class pe_scoreboard extends uvm_scoreboard;
    uvm_analysis_imp #(pe_item, pe_scoreboard) imp;
    int unsigned n_checked, n_errors, n_products;
    // reference state = register values after the last rising edge (reset values first)
    data_t w_shadow, w_active, a_out;
    bit    mul_en_out;
    psum_t psum_out;
    `uvm_component_utils(pe_scoreboard)
    function new(string name, uvm_component parent); super.new(name, parent); imp = new("imp", this); endfunction

    function void write(pe_item it);
      // 1) the outputs seen at this edge come from the previous edge
      n_checked++;
      if (it.w_out !== w_shadow || it.a_out !== a_out || it.mul_en_out !== mul_en_out || it.psum_out !== psum_out) begin
        n_errors++;
        `uvm_error("SB", $sformatf("cycle %0d: got %s | expected w_out=%0d mul_en_out=%0b a_out=%0d psum_out=%0d",
                   n_checked, it.convert2string(), w_shadow, mul_en_out, a_out, psum_out))
      end
      // 2) advance the model with the inputs registered at this edge
      if (it.en) begin
        longint prod = longint'(it.a_in) * longint'(w_active);
        if (it.mul_en_in && prod != 0) n_products++;
        psum_out   = psum_t'(longint'(it.psum_in) + (it.mul_en_in ? prod : 0));   // 32-bit wrap like the RTL
        a_out      = it.a_in;
        mul_en_out = it.mul_en_in;
      end
      if (it.w_swap) w_active = w_shadow;   // old shadow value (non-blocking in RTL)
      if (it.w_load) w_shadow = it.w_in;
    endfunction
  endclass

`ifndef VERILATOR
  // ------------------------------------------------------------------ coverage (xsim only; Verilator ignores covergroups)
  class pe_coverage extends uvm_subscriber #(pe_item);
    pe_item it;
    covergroup cg;
      cp_a:      coverpoint it.a_in { bins min = {-128}; bins max = {127}; bins zero = {0}; bins neg = {[-127:-1]}; bins pos = {[1:126]}; }
      cp_w:      coverpoint it.w_in { bins min = {-128}; bins max = {127}; bins zero = {0}; bins other = default; }
      cp_ctrl:   coverpoint {it.en, it.mul_en_in, it.w_load, it.w_swap};
      x_a_w:     cross cp_a, cp_w;
    endgroup
    `uvm_component_utils(pe_coverage)
    function new(string name, uvm_component parent); super.new(name, parent); cg = new(); endfunction
    function void write(pe_item t); it = t; cg.sample(); endfunction
  endclass
`endif

  // ------------------------------------------------------------------ env
  class pe_env extends uvm_env;
    pe_driver               drv;
    pe_monitor              mon;
    pe_scoreboard           sb;
    uvm_sequencer #(pe_item) sqr;
`ifndef VERILATOR
    pe_coverage             cov;
`endif
    `uvm_component_utils(pe_env)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
      drv = pe_driver::type_id::create("drv", this);
      mon = pe_monitor::type_id::create("mon", this);
      sb  = pe_scoreboard::type_id::create("sb", this);
      sqr = uvm_sequencer#(pe_item)::type_id::create("sqr", this);
`ifndef VERILATOR
      cov = pe_coverage::type_id::create("cov", this);
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
  class pe_base_test extends uvm_test;
    pe_env       env;
    int unsigned seed;
    int unsigned n_sent;
    `uvm_component_utils(pe_base_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
      if (!$value$plusargs("SEED=%d", seed)) seed = 0;
      env = pe_env::type_id::create("env", this);
    endfunction
    virtual task run_seq(); endtask
    task run_phase(uvm_phase phase);
      phase.raise_objection(this);
      `uvm_info("SEED", $sformatf("seed=%0d", seed), UVM_NONE)
      run_seq();
      repeat (3) @(posedge env.drv.vif.clk);   // let the last item reach the scoreboard
      phase.drop_objection(this);
    endtask
    function void report_phase(uvm_phase phase);
      uvm_report_server rs = uvm_report_server::get_server();
      int errs = rs.get_severity_count(UVM_ERROR) + rs.get_severity_count(UVM_FATAL);
      bit ok = (errs == 0) && (n_sent > 0) && (env.sb.n_checked >= n_sent);
      $display("%s pe.%s seed=%0d cycles=%0d nonzero_products=%0d errors=%0d",
               ok ? "PASS" : "FAIL", get_type_name(), seed, env.sb.n_checked, env.sb.n_products, errs);
    endfunction
  endclass

  class pe_directed_test extends pe_base_test;
    `uvm_component_utils(pe_directed_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_seq();
      pe_directed_seq seq = pe_directed_seq::type_id::create("seq");
      seq.start(env.sqr);
      n_sent = seq.n_sent;
    endtask
  endclass

  class pe_random_test extends pe_base_test;
    `uvm_component_utils(pe_random_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_seq();
      pe_random_seq seq = pe_random_seq::type_id::create("seq");
      seq.start(env.sqr);
      n_sent = seq.n_sent;
    endtask
  endclass

endpackage : pe_pkg
