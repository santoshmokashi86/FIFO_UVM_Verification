`timescale 1ns/1ps
module tb_top;
    import uvm_pkg::*;
    import fifo_uvm_pkg::*;

    fifo_if vif();

    // Unrelated clocks: write period = 10 ns, read period = 14 ns.
    initial begin
        vif.wr_clk = 1'b0;
        forever #5 vif.wr_clk = ~vif.wr_clk;
    end

    initial begin
        vif.rd_clk = 1'b0;
        forever #7 vif.rd_clk = ~vif.rd_clk;
    end

    async_fifo #(
        .INPUT_WIDTH(12),
        .OUTPUT_WIDTH(4),
        .DEPTH(16)
    ) dut (
        .wr_clk(vif.wr_clk),
        .wr_rst_n(vif.wr_rst_n),
        .wr_en(vif.wr_en),
        .wr_data(vif.wr_data),
        .wr_full(vif.wr_full),
        .rd_clk(vif.rd_clk),
        .rd_rst_n(vif.rd_rst_n),
        .rd_en(vif.rd_en),
        .rd_data(vif.rd_data),
        .rd_empty(vif.rd_empty)
    );

    initial begin
        vif.wr_rst_n = 1'b0;
        vif.rd_rst_n = 1'b0;
        vif.wr_en    = 1'b0;
        vif.rd_en    = 1'b0;
        vif.wr_data  = '0;

        uvm_config_db#(virtual fifo_if)::set(null, "*", "vif", vif);

        repeat (5) @(negedge vif.wr_clk);
        vif.wr_rst_n = 1'b1;
        repeat (2) @(negedge vif.rd_clk);
        vif.rd_rst_n = 1'b1;

        `uvm_info("TB_TOP", "Reset released; starting UVM test", UVM_LOW)
        run_test("fifo_test");
    end

    initial begin
        #2ms;
        $display("TB_RESULT: FAIL - watchdog timeout");
        $finish;
    end
endmodule
