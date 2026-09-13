`timescale 1ns/1ps
module tb_uvc_payload_source;
    reg clk = 0;
    reg reset = 1;
    reg start_packet = 0;
    reg end_of_frame = 0;
    reg consume = 0;
    wire [7:0] data;
    wire valid;
    wire [11:0] packet_length;
    wire packet_done;
    integer count;

    always #5 clk = ~clk;

    uvc_payload_source #(.PACKET_BYTES(32)) dut (
        .clk(clk), .reset(reset), .start_packet(start_packet),
        .end_of_frame(end_of_frame), .consume(consume),
        .data(data), .valid(valid), .packet_length(packet_length),
        .packet_done(packet_done)
    );

    initial begin
        repeat (3) @(posedge clk);
        reset <= 0;
        @(posedge clk); start_packet <= 1;
        @(posedge clk); start_packet <= 0; consume <= 1;
        count = 0;
        while (!packet_done) begin
            @(posedge clk);
            if (valid) begin
                if (count == 0 && data !== 8'd12) $fatal(1, "bad UVC header length");
                if (count == 1 && data[0] !== 1'b0) $fatal(1, "bad first FID");
                count = count + 1;
            end
        end
        consume <= 0;
        if (count != 32) $fatal(1, "bad packet byte count: %0d", count);
        if (packet_length != 32) $fatal(1, "bad packet length");
        $display("PASS uvc_payload_source bytes=%0d", count);
        $finish;
    end
endmodule

