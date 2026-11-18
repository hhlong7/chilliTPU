// bram_sdp_pkg.sv - UVM environment for bram_sdp (simple dual-port BRAM, read latency 1, read-first).
//
// One item = the BRAM inputs for one clock cycle (same style as pe_pkg). The driver
// applies an item on the falling edge; the monitor samples every rising edge. The
// scoreboard keeps a model of the memory and checks rd_data / rd_valid every cycle.
//
// Every test ends with exactly one line:  PASS bram_sdp.<test> seed=<s> ...  or  FAIL ...

`include "uvm_macros.svh"

package bram_sdp_pkg;
  import uvm_pkg::*;

  // Small DEPTH on purpose: random addresses collide often (same-address read/write).
  localparam int DATA_W = 32;
  localparam int DEPTH  = 16;
  localparam int ADDR_W = $clog2(DEPTH);

  typedef logic [DATA_W-1:0] word_t;
  typedef logic [ADDR_W-1:0] addr_t;
  typedef virtual bram_sdp_if #(DATA_W, ADDR_W) vif_t;

  // ------------------------------------------------------------------ item
  class bram_sdp_item extends uvm_sequence_item;
    // inputs
    bit    wr_en, rd_en;
    addr_t wr_addr, rd_addr;
    word_t wr_data;
    // outputs (filled by the monitor)
    word_t rd_data;
    bit    rd_valid;
    `uvm_object_utils(bram_sdp_item)
    function new(string name = "bram_sdp_item"); super.new(name); endfunction
    function string convert2string();
      return $sformatf("wr_en=%0b wr_addr=%0d wr_data=%h rd_en=%0b rd_addr=%0d | rd_valid=%0b rd_data=%h",
                       wr_en, wr_addr, wr_data, rd_en, rd_addr, rd_valid, rd_data);
    endfunction
  endclass

  // ------------------------------------------------------------------ sequences
  class bram_sdp_base_seq extends uvm_sequence #(bram_sdp_item);
    int unsigned n_sent;
    `uvm_object_utils(bram_sdp_base_seq)
    function new(string name = "bram_sdp_base_seq"); super.new(name); endfunction

    // send one cycle of inputs
    task cyc(bit wr = 0, addr_t wa = 0, word_t wd = 0, bit rd = 0, addr_t ra = 0);
      bram_sdp_item it = bram_sdp_item::type_id::create("it");
      start_item(it);
      it.wr_en = wr; it.wr_addr = wa; it.wr_data = wd; it.rd_en = rd; it.rd_addr = ra;
      finish_item(it);
      n_sent++;
    endtask

    task write(addr_t a, word_t d); cyc(.wr(1), .wa(a), .wd(d)); endtask
    task read(addr_t a);            cyc(.rd(1), .ra(a));          endtask

    // write every address once, so later reads never see uninitialized memory
    task fill();
      for (int a = 0; a < DEPTH; a++) write(addr_t'(a), rand_word());
    endtask

    function word_t rand_word();
      case ($urandom_range(0, 7))   // bias toward the patterns that catch stuck/swapped bits
        0: return '0;
        1: return '1;
        2: return word_t'(32'h8000_0000);
        3: return word_t'(32'h5555_5555);
        default: return word_t'($urandom);
      endcase
    endfunction
  endclass

  // Directed: fill + read back, read-first, hold, overwrite, simultaneous read/write.
  class bram_sdp_directed_seq extends bram_sdp_base_seq;
    `uvm_object_utils(bram_sdp_directed_seq)
    function new(string name = "bram_sdp_directed_seq"); super.new(name); endfunction
    task body();
      // 1) every address gets a unique pattern, read back-to-back
      for (int a = 0; a < DEPTH; a++) write(addr_t'(a), word_t'({8'(a), 24'hC0FFEE}));
      for (int a = 0; a < DEPTH; a++) read(addr_t'(a));
      // 2) hold: no read for several cycles, rd_data must not change
      repeat (4) cyc();
      // 3) read-first: write and read the same address in one cycle returns the OLD data
      cyc(.wr(1), .wa(3), .wd(32'hDEAD_BEEF), .rd(1), .ra(3));
      read(3);                                            // now the new data
      // 4) overwrite the same address back-to-back: the last write wins
      write(5, 32'h1111_1111); write(5, 32'h2222_2222); read(5);
      // 5) write one address while reading another
      cyc(.wr(1), .wa(0), .wd('1), .rd(1), .ra(DEPTH - 1));
      read(0);
      // 6) all-zeros / all-ones / MSB only at the top address
      write(DEPTH - 1, '0); read(DEPTH - 1);
      write(DEPTH - 1, '1); read(DEPTH - 1);
      write(DEPTH - 1, 32'h8000_0000); read(DEPTH - 1);
      repeat (3) cyc();
    endtask
  endclass

  // Random: fill, then random reads/writes with addresses biased to collide.
  class bram_sdp_random_seq extends bram_sdp_base_seq;
    int unsigned n_cycles = 3000;
    int unsigned pct_wr = 50, pct_rd = 60, pct_same_addr = 25;
    `uvm_object_utils(bram_sdp_random_seq)
    function new(string name = "bram_sdp_random_seq"); super.new(name); endfunction
    task body();
      fill();
      repeat (n_cycles) begin
        addr_t wa = addr_t'($urandom_range(0, DEPTH - 1));
        addr_t ra = ($urandom_range(0, 99) < pct_same_addr) ? wa : addr_t'($urandom_range(0, DEPTH - 1));
        cyc(.wr($urandom_range(0, 99) < pct_wr), .wa(wa), .wd(rand_word()),
            .rd($urandom_range(0, 99) < pct_rd), .ra(ra));
      end
    endtask
  endclass

  // ------------------------------------------------------------------ driver
  class bram_sdp_driver extends uvm_driver #(bram_sdp_item);
    vif_t vif;
    `uvm_component_utils(bram_sdp_driver)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
      if (!uvm_config_db#(vif_t)::get(this, "", "vif", vif)) `uvm_fatal("NOVIF", "no vif")
    endfunction
    task run_phase(uvm_phase phase);
      vif.wr_en <= 0; vif.wr_addr <= 0; vif.wr_data <= 0; vif.rd_en <= 0; vif.rd_addr <= 0;
      @(posedge vif.rst_n);
      forever begin
        bram_sdp_item it;
        seq_item_port.get_next_item(it);
        @(negedge vif.clk);
        vif.wr_en <= it.wr_en; vif.wr_addr <= it.wr_addr; vif.wr_data <= it.wr_data;
        vif.rd_en <= it.rd_en; vif.rd_addr <= it.rd_addr;
        seq_item_port.item_done();
      end
    endtask
  endclass

  // ------------------------------------------------------------------ monitor
  class bram_sdp_monitor extends uvm_monitor;
    vif_t vif;
    uvm_analysis_port #(bram_sdp_item) ap;
    `uvm_component_utils(bram_sdp_monitor)
    function new(string name, uvm_component parent); super.new(name, parent); ap = new("ap", this); endfunction
    function void build_phase(uvm_phase phase);
      if (!uvm_config_db#(vif_t)::get(this, "", "vif", vif)) `uvm_fatal("NOVIF", "no vif")
    endfunction
    task run_phase(uvm_phase phase);
      forever begin
        @(posedge vif.clk);
        if (vif.rst_n === 1'b1) begin
          bram_sdp_item it = bram_sdp_item::type_id::create("mon");
          it.wr_en = vif.wr_en; it.wr_addr = vif.wr_addr; it.wr_data = vif.wr_data;
          it.rd_en = vif.rd_en; it.rd_addr = vif.rd_addr;
          it.rd_data = vif.rd_data; it.rd_valid = vif.rd_valid;
          ap.write(it);
        end
      end
    endtask
  endclass

  // ------------------------------------------------------------------ reference model + scoreboard
  class bram_sdp_scoreboard extends uvm_scoreboard;
    uvm_analysis_imp #(bram_sdp_item, bram_sdp_scoreboard) imp;
    int unsigned n_cycles, n_reads_checked, n_errors, n_read_first;
    // reference state after the last rising edge
    word_t mem     [DEPTH];
    bit    written [DEPTH];      // never compare data the DUT was never given
    word_t rd_data;
    bit    rd_known;             // rd_data holds a defined value
    bit    rd_valid;             // reset value 0
    `uvm_component_utils(bram_sdp_scoreboard)
    function new(string name, uvm_component parent); super.new(name, parent); imp = new("imp", this); endfunction

    function void write(bram_sdp_item it);
      // 1) outputs seen at this edge come from the previous edge
      n_cycles++;
      if (it.rd_valid !== rd_valid) begin
        n_errors++;
        `uvm_error("SB", $sformatf("cycle %0d: rd_valid=%0b expected %0b", n_cycles, it.rd_valid, rd_valid))
      end
      if (rd_known) begin
        if (rd_valid) n_reads_checked++;
        if (it.rd_data !== rd_data) begin
          n_errors++;
          `uvm_error("SB", $sformatf("cycle %0d: got %s | expected rd_data=%h", n_cycles, it.convert2string(), rd_data))
        end
      end
      // 2) advance the model: read FIRST (sees the old word), then write
      rd_valid = it.rd_en;
      if (it.rd_en) begin
        rd_data  = mem[it.rd_addr];
        rd_known = written[it.rd_addr];
        if (it.wr_en && it.wr_addr == it.rd_addr) n_read_first++;
      end
      if (it.wr_en) begin
        mem[it.wr_addr]     = it.wr_data;
        written[it.wr_addr] = 1;
      end
    endfunction
  endclass

`ifndef VERILATOR
  // ------------------------------------------------------------------ coverage (xsim only)
  class bram_sdp_coverage extends uvm_subscriber #(bram_sdp_item);
    bram_sdp_item it;
    covergroup cg;
      cp_ops:  coverpoint {it.wr_en, it.rd_en};
      cp_same: coverpoint (it.wr_en && it.rd_en && it.wr_addr == it.rd_addr);
      cp_ra:   coverpoint it.rd_addr iff (it.rd_en) { bins lo = {0}; bins hi = {DEPTH - 1}; bins mid = default; }
      cp_wa:   coverpoint it.wr_addr iff (it.wr_en) { bins lo = {0}; bins hi = {DEPTH - 1}; bins mid = default; }
    endgroup
    `uvm_component_utils(bram_sdp_coverage)
    function new(string name, uvm_component parent); super.new(name, parent); cg = new(); endfunction
    function void write(bram_sdp_item t); it = t; cg.sample(); endfunction
  endclass
`endif

  // ------------------------------------------------------------------ env
  class bram_sdp_env extends uvm_env;
    bram_sdp_driver               drv;
    bram_sdp_monitor              mon;
    bram_sdp_scoreboard           sb;
    uvm_sequencer #(bram_sdp_item) sqr;
`ifndef VERILATOR
    bram_sdp_coverage             cov;
`endif
    `uvm_component_utils(bram_sdp_env)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
      drv = bram_sdp_driver::type_id::create("drv", this);
      mon = bram_sdp_monitor::type_id::create("mon", this);
      sb  = bram_sdp_scoreboard::type_id::create("sb", this);
      sqr = uvm_sequencer#(bram_sdp_item)::type_id::create("sqr", this);
`ifndef VERILATOR
      cov = bram_sdp_coverage::type_id::create("cov", this);
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
  class bram_sdp_base_test extends uvm_test;
    bram_sdp_env env;
    int unsigned seed;
    int unsigned n_sent;
    `uvm_component_utils(bram_sdp_base_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
      if (!$value$plusargs("SEED=%d", seed)) seed = 0;
      env = bram_sdp_env::type_id::create("env", this);
    endfunction
    virtual task run_seq(); endtask
    task run_phase(uvm_phase phase);
      phase.raise_objection(this);
      `uvm_info("SEED", $sformatf("seed=%0d", seed), UVM_NONE)
      run_seq();
      repeat (3) @(posedge env.drv.vif.clk);   // let the last read reach the scoreboard
      phase.drop_objection(this);
    endtask
    function void report_phase(uvm_phase phase);
      uvm_report_server rs = uvm_report_server::get_server();
      int errs = rs.get_severity_count(UVM_ERROR) + rs.get_severity_count(UVM_FATAL);
      bit ok = (errs == 0) && (n_sent > 0) && (env.sb.n_reads_checked > 0);
      $display("%s bram_sdp.%s seed=%0d cycles=%0d reads_checked=%0d read_first=%0d errors=%0d",
               ok ? "PASS" : "FAIL", get_type_name(), seed, env.sb.n_cycles,
               env.sb.n_reads_checked, env.sb.n_read_first, errs);
    endfunction
  endclass

  class bram_sdp_directed_test extends bram_sdp_base_test;
    `uvm_component_utils(bram_sdp_directed_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_seq();
      bram_sdp_directed_seq seq = bram_sdp_directed_seq::type_id::create("seq");
      seq.start(env.sqr);
      n_sent = seq.n_sent;
    endtask
  endclass

  class bram_sdp_random_test extends bram_sdp_base_test;
    `uvm_component_utils(bram_sdp_random_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_seq();
      bram_sdp_random_seq seq = bram_sdp_random_seq::type_id::create("seq");
      seq.start(env.sqr);
      n_sent = seq.n_sent;
    endtask
  endclass

endpackage : bram_sdp_pkg
