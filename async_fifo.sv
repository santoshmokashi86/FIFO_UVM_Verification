`timescale 1ns/1ps
// =============================================================================
// File    : async_fifo.sv
// Design  : Asynchronous width-converting FIFO
// Spec    : 12-bit write data, 4-bit read data, 16 x 12-bit words
// Method  : Gray-coded word pointers, 2-FF CDC synchronizers
// Read order: MSB-first (ABC -> A, then B, then C)
// =============================================================================
module async_fifo #(
    parameter integer INPUT_WIDTH  = 12,
    parameter integer OUTPUT_WIDTH = 4,
    parameter integer DEPTH        = 16,
    parameter integer ADDR_WIDTH   = $clog2(DEPTH),
    parameter integer PTR_WIDTH    = ADDR_WIDTH + 1,
    parameter integer CHUNKS       = INPUT_WIDTH / OUTPUT_WIDTH,
    parameter integer CHUNK_WIDTH  = (CHUNKS <= 1) ? 1 : $clog2(CHUNKS)
)(
    input  logic                  wr_clk,
    input  logic                  wr_rst_n,
    input  logic                  wr_en,
    input  logic [INPUT_WIDTH-1:0] wr_data,
    output logic                  wr_full,

    input  logic                  rd_clk,
    input  logic                  rd_rst_n,
    input  logic                  rd_en,
    output logic [OUTPUT_WIDTH-1:0] rd_data,
    output logic                  rd_empty
);

    // Each memory entry stores one complete INPUT_WIDTH-bit word.
    logic [INPUT_WIDTH-1:0] mem [0:DEPTH-1];

    // Binary and Gray pointers count complete words, not output chunks.
    logic [PTR_WIDTH-1:0] wr_bin, wr_gray;
    logic [PTR_WIDTH-1:0] rd_bin, rd_gray;

    // CDC synchronizers.
    (* ASYNC_REG = "TRUE" *) logic [PTR_WIDTH-1:0] rd_gray_sync1, rd_gray_sync2;
    (* ASYNC_REG = "TRUE" *) logic [PTR_WIDTH-1:0] wr_gray_sync1, wr_gray_sync2;

    // Read-side word buffer and chunk index.
    logic [INPUT_WIDTH-1:0] rd_word_buf;
    logic                  rd_word_valid;
    logic [CHUNK_WIDTH-1:0] rd_chunk;

    function automatic logic [PTR_WIDTH-1:0] bin2gray(
        input logic [PTR_WIDTH-1:0] bin
    );
        bin2gray = (bin >> 1) ^ bin;
    endfunction

    // Full when current write pointer is one complete FIFO depth ahead
    // of the synchronized read pointer (invert the two MSBs).
    always_comb begin
        wr_full = (wr_gray ==
                   {~rd_gray_sync2[PTR_WIDTH-1:PTR_WIDTH-2],
                     rd_gray_sync2[PTR_WIDTH-3:0]});
    end

    // Empty only when there is no partially consumed word and no
    // unread complete word visible from the synchronized write pointer.
    always_comb begin
        rd_empty = (!rd_word_valid && (rd_gray == wr_gray_sync2));
    end

    // Write pointer.
    always_ff @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_bin  <= '0;
            wr_gray <= '0;
        end else if (wr_en && !wr_full) begin
            wr_bin  <= wr_bin + 1'b1;
            wr_gray <= bin2gray(wr_bin + 1'b1);
        end
    end

    // Dual-clock memory write port.
    always_ff @(posedge wr_clk) begin
        if (wr_rst_n && wr_en && !wr_full)
            mem[wr_bin[ADDR_WIDTH-1:0]] <= wr_data;
    end

    // Synchronize read Gray pointer into write clock domain.
    always_ff @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            rd_gray_sync1 <= '0;
            rd_gray_sync2 <= '0;
        end else begin
            rd_gray_sync1 <= rd_gray;
            rd_gray_sync2 <= rd_gray_sync1;
        end
    end

    // Read pointer and width conversion.
    // The word pointer advances only after all CHUNKS have been read.
    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_bin        <= '0;
            rd_gray       <= '0;
            rd_data       <= '0;
            rd_word_buf   <= '0;
            rd_word_valid <= 1'b0;
            rd_chunk      <= '0;
        end else if (rd_en && !rd_empty) begin
            if (!rd_word_valid) begin
                // First chunk comes directly from memory.
                rd_word_buf <= mem[rd_bin[ADDR_WIDTH-1:0]];
                rd_data     <= mem[rd_bin[ADDR_WIDTH-1:0]]
                               [INPUT_WIDTH-1 -: OUTPUT_WIDTH];

                if (CHUNKS == 1) begin
                    rd_bin  <= rd_bin + 1'b1;
                    rd_gray <= bin2gray(rd_bin + 1'b1);
                end else begin
                    rd_word_valid <= 1'b1;
                    rd_chunk      <= 1;
                end
            end else begin
                // Remaining chunks come from the local word buffer.
                rd_data <= rd_word_buf[
                    INPUT_WIDTH-1-(rd_chunk*OUTPUT_WIDTH) -: OUTPUT_WIDTH
                ];

                if (rd_chunk == CHUNKS-1) begin
                    rd_word_valid <= 1'b0;
                    rd_chunk      <= '0;
                    rd_bin        <= rd_bin + 1'b1;
                    rd_gray       <= bin2gray(rd_bin + 1'b1);
                end else begin
                    rd_chunk <= rd_chunk + 1'b1;
                end
            end
        end
    end

    // Synchronize write Gray pointer into read clock domain.
    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            wr_gray_sync1 <= '0;
            wr_gray_sync2 <= '0;
        end else begin
            wr_gray_sync1 <= wr_gray;
            wr_gray_sync2 <= wr_gray_sync1;
        end
    end

    // Parameter checks for this Gray-pointer FIFO implementation.
    initial begin
        if (DEPTH < 4 || ((DEPTH & (DEPTH-1)) != 0))
            $fatal(1, "DEPTH must be a power of 2 and at least 4");
        if ((INPUT_WIDTH % OUTPUT_WIDTH) != 0)
            $fatal(1, "INPUT_WIDTH must be an integer multiple of OUTPUT_WIDTH");
        if (CHUNKS < 1)
            $fatal(1, "CHUNKS must be at least 1");
    end

endmodule
