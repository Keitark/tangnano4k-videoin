// Bundled-data request/acknowledge snapshot. Source holds the bus until the
// next request; only synchronized tokens control capture of that stable bus.
// Both domain resets must be asserted together when restarting the video path.
module video_status_snapshot #(parameter integer WIDTH=48) (
    input wire src_clk, src_reset,
    input wire [WIDTH-1:0] src_data,
    input wire dst_clk, dst_reset, dst_request,
    output reg [WIDTH-1:0] dst_data
);
    reg request_toggle;
    reg request_meta, request_sync, ack_toggle;
    reg ack_meta, ack_sync, ack_seen;
    reg [WIDTH-1:0] held_data;
    always @(posedge src_clk) begin
        if(src_reset) begin
            request_meta<=0; request_sync<=0; ack_toggle<=0; held_data<=0;
        end else begin
            request_meta<=request_toggle; request_sync<=request_meta;
            if(request_sync!=ack_toggle) begin
                held_data<=src_data;
                ack_toggle<=request_sync;
            end
        end
    end
    always @(posedge dst_clk) begin
        if(dst_reset) begin
            request_toggle<=0; ack_meta<=0; ack_sync<=0; ack_seen<=0; dst_data<=0;
        end else begin
            ack_meta<=ack_toggle; ack_sync<=ack_meta;
            if(ack_sync!=ack_seen) begin
                dst_data<=held_data;
                ack_seen<=ack_sync;
            end
            if(dst_request && request_toggle==ack_seen)
                request_toggle<=~request_toggle;
        end
    end
endmodule
