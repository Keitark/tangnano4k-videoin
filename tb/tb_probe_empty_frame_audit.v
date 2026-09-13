`timescale 1ns/1ps
// Regression: source field events cannot publish a zero-write picture.
module tb_probe_empty_frame_audit;
    reg clk=0, reset=1, frame=0, ack=0;
    wire wr,bank,token;
    wire [15:0] addr;
    wire [7:0] data;
    wire [1:0] mode;
    integer writes=0, empty_publications=0, tick;
    always #5 clk=~clk;
    runtime_video_probe #(.DATA_BITS(8),.BANK_PIXELS(9600),.PAGE_TICKS(1000000)) dut(
        .clk(clk),.reset(reset),.raw_level(8'd64),.picture_wr_en(1'b0),
        .picture_addr(15'd0),.picture_data(8'd0),.picture_frame_toggle(frame),
        .adopted_toggle_async(ack),.wr_en(wr),.wr_addr(addr),.wr_data(data),
        .published_bank(bank),.published_toggle(token),.published_mode(mode));
    always @(posedge clk) if(wr) writes=writes+1;
    initial begin
        repeat(4) @(negedge clk); reset=0;
        for(tick=0;tick<1000;tick=tick+1) begin
            @(negedge clk);
            if(tick%100==0) frame=~frame;
            if(token!=ack) begin
                if(mode==0 && writes==0) empty_publications=empty_publications+1;
                ack=token;
            end
        end
        if(empty_publications!=0) $fatal(1,"empty picture published");
        if(dut.rejected_pictures==0 || dut.last_picture_words!=0)
            $fatal(1,"empty picture rejection not observable");
        $display("PASS zero-write pictures rejected: %d",dut.rejected_pictures);
        $finish;
    end
endmodule
