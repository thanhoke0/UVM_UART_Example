`include "uvm_macros.svh"
import uvm_pkg::*;
`ifndef UART_INTERFACE_SV
`define UART_INTERFACE_SV

interface uart_interface(input clk, input rst_);
    logic sin_data;
    logic sout_data;
    logic rts_n;
    logic cts_n;
    logic dtr_n;
    logic dsr_n;

    clocking mst_cb @(posedge clk);
        default input #1step output #1;
        input sin_data, cts_n, dsr_n;
        output sout_data, rts_n, dtr_n;
    endclocking

    clocking mon_cb @(posedge clk);
        default input #1step output #0;
        input sin_data, cts_n, dsr_n;
        input sout_data, rts_n, dtr_n;
    endclocking
endinterface

`endif
`ifndef CPU_INTR_INTERFACE_SV
`define CPU_INTR_INTERFACE_SV

interface cpu_intr_interface(input clk, input sclk);
    logic interrupt;

    clocking mon_cb @(posedge clk);
        default input #1step output #0;
        input interrupt;
    endclocking

    task idle_sclk(int count);
        repeat(count) @(posedge sclk);
    endtask

    task idle_ahb(int count);
        repeat(count) @mon_cb;
    endtask
endinterface

`endif
package uart_host_pkg;
  `include "uvm_macros.svh"
  import uvm_pkg::*;
//----------------------------------------------------------------------------
//  File Name   : uart_host_config.sv
//  Date        : 8/14/2020
//  Author(s)   : WeiChung Wu (exelion04 at gmail.com)
//  Description : 
//----------------------------------------------------------------------------

`ifndef UART_HOST_CONFIG_SV
`define UART_HOST_CONFIG_SV

class uart_host_config extends uvm_object;
    int id;
    uvm_sequencer_base m_sequencer;     //sequencer in current agent
    virtual uart_interface uart_vif;
    int baud_cnt = 16;
    int half_cnt = 8;
    rand int data_len;           //refer LCR[1:0]
    rand int stop_len;           //refer LCR[2]
    rand bit parity_en;          //refer LCR[3]
    rand bit even_parity;        //refer LCR[4]
    rand bit auto_flow_ctrl;     //refer MCR[5]
    rand int rcv_threshold;      //refer FCR[7:6]

    `uvm_object_utils_begin(uart_host_config)
        `uvm_field_int(id, UVM_ALL_ON|UVM_NOPACK)
        `uvm_field_int(baud_cnt, UVM_ALL_ON|UVM_NOPACK)
        `uvm_field_int(data_len, UVM_ALL_ON|UVM_NOPACK)
        `uvm_field_int(stop_len, UVM_ALL_ON|UVM_NOPACK)
        `uvm_field_int(parity_en, UVM_ALL_ON|UVM_NOPACK)
        `uvm_field_int(even_parity, UVM_ALL_ON|UVM_NOPACK)
        `uvm_field_int(auto_flow_ctrl, UVM_ALL_ON|UVM_NOPACK)
    `uvm_object_utils_end

    function new(string name = "uart_host_config");
        super.new(name);
        half_cnt = baud_cnt/2;
    endfunction : new

    constraint con_data_len {
        data_len inside {[5:8]};
        soft data_len == 8;
    }
    constraint con_stop_len {
        stop_len inside {1,2};
        soft stop_len == 1;
    }
    constraint con_parity_en {
        soft parity_en == 1;
    }
    constraint con_even_parity {
        soft even_parity == 0;
    }
    constraint con_auto_flow_ctrl {
        soft auto_flow_ctrl == 0;
    }
    constraint con_rcv_threshold {
        soft rcv_threshold == 256;
    }

    virtual function void set_sequencer(uvm_sequencer_base seqr);
        m_sequencer = seqr;
    endfunction : set_sequencer

    virtual function uvm_sequencer_base get_sequencer();
        return m_sequencer;
    endfunction : get_sequencer

    virtual function string convert2string();
        string qs[$];
        qs.push_back($sformatf("UART_HOST_CONFIG (type: %0s)\n", get_type_name()));
        qs.push_back($sformatf("  data_len       = %0d\n", data_len));
        qs.push_back($sformatf("  stop_len       = %0d\n", stop_len));
        qs.push_back($sformatf("  parity_en      = %0d\n", parity_en));
        qs.push_back($sformatf("  even_parity    = %0d\n", even_parity));
        qs.push_back($sformatf("  auto_flow_ctrl = %0d\n", auto_flow_ctrl));
        qs.push_back($sformatf("  rcv_threshold  = %0d\n", rcv_threshold));
        return `UVM_STRING_QUEUE_STREAMING_PACK(qs);
    endfunction
