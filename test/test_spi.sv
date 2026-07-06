`include "uvm_macros.svh"
import uvm_pkg::*;

typedef enum bit [1:0] {READ = 0, WRITE = 1, RESET = 2} oper_mode;

class spi_config extends uvm_object;
    `uvm_object_utils(spi_config)
    uvm_active_passive_enum is_active = UVM_ACTIVE;
    
    function new(string name = "spi_config");
        super.new(name);
    endfunction
endclass

class spi_seq_item extends uvm_sequence_item;
    rand oper_mode op;
    rand bit [7:0] addr;
    rand bit [7:0] din;
    bit [7:0] dout;
    bit err;
    
    `uvm_object_utils_begin(spi_seq_item)
        `uvm_field_enum(oper_mode, op, UVM_ALL_ON)
        `uvm_field_int(addr, UVM_ALL_ON)
        `uvm_field_int(din, UVM_ALL_ON)
        `uvm_field_int(dout, UVM_ALL_ON)
        `uvm_field_int(err, UVM_ALL_ON)
    `uvm_object_utils_end
    
    constraint op_c { op inside {READ, WRITE}; }
    constraint addr_c { addr inside {[0:31]}; }
    
    function new(string name = "spi_seq_item");
        super.new(name);
    endfunction
endclass

class write_sequence extends uvm_sequence#(spi_seq_item);
    `uvm_object_utils(write_sequence)
    int num_write = 10;
    
    function new(string name = "write_sequence");
        super.new(name);
    endfunction
    
    virtual task body();
        for(int i = 0; i < num_write; i++) begin
            req = spi_seq_item::type_id::create("req");
            start_item(req);
            if (!req.randomize()) begin
                `uvm_error("SEQ", "Randomization failed")
            end
            req.op = WRITE;
            finish_item(req);
        end
    endtask
endclass

class read_sequence extends uvm_sequence#(spi_seq_item);
    `uvm_object_utils(read_sequence)
    int num_read = 10;
    
    function new(string name = "read_sequence");
        super.new(name);
    endfunction
    
    virtual task body();
        for(int i = 0; i < num_read; i++) begin
            req = spi_seq_item::type_id::create("req");
            start_item(req);
            if (!req.randomize()) begin
                `uvm_error("SEQ", "Randomization failed")
            end
            req.op = READ;
            finish_item(req);
        end
    endtask
endclass

class spi_driver extends uvm_driver#(spi_seq_item);
    `uvm_component_utils(spi_driver)
    
    virtual spi_i vif;
    
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(virtual spi_i)::get(this, "", "vif", vif))
            `uvm_fatal("DRV", "Could not get vif")
    endfunction
    
    virtual task run_phase(uvm_phase phase);
        reset_dut();
        forever begin
            seq_item_port.get_next_item(req);
            
            if(req.op == RESET) begin
                vif.rst <= 1;
                @(posedge vif.clk);
                vif.rst <= 0;
            end
            else if(req.op == WRITE) begin
                vif.rst <= 0;
                vif.wr <= 1;
                vif.addr <= req.addr;
                vif.din <= req.din;
                @(posedge vif.clk);
                `uvm_info("DRV", $sformatf("DRV mode : Write addr:%0d din:%0d", vif.addr, vif.din), UVM_DEBUG)
                @(posedge vif.done);
                @(negedge vif.done);
            end
            else if(req.op == READ) begin
                vif.rst <= 0;
                vif.wr <= 0;
                vif.addr <= req.addr;
                vif.din <= req.din;
                @(posedge vif.clk);
                `uvm_info("DRV", $sformatf("DRV mode : Read addr:%0d din:%0d", vif.addr, vif.din), UVM_DEBUG)
                @(posedge vif.done);
                @(negedge vif.done);
            end
            
            seq_item_port.item_done();
        end
    endtask
    
    virtual task reset_dut();
        repeat(5) begin
            vif.rst <= 1;
            vif.addr <= 0;
            vif.din <= 0;
            vif.wr <= 0;
            @(posedge vif.clk);
        end
        vif.rst <= 0;
        `uvm_info("DRV", "System Reset : Start of Simulation", UVM_LOW)
    endtask
endclass

