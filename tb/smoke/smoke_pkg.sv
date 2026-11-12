// smoke_pkg.sv - minimal but complete UVM env: item, sequence, driver, monitor,
// scoreboard, env, test. Use it as the pattern for module envs.

`include "uvm_macros.svh"

package smoke_pkg;
  import uvm_pkg::*;

  class smoke_item extends uvm_sequence_item;
    rand logic signed [7:0] a, b;
    logic signed [8:0]      y;
    `uvm_object_utils(smoke_item)
    function new(string name = "smoke_item"); super.new(name); endfunction
    function string convert2string(); return $sformatf("a=%0d b=%0d y=%0d", a, b, y); endfunction
  endclass

  class smoke_seq extends uvm_sequence #(smoke_item);
    int unsigned n_items = 50;
    `uvm_object_utils(smoke_seq)
    function new(string name = "smoke_seq"); super.new(name); endfunction
    task body();
      // Edge cases first, then random
      int edges[4][2] = '{'{-128, -128}, '{127, 127}, '{-128, 127}, '{0, 0}};
      foreach (edges[i]) begin
        smoke_item it = smoke_item::type_id::create("edge");
        start_item(it); it.a = 8'(edges[i][0]); it.b = 8'(edges[i][1]); finish_item(it);
      end
      repeat (n_items - 4) begin
        smoke_item it = smoke_item::type_id::create("rnd");
        start_item(it);
        if (!it.randomize()) `uvm_error("RAND", "randomize failed")
        finish_item(it);
      end
    endtask
  endclass

  class smoke_driver extends uvm_driver #(smoke_item);
    virtual smoke_if vif;
    `uvm_component_utils(smoke_driver)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
      if (!uvm_config_db#(virtual smoke_if)::get(this, "", "vif", vif)) `uvm_fatal("NOVIF", "no vif")
    endfunction
    task run_phase(uvm_phase phase);
      vif.in_valid <= 1'b0;
      @(posedge vif.rst_n);
      forever begin
        smoke_item it;
        seq_item_port.get_next_item(it);
        @(negedge vif.clk);
        vif.a <= it.a; vif.b <= it.b; vif.in_valid <= 1'b1;
        @(negedge vif.clk);
        vif.in_valid <= 1'b0;
        seq_item_port.item_done();
      end
    endtask
  endclass

  class smoke_monitor extends uvm_monitor;
    virtual smoke_if vif;
    uvm_analysis_port #(smoke_item) ap;
    `uvm_component_utils(smoke_monitor)
    function new(string name, uvm_component parent); super.new(name, parent); ap = new("ap", this); endfunction
    function void build_phase(uvm_phase phase);
      if (!uvm_config_db#(virtual smoke_if)::get(this, "", "vif", vif)) `uvm_fatal("NOVIF", "no vif")
    endfunction
    task run_phase(uvm_phase phase);
      logic signed [7:0] a_q, b_q;
      forever begin
        @(posedge vif.clk);
        if (vif.rst_n && vif.out_valid) begin
          smoke_item it = smoke_item::type_id::create("mon");
          it.a = a_q; it.b = b_q; it.y = vif.y;
          ap.write(it);
        end
        a_q = vif.a; b_q = vif.b;   // inputs that produce next cycle's output
      end
    endtask
  endclass

  class smoke_scoreboard extends uvm_scoreboard;
    uvm_analysis_imp #(smoke_item, smoke_scoreboard) imp;
    int unsigned n_checked, n_errors;
    `uvm_component_utils(smoke_scoreboard)
    function new(string name, uvm_component parent); super.new(name, parent); imp = new("imp", this); endfunction
    function void write(smoke_item it);
      logic signed [8:0] exp = 9'(it.a) + 9'(it.b);   // reference model
      n_checked++;
      if (it.y !== exp) begin
        n_errors++;
        `uvm_error("SB", $sformatf("%s expected y=%0d", it.convert2string(), exp))
      end
    endfunction
  endclass

  class smoke_env extends uvm_env;
    smoke_driver              drv;
    smoke_monitor             mon;
    smoke_scoreboard          sb;
    uvm_sequencer #(smoke_item) sqr;
    `uvm_component_utils(smoke_env)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
      drv = smoke_driver::type_id::create("drv", this);
      mon = smoke_monitor::type_id::create("mon", this);
      sb  = smoke_scoreboard::type_id::create("sb", this);
      sqr = uvm_sequencer#(smoke_item)::type_id::create("sqr", this);
    endfunction
    function void connect_phase(uvm_phase phase);
      drv.seq_item_port.connect(sqr.seq_item_export);
      mon.ap.connect(sb.imp);
    endfunction
  endclass

  // Pattern for every test: print the seed, run, then one PASS/FAIL line.
  class smoke_test extends uvm_test;
    smoke_env    env;
    int unsigned seed;
    int unsigned n_items = 50;
    `uvm_component_utils(smoke_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
      if (!$value$plusargs("SEED=%d", seed)) seed = 0;
      env = smoke_env::type_id::create("env", this);
    endfunction
    task run_phase(uvm_phase phase);
      smoke_seq seq = smoke_seq::type_id::create("seq");
      seq.n_items = n_items;
      phase.raise_objection(this);
      `uvm_info("SEED", $sformatf("seed=%0d", seed), UVM_NONE)
      seq.start(env.sqr);
      repeat (3) @(posedge env.drv.vif.clk);   // drain the pipeline
      phase.drop_objection(this);
    endtask
    function void report_phase(uvm_phase phase);
      uvm_report_server rs = uvm_report_server::get_server();
      int errs = rs.get_severity_count(UVM_ERROR) + rs.get_severity_count(UVM_FATAL);
      bit ok = (errs == 0) && (env.sb.n_checked == n_items);
      $display("%s smoke.%s seed=%0d checked=%0d errors=%0d",
               ok ? "PASS" : "FAIL", get_type_name(), seed, env.sb.n_checked, errs);
    endfunction
  endclass

endpackage : smoke_pkg
