`timescale 1ns/1ps
module tb_picture_validation;
    reg clk=0, reset=1, frame=0, ack=0, pixel=0;
    reg [14:0] addr=0;
    reg [7:0] data=0;
    wire wr, bank, token;
    wire [15:0] wa, words, rejects;
    wire [7:0] wd, accepted, flags;
    wire [1:0] mode;
    reg [7:0] mem[0:15];
    reg reader_bank=0;
    integer k, publications=0;
    reg seen=0;
    always #5 clk=~clk;
    runtime_video_probe #(.DATA_BITS(8),.BANK_PIXELS(8),.PAGE_TICKS(100000)) dut(
        .clk(clk),.reset(reset),.raw_level(8'h25),.picture_wr_en(pixel),
        .picture_addr(addr),.picture_data(data),.picture_frame_toggle(frame),
        .adopted_toggle_async(ack),.wr_en(wr),.wr_addr(wa),.wr_data(wd),
        .published_bank(bank),.published_toggle(token),.published_mode(mode),
        .last_picture_words(words),.rejected_pictures(rejects),
        .accepted_pictures(accepted),.last_picture_flags(flags));
    always @(posedge clk) if(!reset && wr) begin
        if(wa>=16 || (wa>=8)==reader_bank) $fatal(1,"reader bank overwritten");
        mem[wa]=wd;
    end
    always @(negedge clk) if(!reset && seen!=token) begin
        seen=token; publications=publications+1;
        for(integer j=0;j<8;j=j+1)
            if(mem[(bank ? 8:0)+j] !== (8'ha0+j)) $fatal(1,"publication before final RAM write");
    end
    task word(input integer a);
        begin @(negedge clk); pixel=1; addr=a; data=8'ha0+a; end
    endtask
    task boundary;
        begin @(negedge clk); pixel=0; frame=~frame; @(negedge clk); end
    endtask
    task assert_rejected(input integer n);
        begin
            repeat(4) @(negedge clk);
            if(rejects!=n || publications!=0) $fatal(1,"invalid picture accepted/rejection absent");
        end
    endtask
    initial begin
        repeat(4) @(negedge clk); reset=0; boundary();
        boundary(); assert_rejected(1); // empty
        for(k=0;k<7;k=k+1) word(k);
        boundary(); assert_rejected(2); // missing final word
        word(0); word(0);
        for(k=1;k<8;k=k+1) word(k);
        boundary(); assert_rejected(3); // duplicate plus all expected addresses
        word(1); word(0);
        for(k=2;k<8;k=k+1) word(k);
        boundary(); assert_rejected(4); // count alone would accept this
        for(k=0;k<8;k=k+1) word(k);
        word(8); boundary(); assert_rejected(5); // extra out-of-range word
        for(k=0;k<7;k=k+1) word(k);
        word(7); frame=~frame; // last word belongs to closing field
        @(negedge clk); pixel=0;
        repeat(8) @(negedge clk);
        if(publications!=1 || accepted!=1 || words!=8 || flags!=1)
            $fatal(1,"complete boundary-coincident picture rejected");
        // No acknowledgement: incoming source fields must not change RAM/token.
        for(k=0;k<8;k=k+1) word(k);
        boundary(); repeat(8) @(negedge clk);
        if(publications!=1) $fatal(1,"publication without reader release");
        reader_bank=bank; ack=token;
        repeat(6) @(negedge clk); boundary();
        for(k=0;k<8;k=k+1) word(k);
        boundary(); repeat(8) @(negedge clk);
        if(publications!=2 || accepted!=2 || rejects!=5)
            $fatal(1,"failed to resume after ACK");
        $display("PASS empty/short/duplicate/reordered/extra fields, final-write drain, delayed ACK, resume");
        $finish;
    end
endmodule
