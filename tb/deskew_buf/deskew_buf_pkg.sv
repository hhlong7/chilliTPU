`include "uvm_macros.svh"
package deskew_buf_pkg;
  import uvm_pkg::*;
  localparam int COLS=dnn_pkg::COLS, DATA_W=dnn_pkg::PSUM_W;
  typedef logic signed [DATA_W-1:0] data_t;

  class deskew_item extends uvm_sequence_item;
    bit advance, in_valid, out_valid;
    data_t in_data[COLS], out_data[COLS];
    `uvm_object_utils(deskew_item)
    function new(string name="deskew_item"); super.new(name); endfunction
  endclass

  class deskew_seq extends uvm_sequence #(deskew_item);
    bit random_mode;
    int unsigned cycles=300;
    `uvm_object_utils(deskew_seq)
    function new(string name="deskew_seq"); super.new(name); endfunction
    task body();
      data_t d[COLS];
      for(int i=0;i<cycles+COLS+4;i++) begin
        bit adv, valid;
        if(random_mode) begin
          adv=$urandom_range(0,99)<80;
          valid=$urandom_range(0,99)<75;
          foreach(d[c]) d[c]=data_t'($urandom);
        end else begin
          adv=(i%13!=5 && i%13!=6);
          valid=(i<4 || i%9!=4);
          foreach(d[c]) begin
            case(i%4)
              0:d[c]=data_t'(i*COLS+c);
              1:d[c]=0;
              2:d[c]=data_t'(-2147483647-1);
              default:d[c]=data_t'(2147483647-c);
            endcase
          end
          if(i>=cycles) valid=0;
        end
        deskew_item it=deskew_item::type_id::create("cycle");
        start_item(it); it.advance=adv; it.in_valid=valid;
        foreach(d[c]) it.in_data[c]=d[c]; finish_item(it);
      end
    endtask
  endclass

  class deskew_driver extends uvm_driver #(deskew_item);
    virtual deskew_buf_if vif;
    `uvm_component_utils(deskew_driver)
    function new(string n,uvm_component p);super.new(n,p);endfunction
    function void build_phase(uvm_phase phase);
      if(!uvm_config_db#(virtual deskew_buf_if)::get(this,"","vif",vif)) `uvm_fatal("NOVIF","no interface")
    endfunction
    task run_phase(uvm_phase phase);
      vif.advance<=0;vif.in_valid<=0;foreach(vif.in_data[c])vif.in_data[c]<=0;
      @(posedge vif.rst_n);
      forever begin
        deskew_item it;seq_item_port.get_next_item(it);@(negedge vif.clk);
        vif.advance<=it.advance;vif.in_valid<=it.in_valid;
        foreach(it.in_data[c])vif.in_data[c]<=it.in_data[c];seq_item_port.item_done();
      end
    endtask
  endclass

  class deskew_monitor extends uvm_monitor;
    virtual deskew_buf_if vif;uvm_analysis_port #(deskew_item) ap;
    `uvm_component_utils(deskew_monitor)
    function new(string n,uvm_component p);super.new(n,p);ap=new("ap",this);endfunction
    function void build_phase(uvm_phase phase);
      if(!uvm_config_db#(virtual deskew_buf_if)::get(this,"","vif",vif)) `uvm_fatal("NOVIF","no interface")
    endfunction
    task run_phase(uvm_phase phase);
      forever begin @(posedge vif.clk); if(vif.rst_n) begin
        deskew_item it=deskew_item::type_id::create("sample");
        it.advance=vif.advance;it.in_valid=vif.in_valid;it.out_valid=vif.out_valid;
        foreach(it.in_data[c])begin it.in_data[c]=vif.in_data[c];it.out_data[c]=vif.out_data[c];end
        ap.write(it);
      end end
    endtask
  endclass

  class deskew_scoreboard extends uvm_scoreboard;
    uvm_analysis_imp #(deskew_item,deskew_scoreboard) imp;
    data_t q[COLS][COLS]; bit v[COLS][COLS]; data_t last_q;bit last_v;
    int unsigned checks,errors;
    `uvm_component_utils(deskew_scoreboard)
    function new(string n,uvm_component p);super.new(n,p);imp=new("imp",this);
      foreach(q[c,s])begin q[c][s]=0;v[c][s]=0;end last_q=0;last_v=0;endfunction
    function void write(deskew_item it);
      bit ev=last_v;checks++;
      if(it.out_data[COLS-1]!==last_q)begin errors++;`uvm_error("SB","last column data mismatch")end
      for(int c=0;c<COLS-1;c++)begin
        if(it.out_data[c]!==q[c][COLS-2-c])begin errors++;`uvm_error("SB",$sformatf("column %0d data mismatch",c))end
        ev &= v[c][COLS-2-c];
      end
      if(it.out_valid!==ev)begin errors++;`uvm_error("SB","out_valid mismatch")end
      if(it.advance)begin
        last_q=it.in_valid?it.in_data[COLS-1]:'0;last_v=it.in_valid;
        for(int c=0;c<COLS-1;c++)begin
          for(int s=COLS-2-c;s>0;s--)begin q[c][s]=q[c][s-1];v[c][s]=v[c][s-1];end
          q[c][0]=it.in_valid?it.in_data[c]:'0;v[c][0]=it.in_valid;
        end
      end
    endfunction
  endclass

  class deskew_env extends uvm_env;
    deskew_driver drv;deskew_monitor mon;deskew_scoreboard sb;uvm_sequencer #(deskew_item) sqr;
    `uvm_component_utils(deskew_env)
    function new(string n,uvm_component p);super.new(n,p);endfunction
    function void build_phase(uvm_phase phase);
      drv=deskew_driver::type_id::create("drv",this);mon=deskew_monitor::type_id::create("mon",this);
      sb=deskew_scoreboard::type_id::create("sb",this);sqr=uvm_sequencer#(deskew_item)::type_id::create("sqr",this);
    endfunction
    function void connect_phase(uvm_phase phase);drv.seq_item_port.connect(sqr.seq_item_export);mon.ap.connect(sb.imp);endfunction
  endclass

  class deskew_test extends uvm_test;
    deskew_env env;int unsigned seed;bit random_mode;
    `uvm_component_utils(deskew_test)
    function new(string n,uvm_component p);super.new(n,p);endfunction
    function void build_phase(uvm_phase phase);if(!$value$plusargs("SEED=%d",seed))seed=0;env=deskew_env::type_id::create("env",this);endfunction
    task run_phase(uvm_phase phase);deskew_seq seq=deskew_seq::type_id::create("seq");phase.raise_objection(this);seq.random_mode=random_mode;seq.start(env.sqr);repeat(2)@(posedge env.drv.vif.clk);phase.drop_objection(this);endtask
    function void report_phase(uvm_phase phase);uvm_report_server rs=uvm_report_server::get_server();int e=rs.get_severity_count(UVM_ERROR)+rs.get_severity_count(UVM_FATAL);$display("%s deskew_buf.%s seed=%0d checks=%0d errors=%0d",(e==0&&env.sb.checks>0)?"PASS":"FAIL",get_type_name(),seed,env.sb.checks,e);endfunction
  endclass
  class deskew_random_test extends deskew_test;
    `uvm_component_utils(deskew_random_test)
    function new(string n,uvm_component p);super.new(n,p);endfunction
    function void build_phase(uvm_phase phase);super.build_phase(phase);random_mode=1;endfunction
  endclass
endpackage
