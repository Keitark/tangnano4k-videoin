module ntsc_lowres_frame_store #(
    parameter integer DATA_BITS = 4,
    parameter integer DEPTH = 30720
) (
    input  wire        wr_clk,
    input  wire        wr_en,
    input  wire [15:0] wr_addr,
    input  wire [DATA_BITS-1:0] wr_data,
    input  wire        rd_clk,
    input  wire [15:0] rd_addr,
    output reg  [DATA_BITS-1:0] rd_data
);
    generate if ((DEPTH > 32768 && DATA_BITS == 4) ||
                 (DEPTH > 16384 && DATA_BITS == 8)) begin : segmented
        // Gowin maps a flat 38400x4 RAM as twelve 16384x1 blocks. Explicit
        // 4096x4 segments use ten blocks and retain one-cycle read latency.
        localparam integer ADDRESS_BITS=DATA_BITS==8 ? 11 : 12;
        localparam integer SEGMENT_DEPTH=1<<ADDRESS_BITS;
        localparam integer SEGMENTS=(DEPTH+SEGMENT_DEPTH-1)/SEGMENT_DEPTH;
        wire [SEGMENTS*DATA_BITS-1:0] segment_data;
        reg [15-ADDRESS_BITS:0] read_segment;
        genvar s;
        for(s=0;s<SEGMENTS;s=s+1) begin : block_ram
            reg [DATA_BITS-1:0] memory[0:SEGMENT_DEPTH-1];
            reg [DATA_BITS-1:0] read_data;
            always @(posedge wr_clk)
                if(wr_en && wr_addr[15:ADDRESS_BITS]==s)
                    memory[wr_addr[ADDRESS_BITS-1:0]] <= wr_data;
            always @(posedge rd_clk)
                read_data <= memory[rd_addr[ADDRESS_BITS-1:0]];
            assign segment_data[s*DATA_BITS+:DATA_BITS]=read_data;
        end
        always @(posedge rd_clk) read_segment <= rd_addr[15:ADDRESS_BITS];
        always @* rd_data=segment_data[read_segment*DATA_BITS+:DATA_BITS];
    end else begin : flat
        // Keep the validated 128x120 path's original inference.
        reg [DATA_BITS-1:0] frame_memory [0:DEPTH-1];
        always @(posedge wr_clk)
            if (wr_en) frame_memory[wr_addr] <= wr_data;
        always @(posedge rd_clk) rd_data <= frame_memory[rd_addr];
    end endgenerate
endmodule
