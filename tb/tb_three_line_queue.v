`timescale 1ns/1ps
module tb_three_line_queue;
    reg wc=0,rc=0,reset=1,start=0,en=0,done=0,take=0,release_bank=0;
    reg [7:0] field=1,line=0;
    reg [9:0] wa=0,ra=0;
    reg [15:0] wd=0;
    reg [1:0] tb=0,rb=0,read_bank=0;
    wire [15:0] data,drops,bad;
    wire [2:0] ready;
    wire [47:0] tags;
    integer j;
    always #7 wc=~wc;
    always #11 rc=~rc;
    ntsc_three_line_queue #(.WIDTH(8)) dut(.wr_clk(wc),.wr_reset(reset),
        .wr_start(start),.wr_en(en),.wr_end(done),.wr_field(field),.wr_line(line),
        .wr_addr(wa),.wr_data(wd),.dropped_lines(drops),.bad_lines(bad),
        .rd_clk(rc),.rd_reset(reset),.rd_take(take),.rd_release(release_bank),
        .rd_take_bank(tb),.rd_release_bank(rb),.rd_bank(read_bank),.rd_addr(ra),
        .rd_data(data),.rd_ready(ready),.rd_tags(tags));
    task send_line(input integer id, input integer length);
        begin
            @(negedge wc); start=1; line=id;
            @(negedge wc); start=0;
            for(integer k=0;k<length;k=k+1) begin
                en=1; wa=k; wd=id*16+k; done=(k==length-1);
                @(negedge wc);
            end
            en=0; done=0; repeat(4) @(negedge wc);
        end
    endtask
    task claim(input integer bank);
        begin
            @(negedge rc); tb=bank; read_bank=bank; take=1;
            @(negedge rc); take=0;
        end
    endtask
    task check_line(input integer id);
        begin
            for(integer k=0;k<8;k=k+1) begin
                @(negedge rc); ra=k;
                @(negedge rc);
                if(data !== id*16+k) $fatal(1,"line overwritten or final word missing");
            end
        end
    endtask
    initial begin
        repeat(8) @(negedge rc); reset=0;
        send_line(0,8); send_line(1,8); send_line(2,8);
        repeat(5) @(negedge rc);
        if(ready!=7 || tags!={16'h0102,16'h0101,16'h0100}) $fatal(1,"bad descriptors");
        claim(0); check_line(0);
        send_line(3,8); // All banks owned: discard rather than overwrite.
        if(drops!=1) $fatal(1,"overflow not counted");
        check_line(0); check_line(0); // two display passes preserve ownership
        @(negedge rc); release_bank=1; rb=0;
        @(negedge rc); release_bank=0;
        repeat(5) @(negedge wc);
        send_line(4,7);
        if(bad!=1 || ready[0]) $fatal(1,"short line published");
        send_line(5,8); repeat(5) @(negedge rc);
        if(!ready[0] || tags[15:0]!=16'h0105) $fatal(1,"released bank not reusable");
        claim(0); check_line(5);
        read_bank=1; check_line(1);
        read_bank=2; check_line(2);
        $display("PASS three-bank ownership, overflow drop, partial rejection, metadata, reuse and dual-clock pixels");
        $finish;
    end
endmodule
