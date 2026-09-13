`timescale 1ns/1ps
module tb_runtime_video_probe;
    parameter integer CYCLE_ONCE = 0;
    parameter integer BANK_PIXELS = 15360;
    parameter integer NIBBLE_RAW = 0;
    parameter integer DATA_BITS = 4;
    reg clk=0, reset=1, picture_wr=0, frame_toggle=0, ack=0;
    reg [7:0] raw=8'ha5;
    reg [14:0] addr=0;
    wire wr, bank, token;
    wire [15:0] wa;
    wire [DATA_BITS-1:0] wd;
    wire [1:0] mode;
    reg active_bank=0;
    reg [DATA_BITS-1:0] mem[0:2*BANK_PIXELS-1];
    reg [7:0] expected_raw[0:BANK_PIXELS/2-1];
    reg [3:0] expected_nibble[0:BANK_PIXELS-1];
    integer tick, position, k, offset, pages[0:2];
    reg [7:0] value;
    always #5 clk=~clk;
    runtime_video_probe #(.PAGE_TICKS(100000), .CYCLE_ONCE(CYCLE_ONCE), .BANK_PIXELS(BANK_PIXELS), .NIBBLE_RAW(NIBBLE_RAW), .DATA_BITS(DATA_BITS)) dut(
        .clk(clk),.reset(reset),.raw_level(raw),.picture_wr_en(picture_wr),
        .picture_addr(addr),.picture_data(addr[DATA_BITS-1:0]),.picture_frame_toggle(frame_toggle),
        .adopted_toggle_async(ack),.wr_en(wr),.wr_addr(wa),.wr_data(wd),
        .published_bank(bank),.published_toggle(token),.published_mode(mode));
    always @(posedge clk) if(wr && !reset) begin
        if(wa >= 2*BANK_PIXELS) $fatal(1,"out of range");
        if((wa >= BANK_PIXELS) == active_bank) $fatal(1,"writing displayed bank");
        mem[wa]=wd;
    end
    always @(posedge clk)
        if(!reset && dut.state==2 && dut.capture_mode==1 && !dut.raw_addr[0])
            expected_raw[dut.raw_addr/2]=raw;
    always @(posedge clk)
        if(!reset && dut.state==2 && dut.capture_mode==1)
            expected_nibble[dut.raw_addr]=raw[7:4];
    initial begin
        for(k=0;k<3;k=k+1) pages[k]=0;
        repeat(4) @(negedge clk); reset=0;
        for(tick=0;tick<650000;tick=tick+1) begin
            @(negedge clk);
            position=tick%(BANK_PIXELS+1640);
            raw=raw+8'd37;
            if(position==0) frame_toggle=~frame_toggle;
            picture_wr=(position>=100 && position<BANK_PIXELS+100);
            addr=position-100;
            // Simulate slower display-domain adoption at a frame boundary.
            if(tick%503==0 && ack!=token) begin
                if(CYCLE_ONCE && tick > 320000 && mode != 0)
                    $fatal(1,"diagnostics returned after startup cycle");
                offset=bank ? BANK_PIXELS : 0;
                for(k=0;k<BANK_PIXELS;k=k+1) begin
                    if(mode==0) begin
                        if(mem[offset+k] !== (k%(1<<DATA_BITS))) $fatal(1,"partial picture publication %d",k);
                    end else if(NIBBLE_RAW) begin
                        if(mem[offset+k] !== (mode==1 ? expected_nibble[k] : k[3:0]))
                            $fatal(1,"full-rate raw nibble/calibration packing %d",k);
                    end else begin
                        value=mode==1 ? expected_raw[k/2] : (k/2)%256;
                        if(mem[offset+k] !== (k%2 ? value[3:0] : value[7:4]))
                            $fatal(1,"raw byte/calibration packing %d",k);
                    end
                end
                active_bank=bank;
                ack=token;
                pages[mode]=pages[mode]+1;
            end
        end
        if(pages[0]<2 || pages[1]<(CYCLE_ONCE ? 1 : 2) || pages[2]<(CYCLE_ONCE ? 1 : 2))
            $fatal(1,"missing modes");
        if(CYCLE_ONCE && (pages[1]!=1 || pages[2]!=1 || !dut.cycle_complete))
            $fatal(1,"startup diagnostics not exactly once");
        $display("PASS runtime pages=%d/%d/%d, full bank publication, exact packed bytes, no writes to active bank",pages[0],pages[1],pages[2]);
        $finish;
    end
endmodule
