// Three independently-owned dual-clock line banks. A bank cannot be reused
// until the pixel-domain consumer returns its publication token. Metadata is
// written at line start and held through publication and reader release.
module ntsc_three_line_queue #(parameter integer WIDTH=320) (
    input wire wr_clk, wr_reset, wr_start, wr_en, wr_end,
    input wire [7:0] wr_field, wr_line,
    input wire [9:0] wr_addr,
    input wire [15:0] wr_data,
    output reg [15:0] dropped_lines, bad_lines,
    input wire rd_clk, rd_reset,
    input wire rd_take, rd_release,
    input wire [1:0] rd_take_bank, rd_release_bank, rd_bank,
    input wire [9:0] rd_addr,
    output reg [15:0] rd_data,
    output wire [2:0] rd_ready,
    output wire [47:0] rd_tags
);
    reg [15:0] tag0,tag1,tag2;
    reg [2:0] published, returned, returned_meta, returned_sync;
    reg [2:0] published_meta, published_sync, claimed;
    reg writing, malformed, publish_pending;
    reg [1:0] write_bank, pending_bank;
    reg [10:0] words;
    wire [2:0] free_banks=~(published ^ returned_sync);
    wire have_free=|free_banks;
    wire [1:0] free_bank=free_banks[0] ? 0 : free_banks[1] ? 1 : 2;
    wire word_ok=wr_en && !malformed && words<WIDTH && {1'b0,wr_addr}==words;
    wire [10:0] words_next=words+(word_ok ? 11'd1 : 11'd0);
    assign rd_ready=(published_sync ^ returned) & ~claimed;
    assign rd_tags={tag2,tag1,tag0};

    always @(posedge wr_clk) begin
        if(wr_reset) begin
            published<=0; returned_meta<=0; returned_sync<=0;
            writing<=0; malformed<=0; publish_pending<=0;
            write_bank<=0; pending_bank<=0; words<=0;
            tag0<=0; tag1<=0; tag2<=0; dropped_lines<=0; bad_lines<=0;
        end else begin
            returned_meta<=returned; returned_sync<=returned_meta;
            if(publish_pending) begin
                published[pending_bank]<=~published[pending_bank];
                publish_pending<=0;
            end
            if(wr_start) begin
                if(writing && !(&bad_lines)) bad_lines<=bad_lines+1'b1;
                words<=0; malformed<=0; writing<=0;
                // A simultaneous publication/start is deliberately dropped;
                // otherwise an as-yet unannounced bank could be reallocated.
                if(have_free && !publish_pending) begin
                    writing<=1; write_bank<=free_bank;
                    case(free_bank)
                        0: tag0<={wr_field,wr_line};
                        1: tag1<={wr_field,wr_line};
                        2: tag2<={wr_field,wr_line};
                    endcase
                end else if(!(&dropped_lines)) dropped_lines<=dropped_lines+1'b1;
            end else if(writing) begin
                if(word_ok) begin
                    words<=words_next;
                end
                if(wr_en && !word_ok) malformed<=1;
                if(wr_end) begin
                    writing<=0;
                    if(!malformed && !(wr_en && !word_ok) && words_next==WIDTH) begin
                        pending_bank<=write_bank; publish_pending<=1;
                    end else if(!(&bad_lines)) bad_lines<=bad_lines+1'b1;
                end
            end
        end
    end

    always @(posedge rd_clk) begin
        if(rd_reset) begin
            published_meta<=0; published_sync<=0; returned<=0; claimed<=0;
        end else begin
            published_meta<=published; published_sync<=published_meta;
            if(rd_release && rd_release_bank<3) begin
                returned[rd_release_bank]<=published_sync[rd_release_bank];
                claimed[rd_release_bank]<=0;
            end
            if(rd_take && rd_take_bank<3 && rd_ready[rd_take_bank])
                claimed[rd_take_bank]<=1;
        end
    end
    // Use power-of-two, independent read ports. Bounds/mux logic stays OUTSIDE
    // the RAM template; conditional zeroing inside it maps to fabric on Gowin.
    localparam integer ADDR_BITS=WIDTH<=512 ? 9 : 10;
    wire [47:0] bank_data;
    reg [1:0] read_bank_d;
    reg read_valid_d;
    genvar n;
    generate for(n=0;n<3;n=n+1) begin : ram
        reg [15:0] memory[0:(1<<ADDR_BITS)-1];
        reg [15:0] data_q;
        always @(posedge wr_clk)
            if(!wr_reset && !wr_start && writing && word_ok && write_bank==n)
                memory[wr_addr[ADDR_BITS-1:0]]<=wr_data;
        always @(posedge rd_clk) data_q<=memory[rd_addr[ADDR_BITS-1:0]];
        assign bank_data[n*16+:16]=data_q;
    end endgenerate
    always @(posedge rd_clk) begin
        read_bank_d<=rd_bank;
        read_valid_d<=rd_addr<WIDTH && rd_bank<3;
    end
    always @* rd_data=read_valid_d ? bank_data[read_bank_d*16+:16] : 16'b0;
endmodule
