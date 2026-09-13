// Frame-bufferless 2x line doubler. Pixel/serializer clocks never follow input
// edges. Only vertical blank duration may vary, within 493..527 output lines,
// to start on a freshly completed source line zero. Otherwise output a black
// frame with independent status and retry at the next blanking interval.
module hdmi_three_line_tx #(parameter integer WIDTH=320) (
    input wire clk_pixel, clk_5x_pixel, resetn, serial_resetn,
    input wire [2:0] ready,
    input wire [47:0] tags,
    input wire [15:0] line_data,
    output reg take, release_bank,
    output reg [1:0] take_bank, release_index,
    output reg [1:0] read_bank,
    output wire [9:0] read_addr,
    input wire lock_async, color_async,
    input wire [79:0] source_status,
    output wire status_request,
    output reg [15:0] underflows,
    output reg [7:0] started_frames,
    output wire tmds_clk_n, tmds_clk_p,
    output wire [2:0] tmds_d_n, tmds_d_p
);
    reg [9:0] h_count,v_count,h_d,v_d;
    reg frame_valid, bank_valid;
    reg [7:0] active_field;
    reg [10:0] age0,age1,age2;
    reg lock_meta,lock_sync,color_meta,color_sync;
    reg [1:0] de_pipe,hs_pipe,vs_pipe;
    reg [7:0] red_pipe,green_pipe,blue_pipe;
    reg [7:0] r,g,b;
    reg found;
    reg [1:0] selected_bank;
    reg flush_found;
    reg [1:0] flush_bank;
    integer idx;
    reg [15:0] tag;
    wire [7:0] next_line={1'b0,v_count[8:1]}+1'b1;
    wire [63:0] status_bits={source_status[79:48],underflows,started_frames,
        4'b0,source_status[47],frame_valid,color_sync,lock_sync};
    assign read_addr=h_count<640 ? h_count/(640/WIDTH) : 0;
    assign status_request=(h_count==0 && v_count==0);
    always @* begin
        found=0; selected_bank=0; flush_found=0; flush_bank=0; tag=0;
        for(idx=2;idx>=0;idx=idx-1) begin
            tag=tags[idx*16 +: 16];
            if(ready[idx]) begin
                if(v_count>=493 && tag[7:0]==0 &&
                   // Leave >20 us of producer lead for accumulated active-line
                   // rate mismatch; a just-ready line has insufficient margin.
                   (idx==0 ? (age0>=512 && age0<1600) :
                    idx==1 ? (age1>=512 && age1<1600) : (age2>=512 && age2<1600))) begin
                    found=1; selected_bank=idx;
                end else if(v_count<480 && frame_valid && tag[15:8]==active_field && tag[7:0]==next_line) begin
                    found=1; selected_bank=idx;
                end
                // Release stale/unusable ready lines, but never the bank whose
                // take pulse is still travelling to the queue on this clock.
                if(!(bank_valid && read_bank==idx) &&
                   ((v_count<480 && (!frame_valid || tag[15:8]!=active_field || tag[7:0]<next_line)) ||
                    (v_count>=480 && (v_count<493 || tag[7:0]!=0 ||
                     (idx==0 ? age0>=1600 : idx==1 ? age1>=1600 : age2>=1600))))) begin
                    flush_found=1; flush_bank=idx;
                end
            end
        end
    end
    always @(posedge clk_pixel) begin
        if(!resetn) begin
            h_count<=0; v_count<=480; frame_valid<=0; bank_valid<=0;
            active_field<=0; read_bank<=0; take<=0; release_bank<=0;
            take_bank<=0; release_index<=0; age0<=0; age1<=0; age2<=0;
            underflows<=0; started_frames<=0;
            lock_meta<=0; lock_sync<=0; color_meta<=0; color_sync<=0;
        end else begin
            lock_meta<=lock_async; lock_sync<=lock_meta;
            color_meta<=color_async; color_sync<=color_meta;
            age0<=!ready[0] ? 0 : (&age0) ? age0 : age0+1'b1;
            age1<=!ready[1] ? 0 : (&age1) ? age1 : age1+1'b1;
            age2<=!ready[2] ? 0 : (&age2) ? age2 : age2+1'b1;
            take<=0; release_bank<=0;
            if(flush_found) begin release_bank<=1; release_index<=flush_bank; end
            if(h_count==799) begin
                h_count<=0;
                if(v_count>=493 && found) begin
                    v_count<=0; frame_valid<=1; bank_valid<=1;
                    read_bank<=selected_bank; take_bank<=selected_bank; take<=1;
                    active_field<=tags[selected_bank*16+8 +: 8];
                    started_frames<=started_frames+1'b1;
                end else if(v_count==527) begin
                    v_count<=0; frame_valid<=0; bank_valid<=0;
                end else begin
                    v_count<=v_count+1'b1;
                    if(v_count<480 && v_count[0]) begin
                        if(bank_valid) begin release_bank<=1; release_index<=read_bank; end
                        bank_valid<=0;
                        if(v_count<479 && frame_valid) begin
                            if(found) begin
                                take<=1; take_bank<=selected_bank;
                                read_bank<=selected_bank; bank_valid<=1;
                            end else if(!(&underflows)) underflows<=underflows+1'b1;
                        end
                    end
                end
            end else h_count<=h_count+1'b1;
        end
    end
    always @* begin
        r=bank_valid && frame_valid ? {line_data[15:11],line_data[15:13]} : 0;
        g=bank_valid && frame_valid ? {line_data[10:5],line_data[10:9]} : 0;
        b=bank_valid && frame_valid ? {line_data[4:0],line_data[4:2]} : 0;
        if(v_d<8) begin
            case(h_d/80)
                0: begin r=255; g=255; b=255; end
                1: begin r=255; g=255; b=0; end
                2: begin r=0; g=255; b=255; end
                3: begin r=0; g=255; b=0; end
                4: begin r=255; g=0; b=255; end
                5: begin r=255; g=0; b=0; end
                6: begin r=0; g=0; b=255; end
                default: begin r=lock_sync ? 255 : 96; g=lock_sync ? 208 : 0; b=0; end
            endcase
        end else if(v_d<16) begin
            r=16; g=16; b=16;
            if(h_d>=64 && h_d<576 && status_bits[63-((h_d-64)/8)]) begin
                r=240; g=240; b=240;
            end
        end
    end
    always @(posedge clk_pixel) begin
        if(!resetn) begin
            h_d<=0; v_d<=480; de_pipe<=0; hs_pipe<=3; vs_pipe<=3;
            red_pipe<=0; green_pipe<=0; blue_pipe<=0;
        end else begin
            h_d<=h_count; v_d<=v_count;
            de_pipe<={de_pipe[0],h_count<640 && v_count<480};
            hs_pipe<={hs_pipe[0],!((h_count>=656)&&(h_count<752))};
            vs_pipe<={vs_pipe[0],!((v_count>=490)&&(v_count<492))};
            red_pipe<=r; green_pipe<=g; blue_pipe<=b;
        end
    end
    wire [9:0] red_code,green_code,blue_code;
    svo_tmds er(.clk(clk_pixel),.resetn(resetn),.de(de_pipe[1]),.ctrl(2'b0),.din(red_pipe),.dout(red_code));
    svo_tmds eg(.clk(clk_pixel),.resetn(resetn),.de(de_pipe[1]),.ctrl(2'b0),.din(green_pipe),.dout(green_code));
    svo_tmds eb(.clk(clk_pixel),.resetn(resetn),.de(de_pipe[1]),.ctrl({vs_pipe[1],hs_pipe[1]}),.din(blue_pipe),.dout(blue_code));
    wire [2:0] serial_data;
    OSER10 serializers [2:0] (
        .Q(serial_data),
        .D0({red_code[0],green_code[0],blue_code[0]}), .D1({red_code[1],green_code[1],blue_code[1]}),
        .D2({red_code[2],green_code[2],blue_code[2]}), .D3({red_code[3],green_code[3],blue_code[3]}),
        .D4({red_code[4],green_code[4],blue_code[4]}), .D5({red_code[5],green_code[5],blue_code[5]}),
        .D6({red_code[6],green_code[6],blue_code[6]}), .D7({red_code[7],green_code[7],blue_code[7]}),
        .D8({red_code[8],green_code[8],blue_code[8]}), .D9({red_code[9],green_code[9],blue_code[9]}),
        .PCLK(clk_pixel),.FCLK(clk_5x_pixel),.RESET(~serial_resetn));
    ELVDS_OBUF output_buffers [3:0] (.I({clk_pixel,serial_data}),
        .O({tmds_clk_p,tmds_d_p}),.OB({tmds_clk_n,tmds_d_n}));
endmodule
