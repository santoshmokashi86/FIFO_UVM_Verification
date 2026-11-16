`timescale 1ns/1ps
interface fifo_if;
    logic wr_clk;
    logic rd_clk;
    logic wr_rst_n;
    logic rd_rst_n;
    logic wr_en;
    logic rd_en;
    logic [11:0] wr_data;
    logic [3:0]  rd_data;
    logic wr_full;
    logic rd_empty;
endinterface
