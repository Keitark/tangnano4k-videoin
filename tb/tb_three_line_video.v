`timescale 1ns/1ps
// 13.5:25.2 clock ratio, 857/858-sample source lines, 262-line source fields.
module tb_three_line_video;
    reg wc=0,pc=0,reset=1,start=0,en=0,done=0;
    reg [7:0] field=0,line=0;
    reg [9:0] wa=0;
    reg [15:0] wd=0;
    wire [15:0] data,drops,bad,underflows;
    wire [7:0] frames;
    wire [2:0] ready;
    wire [47:0] tags;
    wire take,release_bank;
    wire [1:0] tb,rb,read_bank;
    wire [9:0] ra;
    integer f,l,p,checks=0;
    reg check_now;
    reg [15:0] expected;
    always #7 wc=~wc;
    always #3.75 pc=~pc;
    ntsc_three_line_queue q(.wr_clk(wc),.wr_reset(reset),.wr_start(start),
        .wr_en(en),.wr_end(done),.wr_field(field),.wr_line(line),.wr_addr(wa),.wr_data(wd),
        .dropped_lines(drops),.bad_lines(bad),.rd_clk(pc),.rd_reset(reset),
        .rd_take(take),.rd_release(release_bank),.rd_take_bank(tb),.rd_release_bank(rb),
        .rd_bank(read_bank),.rd_addr(ra),.rd_data(data),.rd_ready(ready),.rd_tags(tags));
    hdmi_three_line_tx out(.clk_pixel(pc),.clk_5x_pixel(pc),.resetn(!reset),.serial_resetn(!reset),
        .ready(ready),.tags(tags),.line_data(data),.take(take),.release_bank(release_bank),
        .take_bank(tb),.release_index(rb),.read_bank(read_bank),.read_addr(ra),
        .lock_async(1'b1),.color_async(1'b0),.source_status(80'b0),
        .underflows(underflows),.started_frames(frames));
    always @(posedge pc) begin
        check_now=!reset && out.frame_valid && out.bank_valid && out.v_count>=16 && out.v_count<480 &&
            out.h_count>4 && out.h_count<638;
        expected={out.active_field[3:0],out.v_count[8:1],ra[3:0]};
        #1;
        if(check_now) begin
            checks=checks+1;
            if(data!==expected) $fatal(1,"wrong line/pixel got=%h expected=%h y=%d",data,expected,out.v_count);
        end
    end
    initial begin
        repeat(10) @(negedge wc); reset=0;
        for(f=0;f<4;f=f+1) begin
            field=f;
            for(l=0;l<262;l=l+1) begin
                line=l-16;
                for(p=0;p<857+(l%2);p=p+1) begin
                    @(negedge wc);
                    start=(l>=16 && l<256 && p==0);
                    en=(l>=16 && l<256 && p>=80 && p<720 && !p[0]);
                    done=(l>=16 && l<256 && p==789);
                    wa=(p-80)/2;
                    wd={field[3:0],line,wa[3:0]};
                end
            end
            $display("field %d: displayed=%d underflows=%d drops=%d bad=%d",f,frames,underflows,drops,bad);
        end
        start=0; en=0; done=0;
        if(frames<3 || underflows!=0 || bad!=0 || checks<500000)
            $fatal(1,"line-video cadence/coverage failed");
        $display("PASS %d checked pixels, correct line identity and 2x output, bounded source/output drift",checks);
        $finish;
    end
endmodule
