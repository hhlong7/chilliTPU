// Cycle-level UVM verification for skew_buf. Inputs are driven on falling
// edges; the scoreboard models row-index delays in array-advance cycles.
`include "uvm_macros.svh"

package skew_buf_pkg;
  import uvm_pkg::*;

  localparam int ROWS = dnn_pkg::ROWS;
  localparam int DATA_W = dnn_pkg::DATA_W;
  typedef logic signed [DATA_W-1:0] data_t;

  class skew_buf_item extends uvm_sequence_item;
    bit advance;
    bit in_valid;
    data_t in_data[ROWS];
    bit out_valid;
    data_t out_data[ROWS];
    `uvm_object_utils(skew_buf_item)
    function new(string name = "skew_buf_item"); super.new(name); endfunction
  endclass

  class skew_buf_seq extends uvm_sequence #(skew_buf_item);
    int unsigned n_cycles = 300;
    bit random_mode;
    `uvm_object_utils(skew_buf_seq)
    function new(string name = "skew_buf_seq"); super.new(name); endfunction

    task send_cycle(bit advance, bit valid, data_t values[ROWS]);
      skew_buf_item it = skew_buf_item::type_id::create("cycle");
      start_item(it);
      it.advance = advance;
      it.in_valid = valid;
      foreach (values[r]) it.in_data[r] = values[r];
      finish_item(it);
    endtask

    task body();
      data_t values[ROWS];
      // Initial all-zero/min/max patterns expose row swaps and sign errors.
      for (int pattern = 0; pattern < 4; pattern++) begin
        foreach (values[r]) begin
          case (pattern)
            0: values[r] = data_t'(r);
            1: values[r] = '0;
            2: values[r] = data_t'(-128);
            default: values[r] = data_t'(127-r);
          endcase
        end
        send_cycle(1, 1, values);
      end
      repeat (n_cycles) begin
        bit adv, valid;
        if (random_mode) begin
          adv = ($urandom_range(0, 99) < 75);
          valid = ($urandom_range(0, 99) < 80);
          foreach (values[r]) values[r] = data_t'($urandom);
        end else begin
          // Directed stalls and bubbles, followed by a continuous stream.
          int unsigned i = n_cycles;
          adv = ((i % 11) != 4 && (i % 11) != 5);
          valid = ((i % 7) != 3);
          foreach (values[r]) values[r] = data_t'((i * 13 + r * 29) & 'hff);
          n_cycles--;
        end
        send_cycle(adv, valid, values);
      end
      // Flush the maximum skew delay so every accepted bundle is observed.
      repeat (ROWS + 2) begin
        foreach (values[r]) values[r] = '0;
        send_cycle(1, 0, values);
      end
    endtask
  endclass

  class skew_buf_driver extends uvm_driver #(skew_buf_item);
    virtual skew_buf_if vif;
    `uvm_component_utils(skew_buf_driver)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
      if (!uvm_config_db#(virtual skew_buf_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "skew_buf virtual interface not configured")
    endfunction
    task run_phase(uvm_phase phase);
      vif.advance <= 0; vif.in_valid <= 0;
      foreach (vif.in_data[r]) vif.in_data[r] <= '0;
      @(posedge vif.rst_n);
      forever begin
        skew_buf_item it;
        seq_item_port.get_next_item(it);
        @(negedge vif.clk);
        vif.advance <= it.advance;
        vif.in_valid <= it.in_valid;
        foreach (it.in_data[r]) vif.in_data[r] <= it.in_data[r];
        seq_item_port.item_done();
      end
    endtask
  endclass

  class skew_buf_monitor extends uvm_monitor;
    virtual skew_buf_if vif;
    uvm_analysis_port #(skew_buf_item) ap;
    `uvm_component_utils(skew_buf_monitor)
    function new(string name, uvm_component parent);
      super.new(name, parent); ap = new("ap", this);
    endfunction
    function void build_phase(uvm_phase phase);
      if (!uvm_config_db#(virtual skew_buf_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "skew_buf virtual interface not configured")
    endfunction
    task run_phase(uvm_phase phase);
      forever begin
        @(posedge vif.clk);
        if (vif.rst_n) begin
          skew_buf_item it = skew_buf_item::type_id::create("observed_cycle");
          it.advance = vif.advance;
          it.in_valid = vif.in_valid;
          foreach (it.in_data[r]) it.in_data[r] = vif.in_data[r];
          it.out_valid = vif.out_valid;
          foreach (it.out_data[r]) it.out_data[r] = vif.out_data[r];
          ap.write(it);
        end
      end
    endtask
  endclass

  class skew_buf_scoreboard extends uvm_scoreboard;
    uvm_analysis_imp #(skew_buf_item, skew_buf_scoreboard) imp;
    data_t model_data[ROWS][ROWS];
    bit model_valid[ROWS][ROWS];
    data_t row0_model;
    bit row0_valid;
    int unsigned checked, errors;
    `uvm_component_utils(skew_buf_scoreboard)
    function new(string name, uvm_component parent);
      super.new(name, parent); imp = new("imp", this);
      foreach (model_data[r,s]) begin model_data[r][s] = '0; model_valid[r][s] = 0; end
      row0_model = '0; row0_valid = 0;
    endfunction
    function void write(skew_buf_item it);
      bit exp_valid;
      checked++;
      exp_valid = row0_valid;
      foreach (it.out_data[r]) begin
        data_t exp_data;
        if (r == 0) exp_data = row0_model;
        else begin exp_data = model_data[r][r-1]; exp_valid &= model_valid[r][r-1]; end
        if (it.out_data[r] !== exp_data) begin
          errors++;
          `uvm_error("SKEW_SB", $sformatf("cycle %0d row %0d data got=%0d expected=%0d", checked, r, it.out_data[r], exp_data))
        end
      end
      if (it.out_valid !== exp_valid) begin
        errors++;
        `uvm_error("SKEW_SB", $sformatf("cycle %0d out_valid got=%b expected=%b", checked, it.out_valid, exp_valid))
      end

      // Model post-edge state. Data advances only on the shared array enable.
      if (it.advance) begin
        row0_model = it.in_valid ? it.in_data[0] : '0;
        row0_valid = it.in_valid;
        for (int r = 1; r < ROWS; r++) begin
          for (int s = r-1; s > 0; s--) begin
            model_data[r][s] = model_data[r][s-1];
            model_valid[r][s] = model_valid[r][s-1];
          end
          model_data[r][0] = it.in_valid ? it.in_data[r] : '0;
          model_valid[r][0] = it.in_valid;
        end
      end
    endfunction
  endclass

`ifndef VERILATOR
  class skew_buf_coverage extends uvm_subscriber #(skew_buf_item);
    skew_buf_item item;
    covergroup cg;
      cp_advance: coverpoint item.advance;
      cp_valid: coverpoint item.in_valid;
      cp_flow: cross cp_advance, cp_valid;
      cp_out: coverpoint item.out_valid;
    endgroup
    `uvm_component_utils(skew_buf_coverage)
    function new(string name, uvm_component parent); super.new(name,parent); cg = new(); endfunction
    function void write(skew_buf_item t); item = t; cg.sample(); endfunction
  endclass
`endif

  class skew_buf_env extends uvm_env;
    skew_buf_driver drv;
    skew_buf_monitor mon;
    skew_buf_scoreboard sb;
    uvm_sequencer #(skew_buf_item) sqr;
`ifndef VERILATOR
    skew_buf_coverage cov;
`endif
    `uvm_component_utils(skew_buf_env)
    function new(string name, uvm_component parent); super.new(name,parent); endfunction
    function void build_phase(uvm_phase phase);
      drv=skew_buf_driver::type_id::create("drv",this);
      mon=skew_buf_monitor::type_id::create("mon",this);
      sb=skew_buf_scoreboard::type_id::create("sb",this);
      sqr=uvm_sequencer#(skew_buf_item)::type_id::create("sqr",this);
`ifndef VERILATOR
      cov=skew_buf_coverage::type_id::create("cov",this);
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

  class skew_buf_test extends uvm_test;
    skew_buf_env env;
    int unsigned seed, sent;
    bit random_mode;
    `uvm_component_utils(skew_buf_test)
    function new(string name, uvm_component parent); super.new(name,parent); endfunction
    function void build_phase(uvm_phase phase);
      if (!$value$plusargs("SEED=%d", seed)) seed=0;
      void'($value$plusargs("RANDOM_MODE=%d", random_mode));
      env=skew_buf_env::type_id::create("env",this);
    endfunction
    task run_phase(uvm_phase phase);
      skew_buf_seq seq=skew_buf_seq::type_id::create("seq");
      phase.raise_objection(this);
      seq.random_mode=random_mode;
      seq.start(env.sqr);
      sent=seq.n_cycles+4+ROWS+2;
      repeat (2) @(posedge env.drv.vif.clk);
      phase.drop_objection(this);
    endtask
    function void report_phase(uvm_phase phase);
      uvm_report_server rs=uvm_report_server::get_server();
      int errs=rs.get_severity_count(UVM_ERROR)+rs.get_severity_count(UVM_FATAL);
      bit ok=(errs==0)&&(env.sb.checked>0)&&(env.sb.errors==0);
      $display("%s skew_buf.%s seed=%0d checked=%0d errors=%0d", ok?"PASS":"FAIL", get_type_name(), seed, env.sb.checked, errs);
    endfunction
  endclass

  class skew_buf_random_test extends skew_buf_test;
    `uvm_component_utils(skew_buf_random_test)
    function new(string name, uvm_component parent); super.new(name,parent); endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      random_mode=1;
    endfunction
  endclass

endpackage : skew_buf_pkg
