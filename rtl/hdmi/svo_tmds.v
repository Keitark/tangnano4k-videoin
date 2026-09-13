/*
 * TMDS encoder derived from the SVO Simple Video Out FPGA Core.
 *
 * Copyright (C) 2014 Clifford Wolf <clifford@clifford.at>
 *
 * Permission to use, copy, modify, and/or distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES.
 */
module svo_tmds (
    input  wire       clk,
    input  wire       resetn,
    input  wire       de,
    input  wire [1:0] ctrl,
    input  wire [7:0] din,
    output reg  [9:0] dout
);
    function [3:0] count_ones;
        input [7:0] bits;
        integer i;
        begin
            count_ones = 0;
            for (i = 0; i < 8; i = i + 1)
                count_ones = count_ones + bits[i];
        end
    endfunction

    reg signed [7:0] disparity;
    reg signed [7:0] disparity_next;
    reg [8:0] q_m;
    reg [9:0] symbol_next;
    reg [3:0] ones_data;
    reg [3:0] ones_qm;
    reg [3:0] zeros_qm;
    integer j;

    always @* begin
        ones_data = count_ones(din);
        q_m[0] = din[0];
        if ((ones_data > 4) || ((ones_data == 4) && !din[0])) begin
            for (j = 1; j < 8; j = j + 1)
                q_m[j] = q_m[j-1] ~^ din[j];
            q_m[8] = 1'b0;
        end else begin
            for (j = 1; j < 8; j = j + 1)
                q_m[j] = q_m[j-1] ^ din[j];
            q_m[8] = 1'b1;
        end

        ones_qm = count_ones(q_m[7:0]);
        zeros_qm = 4'd8 - ones_qm;
        symbol_next = 10'b0;
        disparity_next = disparity;

        if ((disparity == 0) || (ones_qm == zeros_qm)) begin
            symbol_next[9] = ~q_m[8];
            symbol_next[8] = q_m[8];
            symbol_next[7:0] = q_m[8] ? q_m[7:0] : ~q_m[7:0];
            if (q_m[8])
                disparity_next = disparity + ones_qm - zeros_qm;
            else
                disparity_next = disparity + zeros_qm - ones_qm;
        end else if (((disparity > 0) && (ones_qm > zeros_qm)) ||
                     ((disparity < 0) && (zeros_qm > ones_qm))) begin
            symbol_next[9] = 1'b1;
            symbol_next[8] = q_m[8];
            symbol_next[7:0] = ~q_m[7:0];
            disparity_next = disparity + zeros_qm - ones_qm +
                             (q_m[8] ? 8'sd2 : 8'sd0);
        end else begin
            symbol_next[9] = 1'b0;
            symbol_next[8] = q_m[8];
            symbol_next[7:0] = q_m[7:0];
            disparity_next = disparity + ones_qm - zeros_qm -
                             (q_m[8] ? 8'sd0 : 8'sd2);
        end
    end

    always @(posedge clk) begin
        if (!resetn) begin
            disparity <= 0;
            dout <= 10'b1101010100;
        end else if (!de) begin
            disparity <= 0;
            case (ctrl)
                2'b00: dout <= 10'b1101010100;
                2'b01: dout <= 10'b0010101011;
                2'b10: dout <= 10'b0101010100;
                default: dout <= 10'b1010101011;
            endcase
        end else begin
            disparity <= disparity_next;
            dout <= symbol_next;
        end
    end
endmodule