class spi_monitor extends uvm_monitor;
    `uvm_component_utils(spi_monitor)
    
    virtual spi_i vif;
    uvm_analysis_port#(spi_seq_item) ap;
    
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
        if(!uvm_config_db#(virtual spi_i)::get(this, "", "vif", vif))
            `uvm_fatal("MON", "Could not get vif")
    endfunction
    
    virtual task run_phase(uvm_phase phase);
        spi_seq_item item;
        forever begin
            @(posedge vif.clk);
            if(vif.rst === 1'b1) begin
                item = spi_seq_item::type_id::create("item");
                item.op = RESET;
                ap.write(item);
                `uvm_info("MON", "SYSTEM RESET DETECTED", UVM_LOW)
                @(negedge vif.rst);
            end
            else if(vif.wr !== 1'bx) begin // Skip if wr is X
                @(posedge vif.done);
                @(negedge vif.done);
                item = spi_seq_item::type_id::create("item");
                item.addr = vif.addr;
                item.err = vif.err;
                
                if(vif.wr === 1'b1) begin
                    item.op = WRITE;
                    item.din = vif.din;
                    `uvm_info("MON", $sformatf("DATA WRITE addr:%0d data:%0d err:%0d", item.addr, item.din, item.err), UVM_LOW)
                end
                else begin
                    item.op = READ;
                    item.dout = vif.dout;
                    `uvm_info("MON", $sformatf("DATA READ addr:%0d data:%0d slverr:%0d", item.addr, item.dout, item.err), UVM_LOW)
                end
                ap.write(item);
            end
        end
    endtask
endclass

class spi_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(spi_scoreboard)
    
    uvm_tlm_analysis_fifo#(spi_seq_item) fifo;
    bit [7:0] arr [32];
    
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        fifo = new("fifo", this);
        foreach(arr[i]) arr[i] = 8'h00;
    endfunction
    
    virtual task run_phase(uvm_phase phase);
        spi_seq_item item;
        forever begin
            fifo.get(item);
            if(item.op == RESET) begin
                `uvm_info("SCO", "SCO SYSTEM RESET DETECTED", UVM_LOW)
            end
            else if(item.op == WRITE) begin
                if(item.err == 1) begin
                    `uvm_info("SCO", "SCO SLV ERROR during WRITE OP", UVM_LOW)
                end
                else begin
                    arr[item.addr] = item.din;
                    `uvm_info("SCO", $sformatf("SCO DATA WRITE OP addr:%0d, wdata:%0d arr_wr:%0d", item.addr, item.din, arr[item.addr]), UVM_LOW)
                end
            end
            else if(item.op == READ) begin
                if(item.err == 1) begin
                    `uvm_info("SCO", "SCO SLV ERROR during READ OP", UVM_LOW)
                end
                else begin
                    if(arr[item.addr] == item.dout) begin
                        `uvm_info("SCO", $sformatf("SCO DATA MATCHED : addr:%0d, rdata:%0d", item.addr, item.dout), UVM_LOW)
                    end
                    else begin
                        `uvm_error("SCO", $sformatf("SCO TEST FAILED : addr:%0d, rdata:%0d expected:%0d", item.addr, item.dout, arr[item.addr]))
                    end
                end
            end
            `uvm_info("SCO", "----------------------------------------------------------------", UVM_LOW)
        end
    endtask
endclass

class spi_agent extends uvm_agent;
    `uvm_component_utils(spi_agent)
    
    spi_config cfg;
    spi_driver drv;
    spi_monitor mon;
    uvm_sequencer#(spi_seq_item) seqr;
    
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        mon = spi_monitor::type_id::create("mon", this);
        if(!uvm_config_db#(spi_config)::get(this, "", "spi_config", cfg)) begin
            cfg = spi_config::type_id::create("spi_config");
        end
        
        if(cfg.is_active == UVM_ACTIVE) begin
            drv = spi_driver::type_id::create("drv", this);
            seqr = new("seqr", this);
        end
    endfunction
    
    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if(cfg.is_active == UVM_ACTIVE) begin
            drv.seq_item_port.connect(seqr.seq_item_export);
        end
    endfunction
endclass

class spi_env extends uvm_env;
    `uvm_component_utils(spi_env)
    
    spi_agent agent;
    spi_scoreboard sco;
    
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent = spi_agent::type_id::create("agent", this);
        sco = spi_scoreboard::type_id::create("sco", this);
    endfunction
    
    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agent.mon.ap.connect(sco.fifo.analysis_export);
    endfunction
endclass

class spi_test extends uvm_test;
    `uvm_component_utils(spi_test)
    
    spi_env env;
    spi_config cfg;
    
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = spi_env::type_id::create("env", this);
        cfg = spi_config::type_id::create("spi_config");
        uvm_config_db#(spi_config)::set(this, "*", "spi_config", cfg);
    endfunction
    
    virtual task run_phase(uvm_phase phase);
        write_sequence wr_seq;
        read_sequence rd_seq;
        
        phase.raise_objection(this);
        
        wr_seq = write_sequence::type_id::create("wr_seq");
        wr_seq.start(env.agent.seqr);
        
        rd_seq = read_sequence::type_id::create("rd_seq");
        rd_seq.start(env.agent.seqr);
        
        #100ns;
        phase.drop_objection(this);
    endtask
endclass

module tb_top;
    logic clk;
    
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    spi_i vif();
    assign vif.clk = clk;
    
    top dut(
        .wr(vif.wr),
        .clk(vif.clk),
        .rst(vif.rst),
        .addr(vif.addr),
        .din(vif.din),
        .dout(vif.dout),
        .done(vif.done),
        .err(vif.err)
    );
    
    initial begin
        uvm_config_db#(virtual spi_i)::set(null, "*", "vif", vif);
        run_test("spi_test");
    end
    
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars;
    end
endmodule