endclass : uart_host_config
`endif
//----------------------------------------------------------------------------
//  File Name   : uart_host_sequencer.sv
//  Date        : 8/14/2020
//  Author(s)   : WeiChung Wu (exelion04 at gmail.com)
//  Description : 
//----------------------------------------------------------------------------

`ifndef UART_HOST_SEQUENCER_SV
`define UART_HOST_SEQUENCER_SV

class uart_host_sequencer extends uvm_sequencer;
    `uvm_component_utils(uart_host_sequencer)
    function new(string name = "uart_host_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new
endclass : uart_host_sequencer

`endif
//----------------------------------------------------------------------------
//  File Name   : uart_host_driver.sv
//  Date        : 8/14/2020
//  Author(s)   : WeiChung Wu (exelion04 at gmail.com)
//  Description : 
//----------------------------------------------------------------------------

`ifndef UART_HOST_DRIVER_SV
`define UART_HOST_DRIVER_SV

class uart_host_driver extends uvm_driver;
    uart_host_config cfg;
    virtual uart_interface uart_vif;

    protected bit [7:0] received_data_fifo[$];

    // TX, RX operation can be performed simultaneously
    // In TX or RX operation, one transfer is following previous transfer ended
    protected semaphore tx_lock, rx_lock;

    `uvm_component_utils_begin(uart_host_driver)
        `uvm_field_object(cfg, UVM_DEFAULT|UVM_REFERENCE)
    `uvm_component_utils_end

    function new(string name = "uart_host_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual function void build_phase(uvm_phase phase);
        string val;
        uvm_cmdline_processor clp = uvm_cmdline_processor::get_inst();

        super.build_phase(phase);
        uart_vif = cfg.uart_vif;
        tx_lock = new(1);
        rx_lock = new(1);

        if(!clp.get_arg_value("+UART_DEBUG", val)) begin
            set_report_severity_id_action_hier(UVM_INFO, get_type_name(), UVM_NO_ACTION);
        end
    endfunction : build_phase

    virtual task run_phase(uvm_phase phase);
        uart_vif.sout_data <= 1'b1;
        uart_vif.rts_n <= 1'b1;
        uart_vif.dtr_n <= 1'b1;
        fork
        main_loop();
        receive();
        auto_flow_ctrl();
        join
    endtask : run_phase

    extern virtual task main_loop();
    extern virtual task reset();
    extern virtual task send(ref uart_trans tr);
    extern virtual function bit get_parity(int n, ref uart_trans tr);
    extern virtual task auto_flow_ctrl();
    extern virtual task receive();
    extern virtual task read(ref uart_trans tr);
endclass

task uart_host_driver::main_loop();
    uvm_sequence_item item;
    uart_trans tr;

    forever begin
        seq_item_port.get(item);
        void'($cast(tr, item));
        if(tr==null) `uvm_fatal(get_name(), "casting failed or item returned null")
        if(tr.direction==UART_WRITE) tx_lock.get();
        else                        rx_lock.get();

        fork
        begin
            automatic uart_trans req, rsp;
            req = tr;
            if(req.direction==UART_WRITE) send(req);
            else                         read(req);
            $cast(rsp, req.clone());
            rsp.set_id_info(req);
            seq_item_port.put(rsp);
            if(req.direction==UART_WRITE) tx_lock.put();
            else                         rx_lock.put();
        end
        join_none
    end
endtask

task uart_host_driver::reset();
    forever begin
        @(posedge uart_vif.rst_);
        received_data_fifo.delete();
        uart_vif.sout_data <= 1'b1;
        uart_vif.rts_n <= 1'b1;
        uart_vif.dtr_n <= 1'b1;
    end
endtask

task uart_host_driver::send(ref uart_trans tr);
    `uvm_info(get_type_name(), $sformatf("In send() :\n%s", tr.convert2string()), UVM_MEDIUM)

    repeat (cfg.half_cnt) @(uart_vif.mst_cb);
    for(int n=0; n<tr.byte_array.size(); n++) begin
        if(cfg.auto_flow_ctrl) begin
            wait(uart_vif.cts_n==0);
            @(uart_vif.mst_cb) uart_vif.mst_cb.sout_data <= 1'b0;
        end
        // Send start bit
        uart_vif.mst_cb.sout_data <= 1'b0;
        repeat (cfg.baud_cnt) @(uart_vif.mst_cb);

        for(int i=0; i<cfg.data_len; i++) begin
            uart_vif.mst_cb.sout_data <= tr.byte_array[n][i];
            repeat (cfg.baud_cnt) @(uart_vif.mst_cb);
        end

        // Send parity bit
        if(cfg.parity_en) begin
            uart_vif.mst_cb.sout_data <= get_parity(n, tr);
            repeat (cfg.baud_cnt) @(uart_vif.mst_cb);
        end

        // Send stop bit
        uart_vif.mst_cb.sout_data <= 1'b1;
        repeat (cfg.baud_cnt*cfg.stop_len) @(uart_vif.mst_cb);
        //`uvm_info(tr.get_name(), $sformatf("[H -> D] SOUT_DATA = %2h", tr.byte_array[n]), UVM_MEDIUM)
    end

    `uvm_info(get_type_name(), $sformatf("In send() : end"), UVM_MEDIUM)
endtask

function bit uart_host_driver::get_parity(int n, ref uart_trans tr);
    bit [7:0] data = tr.byte_array[n];
    get_parity = ^{data, ~cfg.even_parity};
    if(tr.strb_array[n]==0) begin //insert parity error, using strb_array to indicate it
        get_parity = ~get_parity;
    end
endfunction

task uart_host_driver::read(ref uart_trans tr);
    `uvm_info(get_type_name(), $sformatf("In read() :\n%s", tr.convert2string()), UVM_MEDIUM)
    for(int n=0; n<tr.byte_array.size(); n++) begin
        wait(received_data_fifo.size()!=0);
        tr.byte_array[n] = received_data_fifo.pop_front();
        //`uvm_info(tr.get_name(), $sformatf("[H <- D] SIN_DATA = %2h", tr.byte_array[n]), UVM_MEDIUM)
    end
    `uvm_info(get_type_name(), $sformatf("In read() : end"), UVM_MEDIUM)
endtask

task uart_host_driver::auto_flow_ctrl();
    forever begin
        if(cfg.auto_flow_ctrl) begin
            if(received_data_fifo.size()==0) begin
                uart_vif.mst_cb.rts_n <= 1'b0;
            end
            else if(received_data_fifo.size()>=(cfg.rcv_threshold-1)) begin
                uart_vif.mst_cb.rts_n <= 1'b1;
            end
        end
        @(uart_vif.mst_cb);
    end
endtask

task uart_host_driver::receive();
    uart_trans  tr;
    bit start_bit_found;
    bit stop_bit_found;
    bit [7:0] rdata;

    forever begin
        //wait start bit
        do begin
            start_bit_found = 1;
            wait(uart_vif.sin_data==0);
            `uvm_info(get_type_name(), $sformatf("Start Bit begins..."), UVM_MEDIUM)
            repeat (cfg.baud_cnt) begin
                @(uart_vif.mst_cb);
                if(uart_vif.mst_cb.sin_data==1) begin
                    start_bit_found = 0;
                    `uvm_info(get_type_name(), $sformatf("Start Bit is aborted, mst_cb.sin_data=%1b", uart_vif.mst_cb.sin_data), UVM_MEDIUM)
                    break;
                end
            end
        end while(!start_bit_found);
        `uvm_info(get_type_name(), $sformatf("Start Bit is detected"), UVM_MEDIUM)

        //receive data bit
        repeat (cfg.half_cnt) @(uart_vif.mst_cb);
        for (int i=0; i<cfg.data_len; i++) begin
            rdata[i] = uart_vif.sin_data;
            `uvm_info(get_type_name(), $sformatf("Receive BIT%0d=%1b", i, rdata[i]), UVM_MEDIUM)
            if(i<cfg.data_len-1) repeat (cfg.baud_cnt) @(uart_vif.mst_cb);
            else    repeat (cfg.baud_cnt-cfg.half_cnt) @(uart_vif.mst_cb);
        end

        if(cfg.parity_en) begin
            repeat (cfg.baud_cnt) @(uart_vif.mst_cb);
        end

        //wait stop bit
        stop_bit_found = 1;
        `uvm_info(get_type_name(), $sformatf("Stop Bit begins"), UVM_MEDIUM)
        repeat (cfg.baud_cnt*cfg.stop_len) begin
            @(uart_vif.mst_cb);
            if(uart_vif.mst_cb.sin_data==0) begin
                stop_bit_found = 0;
                //`uvm_error(get_name(), "Stop bit not received properly")
                break;
            end
        end
        if(stop_bit_found) begin
            received_data_fifo.push_back(rdata);
            `uvm_info(get_type_name(), $sformatf("Stop Bit is detected"), UVM_MEDIUM)
            `uvm_info(get_type_name(), $sformatf("Host received data = %2h", rdata), UVM_MEDIUM)
        end
    end
endtask
`endif

//----------------------------------------------------------------------------
//  File Name   : uart_host_monitor.sv
//  Date        : 8/14/2020
//  Author(s)   : WeiChung Wu (exelion04 at gmail.com)
//  Description : 
//----------------------------------------------------------------------------

`ifndef UART_HOST_MONITOR_SV
`define UART_HOST_MONITOR_SV

class uart_host_monitor extends uvm_monitor;
    uart_host_config cfg;
    virtual uart_interface uart_vif;

    uvm_analysis_port#(uart_trans) tx_trans_ap;
    uvm_analysis_port#(uart_trans) rx_trans_ap;
    uvm_analysis_port#(uart_trans) trans_ap;

    typedef enum bit {TX=1'b0, RX=1'b1} uart_dir_e;

    protected string rpt_id;

    `uvm_component_utils_begin(uart_host_monitor)
        `uvm_field_object(cfg, UVM_DEFAULT|UVM_REFERENCE)
    `uvm_component_utils_end

    function new(string name = "uart_host_monitor", uvm_component parent = null);
        super.new(name, parent);
        tx_trans_ap = new("tx_trans_ap", this);
        rx_trans_ap = new("rx_trans_ap", this);
        trans_ap = new("trans_ap", this);
    endfunction : new

    virtual function void build_phase(uvm_phase phase);
        string val;
        uvm_cmdline_processor clp = uvm_cmdline_processor::get_inst();

        super.build_phase(phase);
        uart_vif = cfg.uart_vif;

        if(!clp.get_arg_value("+UART_DEBUG", val)) begin
            set_report_severity_id_action_hier(UVM_INFO, get_type_name(), UVM_NO_ACTION);
        end
        rpt_id = $sformatf("uart_host_monitor%0d", cfg.id);
    endfunction : build_phase

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
    endfunction : connect_phase

    virtual task run_phase(uvm_phase phase);
        fork
        main_loop(TX);
        main_loop(RX);
        join
    endtask : run_phase

    extern virtual task main_loop(uart_dir_e dir=RX);
    extern virtual function uart_trans transform(bit [7:0] data, uart_dir_e dir=RX);
endclass : uart_host_monitor

task uart_host_monitor::main_loop(uart_dir_e dir=RX);
    bit start_bit_found;
    bit stop_bit_found;
    bit [7:0] rdata;
    string id = {"[",dir.name(),"]"};

    forever begin
        if(cfg.auto_flow_ctrl) begin
            if(dir) wait(uart_vif.rts_n==0);
            else    wait(uart_vif.cts_n==0);
        end
        //wait start bit
        do begin
            start_bit_found = 1;
            if(dir) wait(uart_vif.sin_data==0);
            else    wait(uart_vif.sout_data==0);
            `uvm_info(get_type_name(), $sformatf("%s Start Bit begins...", id), UVM_MEDIUM)
            repeat (cfg.baud_cnt) begin
                @(uart_vif.mon_cb);
                if((uart_vif.mon_cb.sin_data==1&&dir) || (uart_vif.mon_cb.sout_data==1&&~dir)) begin
                    start_bit_found = 0;
                    `uvm_info(get_type_name(), $sformatf("%s Start Bit is aborted, mon_cb.sin_data=%1b", id, uart_vif.mon_cb.sin_data), UVM_MEDIUM)
                    break;
                end
            end
        end while(!start_bit_found);
        `uvm_info(get_type_name(), $sformatf("%s Start Bit is detected", id), UVM_MEDIUM)

        //receive data bit
        repeat (cfg.half_cnt) @(uart_vif.mon_cb);
        for (int i=0; i<cfg.data_len; i++) begin
            if(dir) rdata[i] = uart_vif.mon_cb.sin_data;
            else    rdata[i] = uart_vif.mon_cb.sout_data;
            `uvm_info(get_type_name(), $sformatf("%s Receive BIT%0d=%1b", id, i, rdata[i]), UVM_MEDIUM)
            if(i<7) repeat (cfg.baud_cnt) @(uart_vif.mon_cb);
            else    repeat (cfg.baud_cnt-cfg.half_cnt) @(uart_vif.mon_cb);
        end

        if(cfg.parity_en) begin
            `uvm_info(get_type_name(), $sformatf("%s Parity Bit begins", id), UVM_MEDIUM)
            repeat (cfg.baud_cnt) @(uart_vif.mon_cb);
            `uvm_info(get_type_name(), $sformatf("%s Parity Bit ends", id), UVM_MEDIUM)
        end

        //wait stop bit
        stop_bit_found = 1;
        `uvm_info(get_type_name(), $sformatf("%s Stop Bit begins", id), UVM_MEDIUM)
        repeat (cfg.baud_cnt) begin 
            @(uart_vif.mon_cb);
            if((uart_vif.mon_cb.sin_data==0&&dir) || (uart_vif.mon_cb.sout_data==0&&~dir)) begin
                stop_bit_found = 0;
                break;
            end
        end
        if(stop_bit_found) begin
            `uvm_info(get_type_name(), $sformatf("%s Stop Bit is detected", id), UVM_MEDIUM)
            if(dir) `uvm_info(rpt_id, $sformatf("[H <- D] SIN_DATA = %2h", rdata), UVM_MEDIUM)
            else    `uvm_info(rpt_id, $sformatf("[H -> D] SOUT_DATA = %2h", rdata), UVM_MEDIUM)
            if(dir) rx_trans_ap.write(transform(rdata, dir));
            else    tx_trans_ap.write(transform(rdata, dir));
            trans_ap.write(transform(rdata, dir));
        end
    end
endtask

function uart_trans uart_host_monitor::transform(bit [7:0] data, uart_dir_e dir=RX);
    uart_trans pkt = uart_trans::type_id::create("uart_mon");
    pkt.addr = 64'h0;
    pkt.data_width = DATA_WIDTH_8BIT;
    pkt.burst_length = 1;
    pkt.direction = dir ? UART_READ : UART_WRITE;
    pkt.byte_array = new[1];
    pkt.byte_array[0] = data;
    pkt.data = pkt.unpack_bytestream();
    return pkt;
endfunction
`endif
//----------------------------------------------------------------------------
//  File Name   : uart_host_agent.sv
//  Date        : 8/14/2020
//  Author(s)   : WeiChung Wu (exelion04 at gmail.com)
//  Description : 
//----------------------------------------------------------------------------

`ifndef UART_HOST_AGENT_SV
`define UART_HOST_AGENT_SV

class uart_host_agent extends uvm_agent;
    uart_host_sequencer sequencer;
    uart_host_driver    driver;
    uart_host_monitor   monitor;
    uart_host_config    cfg;

    `uvm_component_utils_begin(uart_host_agent)
        `uvm_field_object(cfg, UVM_DEFAULT|UVM_REFERENCE)
    `uvm_component_utils_end

    function new(string name = "uart_host_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction : new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(is_active == UVM_ACTIVE) begin
            sequencer = uart_host_sequencer::type_id::create("sequencer", this);
            driver = uart_host_driver::type_id::create("driver", this);
            cfg.set_sequencer(sequencer);
        end
        monitor = uart_host_monitor::type_id::create("monitor", this);
    endfunction : build_phase

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if(is_active == UVM_ACTIVE) begin
            driver.seq_item_port.connect(sequencer.seq_item_export);
            driver.rsp_port.connect(sequencer.rsp_export);
        end
    endfunction : connect_phase
endclass : uart_host_agent
`endif
//----------------------------------------------------------------------------
//  File Name   : uart_host_sequence.sv
//  Date        : 8/14/2020
//  Author(s)   : WeiChung Wu (exelion04 at gmail.com)
//  Description : 
//----------------------------------------------------------------------------

`ifndef UART_HOST_SEQUENCE_SV
`define UART_HOST_SEQUENCE_SV

class uart_host_base_sequence extends uvm_sequence#(uart_trans);
    `uvm_object_utils(uart_host_base_sequence)

    local uart_trans tr;     //reuse the constraint solver

    function new(string name = "uart_host_base_sequence");
        super.new(name);
        tr = uart_trans::type_id::create(get_name(),,get_full_name());
    endfunction : new

    virtual function void set_name (string name);
        super.set_name(name);
        tr.set_name(name);
    endfunction

    virtual task body();
    endtask : body

    virtual task pre_start();
        `uvm_info(get_name(), $sformatf("Entering : %0s", get_sequence_path()), UVM_MEDIUM)
    endtask

    virtual task post_start();
        `uvm_info(get_name(), $sformatf("Exiting : %0s", get_sequence_path()), UVM_MEDIUM)
    endtask

    virtual task writeburst(input bit [63:0] addr, input uvm_bitstream_t data,
                            input int length,      input int data_width);
        bit success;
        uart_trans req, rsp;
        // randomize item
        success = tr.randomize() with {addr         == local::addr;
                                       data         == 0;
                                       data_width   == local::data_width;
                                       direction    == UART_WRITE;
                                       burst_length == local::length;
                                       id           == 0;};
        if(!success) `uvm_error(get_name(), {tr.get_type_name()," Randomized failed!"})
        $cast(req, tr.clone());
        req.pack_bytestream(data);
        start_item(req);
        finish_item(req);
        get_response(rsp, req.get_transaction_id());
    endtask

    virtual task readburst(input logic [63:0] addr, output uvm_bitstream_t data,
                           input int length,        input int data_width);
        bit success;
        uart_trans req, rsp;
        // randomize item
        success = tr.randomize() with {addr         == local::addr;
                                       data         == 0;
                                       data_width   == local::data_width;
                                       direction    == UART_READ;
                                       burst_length == local::length;
                                       id           == 0;};
        if(!success) `uvm_error(get_name(), {tr.get_type_name()," Randomized failed!"})
        $cast(req, tr.clone());
        start_item(req);
        finish_item(req);
        get_response(rsp, req.get_transaction_id());
        data = rsp.unpack_bytestream();
    endtask

    virtual task writereg(input logic [63:0] addr, input logic [127:0] data, input int data_width);
        this.writeburst(addr, data, 1, data_width);
    endtask

    virtual task readreg(input logic [63:0] addr, output logic [127:0] data, input int data_width);
        this.readburst(addr, data, 1, data_width);
    endtask

    virtual task write8(input logic [31:0] addr, input logic [7:0] data);
        this.writereg({32'h0,addr}, data, DATA_WIDTH_8BIT);
    endtask

    virtual task read8(input logic [31:0] addr, output logic [7:0] data);
        this.readreg({32'h0,addr}, data, DATA_WIDTH_8BIT);
    endtask

    virtual task write16(input logic [31:0] addr, input logic [15:0] data);
        this.writereg({32'h0,addr}, data, DATA_WIDTH_16BIT);
    endtask

    virtual task read16(input logic [31:0] addr, output logic [15:0] data);
        this.readreg({32'h0,addr}, data, DATA_WIDTH_16BIT);
    endtask

    virtual task write32(input logic [31:0] addr, input logic [31:0] data);
        this.writereg({32'h0,addr}, data, DATA_WIDTH_32BIT);
    endtask

    virtual task read32(input logic [31:0] addr, output logic [31:0] data);
        this.readreg({32'h0,addr}, data, DATA_WIDTH_32BIT);
    endtask
endclass
`endif
//----------------------------------------------------------------------------
//  File Name   : uart_host_sequencer.sv
//  Date        : 8/14/2020
//  Author(s)   : WeiChung Wu (exelion04 at gmail.com)
//  Description : 
//----------------------------------------------------------------------------

`ifndef UART_HOST_SCORE_BOARD_SV
`define UART_HOST_SCORE_BOARD_SV

`uvm_analysis_imp_decl(_exp_tx_in)
`uvm_analysis_imp_decl(_act_tx_in)
`uvm_analysis_imp_decl(_exp_rx_in)
`uvm_analysis_imp_decl(_act_rx_in)

class uart_serial_data extends uvm_object;
    logic [7:0] data;
    bit         parity_err;
    bit         frame_err;
    `uvm_object_utils_begin(uart_serial_data)
        `uvm_field_int      (data,UVM_DEFAULT)
    `uvm_object_utils_end
    function new (string name="uart_serial_data");
        super.new(name);
    endfunction : new
    virtual function string convert2string();
        convert2string = $sformatf("data = %2h", data);
    endfunction : convert2string
endclass: uart_serial_data

class uart_sb_cmd extends uvm_object;
    uart_trans tx_data[$];
    uart_trans rx_data[$];
    `uvm_object_utils_begin(uart_sb_cmd)
    `uvm_object_utils_end

    function new (string name="UART_SB_OP");
        super.new(name);
    endfunction : new

    virtual function void insert_tx_data(bit [7:0] data_in[]);
        foreach(data_in[i]) begin
            tx_data.push_back(transform(data_in[i],0));
        end
        execute(get_name());
    endfunction : insert_tx_data

    virtual function void insert_rx_data(bit [7:0] data_in[]);
        foreach(data_in[i]) begin
            rx_data.push_back(transform(data_in[i],1));
        end
        execute(get_name());
    endfunction : insert_rx_data

    virtual function uart_trans transform(bit [7:0] data, bit dir=1);
        uart_trans pkt = uart_trans::type_id::create("uart_sb_cmd");
        pkt.addr = 64'h0;
        pkt.data_width = DATA_WIDTH_8BIT;
        pkt.burst_length = 1;
        pkt.direction = dir ? UART_READ : UART_WRITE;
        pkt.byte_array = new[1];
        pkt.byte_array[0] = data;
        pkt.data = pkt.unpack_bytestream();
        return pkt;
    endfunction

    virtual function string convert2string();
    endfunction : convert2string

    virtual function void execute(string ev_name);
        uvm_event_pool ep = uvm_event_pool::get_global_pool();
        uvm_event e;
        if(!ep.exists(ev_name)) `uvm_error(get_type_name(), $sformatf("uart_sb_cmd event:%s does not exist!", ev_name))
        else begin e = uvm_event_pool::get_global(ev_name); e.trigger(this); end
    endfunction : execute
endclass: uart_sb_cmd

typedef class uart_host_scoreboard;
class uart_sb_subscriber#(type T=uvm_object) extends uvm_event_callback;
    protected T obs;
    function new(string name="");
        super.new(name);
    endfunction

    virtual function bit pre_trigger(uvm_event e, uvm_object data=null);
        this.obs.observe(e,data);
        return 0;
    endfunction

    virtual function void append_cb(T obs, uvm_event e);
        this.obs = obs;
        `ifdef UVM_VERSION
        uvm_event#()::cbs_type::add(e, this, UVM_APPEND);
        `elsif UVM_MAJOR_REV_1
        e.add_callback(this);
        `endif
    endfunction
endclass

class uart_host_scoreboard extends uvm_scoreboard;
    uvm_queue#(uart_serial_data) m_tx_queue;
    uvm_queue#(uart_serial_data) m_rx_queue;

    uvm_analysis_imp_exp_tx_in#(uart_trans, uart_host_scoreboard) exp_tx_in;
    uvm_analysis_imp_act_tx_in#(uart_trans, uart_host_scoreboard) act_tx_in;
    uvm_analysis_imp_exp_rx_in#(uart_trans, uart_host_scoreboard) exp_rx_in;
    uvm_analysis_imp_act_rx_in#(uart_trans, uart_host_scoreboard) act_rx_in;

    `uvm_component_utils_begin(uart_host_scoreboard)
    `uvm_component_utils_end

    function new (string name = "uart_host_scoreboard", uvm_component parent = null);
        super.new(name, parent);
        exp_tx_in = new("exp_tx_in", this);
        act_tx_in = new("act_tx_in", this);
        exp_rx_in = new("exp_rx_in", this);
        act_rx_in = new("act_rx_in", this);
        m_tx_queue = new();
        m_rx_queue = new();
    endfunction : new

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        event_cb_configure("UART_SB_OP");
    endfunction : build_phase

    virtual task post_main_phase(uvm_phase phase);
        super.post_main_phase(phase);
        check_orphan();
    endtask : post_main_phase

    virtual function void write_exp_tx_in(uvm_object exp_in);
        process_exp_in(exp_in, 0);
    endfunction : write_exp_tx_in

    virtual function void write_exp_rx_in(uvm_object exp_in);
        process_exp_in(exp_in, 1);
    endfunction : write_exp_rx_in

    virtual function void process_exp_in(uvm_object exp_in, bit dir=0);
        uart_trans exp_tmp;
        uart_serial_data exp_pkt;
        string msg = dir ? "RX" : "TX";
        uvm_queue#(uart_serial_data) m_queue = dir ? m_rx_queue : m_tx_queue;
        if ($cast(exp_tmp,exp_in)) begin
            exp_pkt = transform(exp_tmp);
            `uvm_info(get_type_name(), $sformatf("Insert %s Expected : [%0s]", msg, exp_pkt.convert2string()), UVM_MEDIUM)
            m_queue.push_back(exp_pkt);       
        end
    endfunction : process_exp_in

    virtual function void write_act_tx_in(uvm_object act_in);
        process_act_in(act_in, 0);
    endfunction : write_act_tx_in

    virtual function void write_act_rx_in(uvm_object act_in);
        process_act_in(act_in, 1);
    endfunction : write_act_rx_in

    virtual function void process_act_in(uvm_object act_in, bit dir=0);
        uart_trans act_tmp;
        uart_serial_data act_pkt, exp_pkt;
        string msg = dir ? "RX" : "TX";
        uvm_queue#(uart_serial_data) m_queue = dir ? m_rx_queue : m_tx_queue;
        if ($cast(act_tmp,act_in)) begin
            act_pkt = transform(act_tmp);
            if (m_queue.size()) begin
                // In order checking
                `uvm_info(get_type_name(), $sformatf("Compare %s Actual  : [%0s]", msg, act_pkt.convert2string()), UVM_MEDIUM)
                exp_pkt = m_queue.pop_front();
                if (!exp_pkt.compare(act_pkt)) begin
                    `uvm_error(get_type_name(), $sformatf("UART Scoreboard %s expected FAIL => Expected : [%0s], Actual : [%0s]", msg, exp_pkt.convert2string(), act_pkt.convert2string()))
                end
            end
            else begin
                `uvm_error(get_type_name(), $sformatf("FAIL: UART Scoreboard %s is Empty => Actual : [%0s]", msg, act_pkt.convert2string()))
            end
        end
    endfunction : process_act_in

    virtual function void check_orphan();
        if (m_tx_queue.size()) begin
            `uvm_error(get_type_name(), $sformatf("%0s HAS ORPHAN, number = %0d", get_name(), m_tx_queue.size()))
        end
        if (m_rx_queue.size()) begin
            `uvm_error(get_type_name(), $sformatf("%0s HAS ORPHAN, number = %0d", get_name(), m_rx_queue.size()))
        end
    endfunction

    virtual function uart_serial_data transform(uart_trans tr);
        uart_serial_data pkt = uart_serial_data::type_id::create("uart_sb");
        pkt.data = tr.byte_array[0];
        pkt.parity_err = 0;
        pkt.frame_err = 0;
        return pkt;
    endfunction

    virtual function void observe(uvm_event e, uvm_object data=null);
        uart_sb_cmd sb_cmd;
        void'($cast(sb_cmd, data));
        if(sb_cmd.tx_data.size()>0) begin
            foreach(sb_cmd.tx_data[i]) write_act_tx_in(sb_cmd.tx_data[i]);
        end
        if(sb_cmd.rx_data.size()>0) begin
            foreach(sb_cmd.rx_data[i]) write_exp_rx_in(sb_cmd.rx_data[i]);
        end
        sb_cmd.tx_data.delete();
        sb_cmd.rx_data.delete();
    endfunction: observe

    virtual function void event_cb_configure(string ev_name);
        uart_sb_subscriber#(uart_host_scoreboard) cb;
        uvm_event e = uvm_event_pool::get_global(ev_name);
        cb=new(ev_name);
        cb.append_cb(this, e);
    endfunction: event_cb_configure
endclass
`endif
endpackage
import uart_host_pkg::*;
`ifndef UART_FW_SEQ_LIB_SV
`define UART_FW_SEQ_LIB_SV

class uart_fw_base_sequence extends cpu_rw_sequence;
    ral_block_uart uart_reg;
    virtual cpu_intr_interface cpu_intr_vif;
    uvm_status_e status;
    uvm_reg_data_t data, rdata;

    bit [7:0] fcr_wdata = 8'hF7;
    bit [7:0] ier_wdata = 8'h0F;

    `uvm_object_utils(uart_fw_base_sequence)

    function new(string name = "uart_fw_base_sequence");
        super.new(name);
    endfunction : new

    virtual task pre_start();
        uvm_object obj;
        super.pre_start();
        if (!uvm_config_object::get(get_sequencer(), "", "ral_uart_reg", obj)) begin
            `uvm_fatal(get_name(), $sformatf("Can't get uart ral_model"))
        end
        void'($cast(uart_reg, obj));
    endtask

    virtual task write8(input logic [31:0] addr, input logic [7:0] data);
        this.writereg({32'h0,addr}, data, DATA_WIDTH_8BIT);
    endtask

    virtual task read8(input logic [31:0] addr, output logic [7:0] data);
        this.readreg({32'h0,addr}, data, DATA_WIDTH_8BIT);
    endtask

    virtual task read8_cmp(input logic [31:0] addr, input logic [7:0] data);
        logic [7:0] rdata;
        read8(addr, rdata);
        if(rdata!==data) begin
            `uvm_error(get_name(), $sformatf("Read Mismatch: exp=%0x rcv=%0x", data, rdata))
        end
    endtask

    virtual task write16(input logic [31:0] addr, input logic [15:0] data);
        this.writereg({32'h0,addr}, data, DATA_WIDTH_16BIT);
    endtask

    virtual task read16(input logic [31:0] addr, output logic [15:0] data);
        this.readreg({32'h0,addr}, data, DATA_WIDTH_16BIT);
    endtask

    virtual task write32(input logic [31:0] addr, input logic [31:0] data);
        this.writereg({32'h0,addr}, data, DATA_WIDTH_16BIT);
    endtask

    virtual task read32(input logic [31:0] addr, output logic [31:0] data);
        this.readreg({32'h0,addr}, data, DATA_WIDTH_16BIT);
    endtask

    virtual task isr();
        siu_isr();
    endtask

    virtual task siu_isr();
        `uvm_info(get_name(), $sformatf("UART interrupt asserted"), UVM_MEDIUM)
        uart_reg.iir_fcr.read(status, rdata, .parent(this));
        case(rdata[3:0])
            4'b0000 : begin
                `uvm_info(get_name(), $sformatf("Modem status"), UVM_MEDIUM)
                uart_reg.msr.read(status, rdata, .parent(this));
            end
            4'b0010 : begin
                `uvm_info(get_name(), $sformatf("Transmit holding register empty"), UVM_MEDIUM)
            end
            4'b0100 : begin
                `uvm_info(get_name(), $sformatf("Received data available"), UVM_MEDIUM)
            end
            4'b0110 : begin
                `uvm_info(get_name(), $sformatf("Received line status"), UVM_MEDIUM)
                uart_reg.lsr.read(status, rdata, .parent(this));
            end
            4'b0111 : begin
                `uvm_info(get_name(), $sformatf("Bust detect indication"), UVM_MEDIUM)
                uart_reg.usr.read(status, rdata, .parent(this));
            end
            4'b1100 : begin
                `uvm_info(get_name(), $sformatf("Character timeout indication"), UVM_MEDIUM)
            end
            default : begin
                `uvm_info(get_name(), $sformatf("No interrupt pending"), UVM_MEDIUM)
            end
        endcase
    endtask

    virtual task idle(int count);
        cpu_intr_vif.idle_sclk(count);
    endtask

    virtual task wait4Intr();
        wait(cpu_intr_vif.mon_cb.interrupt==1);
        isr();
        idle(16);
    endtask

    //UART subroutines
    virtual task siu_set_data_length(int bit_num=8);
        bit [1:0] dls;
        case(bit_num)
            5: dls = 2'b00;
            6: dls = 2'b01;
            7: dls = 2'b10;
            8: dls = 2'b11;
            default: dls = 2'b11;
        endcase
        reg8_rmw(uart_reg.lcr.wls, dls);
    endtask

    virtual task siu_set_parity_en(bit even_parity=0);
        reg8_rmw(uart_reg.lcr.par_sel, even_parity);
        reg8_rmw(uart_reg.lcr.par_en, 1'b1);
    endtask

    virtual task siu_set_divisor();
        reg8_rmw(uart_reg.lcr.div_latch_rd_wrt, 1'b1);
        uart_reg.dlh_ier.write(status, 8'h00, .parent(this));
        uart_reg.rbr_thr_dll.write(status, 8'h01, .parent(this));
        reg8_rmw(uart_reg.lcr.div_latch_rd_wrt, 1'b0);
    endtask

    virtual task siu_set_fifo_enable();
        uart_reg.iir_fcr.read(status, rdata, .parent(this));
        uart_reg.iir_fcr.write(status, {rdata[7:4],4'h7}, .parent(this));
    endtask

    virtual task siu_set_rcvr_trigger(bit [1:0] trig_lvl);
        fcr_wdata[7:6] = trig_lvl;
        uart_reg.iir_fcr.write(status, fcr_wdata, .parent(this));
    endtask

    virtual task siu_set_tx_empty_trigger(bit [1:0] trig_lvl);
        fcr_wdata[5:4] = trig_lvl;
        uart_reg.iir_fcr.write(status, fcr_wdata, .parent(this));
    endtask
endclass
`endif
`ifndef UART_IP_TB_SV
`define UART_IP_TB_SV

`include "uart_fw_seq_lib.sv"

class uart_ip_tb extends uvm_env;

    `uvm_component_utils(uart_ip_tb)

    uart_host_config       uart_host_cfg;
    uart_host_agent        uart_host;
    uart_host_scoreboard   uart_sb;

    uvm_table_printer printer;

    function new (string name = "uart_ip_tb", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        //UART Host
        uart_host_cfg = uart_host_config::type_id::create("uart_host_cfg");
        if(!uart_host_cfg.randomize())
            `uvm_fatal(get_name(), "uart_host_cfg randomize failed!")
        if (!uvm_config_db#(virtual uart_interface)::get(this, "", "uart_interface", uart_host_cfg.uart_vif)) begin
            `uvm_fatal(get_name(), $sformatf("No virtual uart_interface specified"))
        end
        uvm_config_object::set(this, "uart_host*", "cfg", uart_host_cfg);
        uart_host = uart_host_agent::type_id::create("uart_host", this);
        uart_sb = uart_host_scoreboard::type_id::create("uart_sb", this);
    endfunction : build_phase

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        uart_host.monitor.tx_trans_ap.connect(uart_sb.exp_tx_in);
        uart_host.monitor.rx_trans_ap.connect(uart_sb.act_rx_in);
    endfunction

    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        printer = new();
        printer.knobs.depth = 3;

        begin
            uvm_report_server rs =uvm_report_server::get_server();
            rs.set_max_quit_count(1);
        end

        uvm_report_info(get_type_name(), $psprintf("Printing the test topology :\n%s", this.sprint(printer)), UVM_LOW);

        `uvm_info(get_name(), "Print timescale:", UVM_MEDIUM)
        $printtimescale(tb.top);
    endfunction : end_of_elaboration_phase

    virtual function void start_of_simulation_phase(uvm_phase phase);
        super.start_of_simulation_phase(phase);
    endfunction : start_of_simulation_phase

    virtual task run_phase(uvm_phase phase);
    endtask : run_phase

    virtual task reset_phase(uvm_phase phase);
        phase.raise_objection(this);
        @(posedge tb.top.rstn);
        `uvm_info(get_type_name(), "Reset is done", UVM_MEDIUM)
        phase.drop_objection(this);
    endtask : reset_phase

endclass : uart_ip_tb
`endif
`ifndef UART_BASE_TEST__SV
`define UART_BASE_TEST__SV

class uart_base_test extends uvm_test;

    `uvm_component_utils(uart_base_test)

    uart_ip_tb uarttb;

    function new (string name = "uart_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uarttb = uart_ip_tb::type_id::create("uart_tb", this);
    endfunction : build_phase

    virtual task main_phase(uvm_phase phase);
        phase.raise_objection(this);
        `uvm_info(get_type_name(),"[UART Test] Main Phase", UVM_LOW)
        phase.drop_objection(this);
    endtask : main_phase

endclass : uart_base_test
`endif
`ifndef UART_RDWR_TEST_SV
`define UART_RDWR_TEST_SV

class uart_rdwr_sequence extends uart_host_base_sequence;
    bit [7:0] tx_data[];
    bit [7:0] rx_data[];
    `uvm_object_utils(uart_rdwr_sequence)
    function new(string name = "uart_rdwr_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        bit [7:0] rdata;
        for(int i=0; i<tx_data.size(); i++) begin
            write8(32'h0, tx_data[i]);
        end
        for(int i=0; i<rx_data.size(); i++) begin
            read8(32'h0, rdata);
            `uvm_info(get_name(), $sformatf("[Host] received data = %2h", rdata), UVM_MEDIUM)
            if(rdata!==rx_data[i]) begin
                `uvm_error(get_name(), $sformatf("Host Read Mismatch: exp=%0x rcv=%0x", rx_data[i], rdata))
            end
        end
    endtask
endclass

class uart_fw_rdwr_init_sequence extends uart_fw_base_sequence;
    `uvm_object_utils(uart_fw_rdwr_init_sequence)
    function new(string name = "uart_fw_rdwr_init_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        siu_set_divisor();
        siu_set_data_length();
        siu_set_parity_en();
        siu_set_fifo_enable();
        uart_reg.dlh_ier.write(status, 8'h01, .parent(this));  // Enable Rx data available interrupt
    endtask
endclass

class uart_fw_rdwr_ctrl_sequence extends uart_fw_base_sequence;
    bit [7:0] tx_data[];
    bit [7:0] rx_data[];
    `uvm_object_utils(uart_fw_rdwr_ctrl_sequence)
    function new(string name = "uart_fw_rdwr_ctrl_sequence");
        super.new(name);
    endfunction : new

    virtual task body();
        uart_reg.lsr.read(status, rdata, .parent(this));
        //Fill TX FIFO
        for(int i=0; i<tx_data.size(); i++) begin
            uart_reg.rbr_thr_dll.write(status, tx_data[i], .parent(this));
        end

        uart_reg.lcr.read(status, rdata, .parent(this));

        `uvm_delay(500ns)
        //Read RX FIFO by polling status bit
        for(int i=0; i<rx_data.size(); i++) begin
            do begin
                uart_reg.lsr.read(status, rdata, .parent(this));
                idle(16);
            end while(rdata[0]==0);
            uart_reg.rbr_thr_dll.read(status, rdata, .parent(this));
            `uvm_info(get_name(), $sformatf("[UART] received data = %2h", rdata), UVM_MEDIUM)

            if(rdata!==rx_data[i]) begin
                `uvm_error(get_name(), $sformatf("UART Read Mismatch: exp=%0x rcv=%0x", rx_data[i], rdata))
            end
        end

        uart_reg.lsr.read(status, rdata, .parent(this));
    endtask
endclass

class uart_rdwr_test extends uart_base_test;
    uart_rdwr_sequence uart_rdwr_seq;
    uart_fw_rdwr_init_sequence uart_fw_init_seq;
    uart_fw_rdwr_ctrl_sequence uart_fw_ctrl_seq;
    bit [7:0] tx_data[];
    bit [7:0] rx_data[];

    `uvm_component_utils(uart_rdwr_test)

    function new (string name = "uart_rdwr_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task main_phase(uvm_phase phase);
        phase.raise_objection(this);
        uart_rdwr_seq = uart_rdwr_sequence::type_id::create("uart_rdwr_seq");
        uart_fw_init_seq = uart_fw_rdwr_init_sequence::type_id::create("uart_fw_init_seq");
        uart_fw_ctrl_seq = uart_fw_rdwr_ctrl_sequence::type_id::create("uart_fw_ctrl_seq");

        tx_data = new[17];
        rx_data = new[17];
        std::randomize(tx_data);
        std::randomize(rx_data);
        uart_rdwr_seq.tx_data = tx_data;
        uart_rdwr_seq.rx_data = rx_data;
        uart_fw_ctrl_seq.tx_data = rx_data;
        uart_fw_ctrl_seq.rx_data = tx_data;

        `uvm_info(get_name(), $sformatf("Print config:\n%s", uarttb.uart_host_cfg.convert2string()), UVM_MEDIUM)
        uart_fw_init_seq.start(uarttb.ahb_mst[0].sequencer);
        fork
        uart_rdwr_seq.start(uarttb.uart_host.sequencer);
        uart_fw_ctrl_seq.start(uarttb.ahb_mst[0].sequencer);
        join

        phase.drop_objection(this);
    endtask : main_phase
endclass : uart_rdwr_test
`endif
module dut_wrapper();
    timeunit 1ns; timeprecision 10ps;
    parameter clk_period = 20ns;
    parameter sclk_period = 40ns;

    reg clk;
    reg rstn;

    reg siu_clkg;

    wire        uart_intr;
    wire [13:0] uart_debug_mon;

    // -------------------------------
    // Clocks and Resets
    // -------------------------------
    initial begin
        // init
        clk  = 0;
        rstn = 0;
        siu_clkg = 0;
        #100ns;
        rstn = 1;
    end

    always #(clk_period/2) clk <= ~clk;
    always #(sclk_period/2) siu_clkg <= ~siu_clkg;

    uart_interface uart_if(.clk(siu_clkg), .rst_(rstn));
    cpu_intr_interface cpu_intr_if(.clk(clk), .sclk(siu_clkg));

    assign cpu_intr_if.interrupt = uart_intr;

    // ----------------------------------------------------------------
    // UART DUT
    // ----------------------------------------------------------------

    uart_top uart_top (
        .HCLK                   (),
        .HRESETn                (),
        .HTRANS                 (),
        .HADDR                  (),
        .HWRITE                 (),
        .HSIZE                  (),
        .HBURST                 (),
        .HWDATA                 (),
        .HSEL                   (),
        .AHB_HREADY             (),
        .HREADY                 (),
        .HRESP                  (),
        .HRDATA                 (),
        .apbclk                 (),
        .clk                    (),
        .rst_                   (),
        .sclk                   (siu_clkg),
        .siu_rst_               (rstn),
        .siu_cfg_rst_           (rstn),
        .inst_sin               (uart_if.sout_data),
        .inst_cts_n             (uart_if.rts_n),
        .inst_dsr_n             (uart_if.dtr_n),
        .inst_dcd_n             (1'b1),
        .inst_ri_n              (1'b1),
        .intr_inst              (uart_intr),
        .sout_inst              (uart_if.sin_data),
        .dtr_n_inst             (uart_if.dsr_n),
        .rts_n_inst             (uart_if.cts_n)
    );

endmodule

`ifndef TP__SV
`define TP__SV

`timescale 1ns/10ps

module tb;
    import uvm_pkg::*;
    import uart_host_pkg::*;

    dut_wrapper top();

    // inlined tests

    initial begin
        uvm_config_db#(virtual uart_interface)::set(null, "*", "uart_interface", top.uart_if);
        uvm_config_db#(virtual cpu_intr_interface)::set(null, "*", "cpu_intr_interface", top.cpu_intr_if);
        $dumpfile("dump.vcd"); $dumpvars;
        run_test();
    end
endmodule : tb

`endif 

