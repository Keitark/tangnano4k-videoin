module uvc_payload_source #(
    parameter integer PACKET_BYTES = 1024
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        start_packet,
    input  wire        end_of_frame,
    input  wire        consume,
    output reg  [7:0]  data,
    output reg         valid,
    output reg  [11:0] packet_length,
    output reg         packet_done
);
    reg [11:0] byte_index;
    reg frame_id;

    function [7:0] payload_byte;
        input [11:0] index;
        begin
            // Synthetic YUY2-like bars after the 12-byte UVC header.
            case (index[7:6])
                2'b00: payload_byte = index[0] ? 8'h80 : 8'hEB;
                2'b01: payload_byte = index[0] ? 8'h10 : 8'hD2;
                2'b10: payload_byte = index[0] ? 8'hF0 : 8'h91;
                default: payload_byte = index[0] ? 8'h80 : 8'h29;
            endcase
        end
    endfunction

    always @(*) begin
        case (byte_index)
            12'd0: data = 8'd12;                         // bHeaderLength
            12'd1: data = {6'b0, end_of_frame, frame_id}; // EOF/FID
            12'd2, 12'd3, 12'd4, 12'd5,
            12'd6, 12'd7, 12'd8, 12'd9,
            12'd10, 12'd11: data = 8'h00;
            default: data = payload_byte(byte_index - 12);
        endcase
    end

    always @(posedge clk) begin
        if (reset) begin
            byte_index <= 0;
            frame_id <= 0;
            valid <= 0;
            packet_length <= PACKET_BYTES;
            packet_done <= 0;
        end else begin
            packet_done <= 0;
            if (start_packet && !valid) begin
                byte_index <= 0;
                packet_length <= PACKET_BYTES;
                valid <= 1;
            end else if (valid && consume) begin
                if (byte_index == PACKET_BYTES - 1) begin
                    valid <= 0;
                    packet_done <= 1;
                    byte_index <= 0;
                    if (end_of_frame)
                        frame_id <= ~frame_id;
                end else begin
                    byte_index <= byte_index + 1'b1;
                end
            end
        end
    end
endmodule

