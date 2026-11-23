`include "uvm_macros.svh"

package systolic_array_pkg;
  timeunit 1ns;
  timeprecision 1ps;

  import uvm_pkg::*;
  import tb_common_pkg::hex_vector_reader;
  import dnn_pkg::*;

  // Edge t accepts X[m]. The aligned result is sampled at edge t + LATENCY.
  localparam int LATENCY = 1 + ROWS + COLS;

  class array_cycle extends uvm_sequence_item;
    logic rst_n = 1;
    logic advance = 0, feed_valid = 0, deskew_in_valid = 0;
    logic w_load = 0, w_swap = 0;
    logic feed_ready, skew_valid, deskew_valid;
    logic [COLS-1:0] mul_en = '0;
    data_t x [ROWS] = '{default:'0};
    data_t weights [COLS] = '{default:'0};
    psum_t result [COLS];
    `uvm_object_utils(array_cycle)

    function new(string name = "array_cycle");
      super.new(name);
    endfunction
  endclass

  class array_tile_seq extends uvm_sequence #(array_cycle);
    hex_vector_reader vec;
    bit exercise_gap;
    `uvm_object_utils(array_tile_seq)

    function new(string name = "array_tile_seq");
      super.new(name);
    endfunction

    task send_cycle(array_cycle item);
      start_item(item);
      finish_item(item);
    endtask

    task body();
      array_cycle item;
      int slots, m;
      slots = vec.M + int'(exercise_gap);
      m = 0;

      item = new("reset");
      item.rst_n = 0;
      send_cycle(item);

      // Load the complete shadow chain bottom first, including padded rows.
      for (int r = ROWS-1; r >= 0; r--) begin
        item = new("load_weights");
        item.w_load = 1;
        for (int c = 0; c < COLS; c++)
          if (r < vec.K && c < vec.N)
            item.weights[c] = data_t'(vec.w[r*vec.N+c]);
        send_cycle(item);
      end

      item = new("activate_weights");
      item.w_swap = 1;
      send_cycle(item);

      for (int t = 0; t < slots + LATENCY + 2; t++) begin
        item = new("stream_or_drain");
        item.advance = 1;
        // Column 0 presents the first result at edge ROWS+1. The last
        // column presents the final result COLS-1 edges after column 0.
        item.deskew_in_valid = (t >= ROWS+1 && t < slots+ROWS+COLS);
        for (int c = 0; c < vec.N; c++) item.mul_en[c] = 1;
        item.feed_valid = (t < slots && !(exercise_gap && t == 1));
        if (item.feed_valid) begin
          for (int k = 0; k < vec.K; k++) item.x[k] = data_t'(vec.x[m*vec.K+k]);
          m++;
        end
        // In the robustness case, freeze the whole core at the first result.
        if (exercise_gap && t == LATENCY) begin
          item.advance = 0;
          send_cycle(item);
          item.advance = 1;
        end
        send_cycle(item);
      end
    endtask
  endclass

  class array_driver extends uvm_driver #(array_cycle);
    virtual systolic_array_if vif;
    `uvm_component_utils(array_driver)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      if (!uvm_config_db#(virtual systolic_array_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "array driver interface missing")
    endfunction

    task run_phase(uvm_phase phase);
      forever begin
        array_cycle item;
        seq_item_port.get_next_item(item);
        @(negedge vif.clk);
        vif.rst_n <= item.rst_n;
        vif.advance <= item.advance;
        vif.feed_valid <= item.feed_valid;
        vif.deskew_in_valid <= item.deskew_in_valid;
        vif.w_load <= item.w_load;
        vif.w_swap <= item.w_swap;
        vif.mul_en <= item.mul_en;
        vif.x <= item.x;
        vif.weights <= item.weights;
        @(posedge vif.clk);
        #1ps;
        seq_item_port.item_done();
      end
    endtask
  endclass

  class array_monitor extends uvm_monitor;
    virtual systolic_array_if vif;
    uvm_analysis_port #(array_cycle) samples;
    `uvm_component_utils(array_monitor)

    function new(string name, uvm_component parent);
      super.new(name, parent);
      samples = new("samples", this);
    endfunction

    function void build_phase(uvm_phase phase);
      if (!uvm_config_db#(virtual systolic_array_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "array monitor interface missing")
    endfunction

    task run_phase(uvm_phase phase);
      forever begin
        array_cycle item;
        @(posedge vif.clk);
        item = new("sample");
        item.rst_n = vif.rst_n;
        item.advance = vif.advance;
        item.feed_valid = vif.feed_valid;
        item.feed_ready = vif.feed_ready;
        item.deskew_in_valid = vif.deskew_in_valid;
        item.skew_valid = vif.skew_valid;
        item.deskew_valid = vif.deskew_valid;
        item.x = vif.x;
        item.result = vif.result;
        samples.write(item);
      end
    endtask
  endclass

  class array_scoreboard extends uvm_scoreboard;
    uvm_analysis_imp #(array_cycle, array_scoreboard) samples;
    hex_vector_reader vec;
    string case_name;
    // Append one entry per advance, including empty slots. Index by edge
    // number so row identity does not depend on either buffer's out_valid.
    int row_at_edge[$];
    bit deskew_window[$];
    int accepted, matched, total_rows, gap_checks, stall_checks;
    bit exercise_gap;
    `uvm_component_utils(array_scoreboard)

    function new(string name, uvm_component parent);
      super.new(name, parent);
      samples = new("samples", this);
    endfunction

    function void write(array_cycle item);
      int t, row_id, next_row, slots;
      bit expected_skew, expected_deskew, expected_window;
      psum_t expected;

      if (!item.rst_n) begin
        row_at_edge.delete();
        deskew_window.delete();
        accepted = 0;
        matched = 0;
        return;
      end
      if (vec == null) return;

      t = row_at_edge.size();
      slots = vec.M + int'(exercise_gap);
      row_id = (t >= LATENCY) ? row_at_edge[t-LATENCY] : -1;

      expected_skew = (t >= ROWS);
      for (int r = 1; r <= ROWS && expected_skew; r++)
        expected_skew = row_at_edge[t-r] >= 0;
      expected_deskew = (t >= COLS);
      for (int c = 1; c <= COLS && expected_deskew; c++)
        expected_deskew = deskew_window[t-c];
      expected_window = (t >= ROWS+1 && t < slots+ROWS+COLS);
      if (item.deskew_in_valid !== expected_window)
        `uvm_error("WINDOW", $sformatf("%s edge=%0d deskew input valid=%b expected=%b",
                                      case_name, t, item.deskew_in_valid, expected_window))
      if (item.skew_valid !== expected_skew || item.deskew_valid !== expected_deskew)
        `uvm_error("VALID", $sformatf("%s edge=%0d skew=%b/%b deskew=%b/%b (got/expected)",
                                    case_name, t, item.skew_valid, expected_skew,
                                    item.deskew_valid, expected_deskew))
      if (!exercise_gap && item.deskew_valid !== (row_id >= 0))
        `uvm_error("LATENCY", $sformatf("%s edge=%0d expected row=%0d latency=%0d",
                                      case_name, t, row_id, LATENCY))

      for (int c = 0; c < COLS; c++) begin
        expected = '0;
        if (row_id >= 0 && row_id < vec.M && c < vec.N)
          expected = psum_t'(vec.acc_expected[row_id*vec.N+c]);
        if (item.result[c] !== expected)
          `uvm_error("ACC", $sformatf("%s edge=%0d row=%0d col=%0d got=%0d expected=%0d",
                                     case_name, t, row_id, c, item.result[c], expected))
      end

      if (!item.advance) begin
        if (row_id >= 0) stall_checks++;
        return;
      end
      if (row_id >= 0) begin
        if (row_id != matched)
          `uvm_error("ORDER", $sformatf("%s expected row %0d, history returned %0d",
                                       case_name, matched, row_id))
        matched++;
        total_rows++;
      end else if (exercise_gap && t == LATENCY+1 && item.deskew_valid) begin
        gap_checks++;
      end

      next_row = -1;
      if (item.feed_valid && item.feed_ready) begin
        next_row = accepted++;
        if (next_row >= vec.M) begin
          `uvm_error("FEED", $sformatf("%s accepted an extra row at edge=%0d", case_name, t))
        end else begin
          foreach (item.x[k]) begin
            data_t expected_x;
            expected_x = k < vec.K ? data_t'(vec.x[next_row*vec.K+k]) : '0;
            if (item.x[k] !== expected_x)
              `uvm_error("FEED", $sformatf("%s row=%0d k=%0d got=%0d expected=%0d",
                                          case_name, next_row, k, item.x[k], expected_x))
          end
        end
      end
      row_at_edge.push_back(next_row);
      deskew_window.push_back(item.deskew_in_valid);
    endfunction
  endclass

  class array_env extends uvm_env;
    array_driver driver;
    array_monitor monitor;
    array_scoreboard scoreboard;
    uvm_sequencer #(array_cycle) sequencer;
    `uvm_component_utils(array_env)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      driver = array_driver::type_id::create("driver", this);
      monitor = array_monitor::type_id::create("monitor", this);
      scoreboard = array_scoreboard::type_id::create("scoreboard", this);
      sequencer = new("sequencer", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      driver.seq_item_port.connect(sequencer.seq_item_export);
      monitor.samples.connect(scoreboard.samples);
    endfunction
  endclass

  class array_core_test extends uvm_test;
    array_env env;
    int seed, cases;
    string vector_root = "vectors/systolic_array";
    `uvm_component_utils(array_core_test)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      env = array_env::type_id::create("env", this);
      void'($value$plusargs("SEED=%d", seed));
    endfunction

    task run_case(string name, bit exercise_gap = 0);
      array_tile_seq seq;
      hex_vector_reader vec;
      vec = new("vectors");
      vec.load({vector_root, "/", name});
      if (vec.M <= 0 || vec.K <= 0 || vec.N <= 0 || vec.K > ROWS || vec.N > COLS ||
          vec.x_count != vec.M*vec.K || vec.w_count != vec.K*vec.N ||
          vec.acc_count != vec.M*vec.N) begin
        `uvm_fatal("VEC", $sformatf("%s: invalid single-tile dimensions or vector counts", name))
      end
      env.scoreboard.vec = vec;
      env.scoreboard.case_name = name;
      env.scoreboard.exercise_gap = exercise_gap;
      seq = new("tile");
      seq.vec = vec;
      seq.exercise_gap = exercise_gap;
      seq.start(env.sequencer);
      if (env.scoreboard.accepted != vec.M || env.scoreboard.matched != vec.M)
        `uvm_error("COUNT", $sformatf("%s accepted=%0d compared=%0d expected=%0d",
                                    name, env.scoreboard.accepted, env.scoreboard.matched, vec.M))
      `uvm_info("CASE", $sformatf("%s gap=%b rows=%0d latency=%0d",
                                 name, exercise_gap, env.scoreboard.matched, LATENCY), UVM_LOW)
      cases++;
    endtask

    task run_phase(uvm_phase phase);
      int vector_probe;
      phase.raise_objection(this);
      if (!$value$plusargs("ARRAY_VECTOR_ROOT=%s", vector_root)) begin
        // xsim runs from build/systolic_array/xsim.
        vector_probe = $fopen({vector_root, "/tile_1x12x12/meta.txt"}, "r");
        if (vector_probe) $fclose(vector_probe);
        else vector_root = {"../../../", vector_root};
      end
      run_case("tile_1x12x12");
      run_case("tile_12x12x12");
      run_case("tile_20x12x12");
      run_case("tile_6x5x7");
      run_case("tile_10x12x1");
      run_case("tile_10x1x12");
      run_case("extremes");
      run_case("tile_20x12x12", 1);
      if (env.scoreboard.gap_checks != 1 || env.scoreboard.stall_checks != 1)
        `uvm_error("COVERAGE", "expected one empty slot with scalar valid high and one stalled result")
      phase.drop_objection(this);
    endtask

    function void report_phase(uvm_phase phase);
      uvm_report_server server;
      int errors;
      server = uvm_report_server::get_server();
      errors = server.get_severity_count(UVM_ERROR) + server.get_severity_count(UVM_FATAL);
      $display("%s systolic_array.%s seed=%0d cases=%0d rows=%0d latency=%0d errors=%0d",
               errors == 0 && cases == 8 ? "PASS" : "FAIL", get_type_name(), seed,
               cases, env.scoreboard.total_rows, LATENCY, errors);
    endfunction
  endclass
endpackage : systolic_array_pkg
