module ntsc_line_store (
    input  wire        wr_clk,
    input  wire        wr_reset,
    input  wire        wr_en,
    input  wire [9:0]  wr_addr,
    input  wire [15:0] wr_data,
    input  wire        wr_line_done,
    output reg  [1:0]  completed_bank,
    output reg         completed_toggle,
    input  wire        rd_clk,
    input  wire [1:0]  rd_bank,
    input  wire [9:0]  rd_addr,
    output reg  [15:0] rd_data
);
    reg [1:0] write_bank;
    reg [15:0] bank0 [0:639];
    reg [15:0] bank1 [0:639];
    reg [15:0] bank2 [0:639];

    always @(posedge wr_clk) begin
        if (wr_reset) begin
            write_bank <= 2'd0;
            completed_bank <= 2'd0;
            completed_toggle <= 1'b0;
        end else begin
            if (wr_en) begin
                case (write_bank)
                    2'd0: bank0[wr_addr] <= wr_data;
                    2'd1: bank1[wr_addr] <= wr_data;
                    default: bank2[wr_addr] <= wr_data;
                endcase
            end
            if (wr_line_done) begin
                completed_bank <= write_bank;
                completed_toggle <= ~completed_toggle;
                write_bank <= (write_bank == 2'd2) ? 2'd0 :
                              write_bank + 1'b1;
            end
        end
    end

    always @(posedge rd_clk) begin
        case (rd_bank)
            2'd0: rd_data <= bank0[rd_addr];
            2'd1: rd_data <= bank1[rd_addr];
            default: rd_data <= bank2[rd_addr];
        endcase
    end
endmodule
