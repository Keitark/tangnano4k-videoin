// Runtime pages without rebuilding: picture, raw bytes, calibration bytes.
// Each raw byte is packed into two adjacent grayscale nibbles: high then low.
// Sample every other 13.5MHz cycle => BANK_PIXELS/2 bytes at 6.75MHz.
// The producer never writes the displayed bank. Publication includes a stable
// page tag; an acknowledged HDMI frame-boundary handoff releases the old bank.
module runtime_video_probe #(
    parameter integer PAGE_TICKS = 67500000,
    parameter integer CYCLE_ONCE = 0,
    parameter integer BANK_PIXELS = 15360,
    parameter integer NIBBLE_RAW = 0,
    parameter integer DATA_BITS = 4
) (
    input wire clk, reset,
    input wire [7:0] raw_level,
    input wire picture_wr_en,
    input wire [14:0] picture_addr,
    input wire [DATA_BITS-1:0] picture_data,
    input wire picture_frame_toggle,
    input wire adopted_toggle_async,
    output reg wr_en,
    output reg [15:0] wr_addr,
    output reg [DATA_BITS-1:0] wr_data,
    output reg published_bank,
    output reg published_toggle,
    output reg [1:0] published_mode,
    output reg [15:0] last_picture_words,
    output reg [15:0] rejected_pictures,
    output reg [7:0] accepted_pictures,
    output reg [7:0] last_picture_flags
);
    localparam WAIT_FRAME=0, PICTURE=1, SNAPSHOT=2, WAIT_ACK=3, HOLD_PAGE=4, PUBLISH=5;
    reg [2:0] state;
    reg [26:0] page_ticks;
    reg [1:0] requested_mode;
    reg cycle_complete;
    reg [1:0] capture_mode;
    reg ack_meta, ack_sync;
    reg frame_seen;
    reg back_bank;
    reg [14:0] raw_addr;
    reg [3:0] raw_low;
    reg [15:0] picture_words;
    reg picture_bad;
    wire frame_event = picture_frame_toggle != frame_seen;
    wire [7:0] capture_byte = capture_mode == 2 ? raw_addr[8:1] : raw_level;
    // The boundary cycle may carry the FINAL word of the closing picture.
    // A count alone is insufficient: require each address exactly once, in order.
    wire picture_word_ok = picture_wr_en && !picture_bad &&
        picture_words < BANK_PIXELS && {1'b0,picture_addr} == picture_words;
    wire picture_word_bad = picture_wr_en && !picture_word_ok;
    wire [15:0] picture_words_next = picture_words + (picture_word_ok ? 16'd1 : 16'd0);
    wire picture_complete = !picture_bad && !picture_word_bad &&
        picture_words_next == BANK_PIXELS;

    always @(posedge clk) begin
        if(reset) begin
            state <= WAIT_FRAME;
            page_ticks <= 0;
            requested_mode <= 0;
            cycle_complete <= 0;
            capture_mode <= 0;
            ack_meta <= 0; ack_sync <= 0;
            frame_seen <= 0;
            back_bank <= 1; // HDMI initially reads bank zero.
            raw_addr <= 0; raw_low <= 0;
            picture_words <= 0; picture_bad <= 0;
            last_picture_words <= 0; rejected_pictures <= 0;
            accepted_pictures <= 0; last_picture_flags <= 0;
            published_bank <= 0; published_toggle <= 0; published_mode <= 0;
            wr_en <= 0; wr_addr <= 0; wr_data <= 0;
        end else begin
            ack_meta <= adopted_toggle_async;
            ack_sync <= ack_meta;
            frame_seen <= picture_frame_toggle;
            wr_en <= 0;
            if(CYCLE_ONCE && cycle_complete) begin
                page_ticks <= 0;
            end else if(page_ticks == PAGE_TICKS-1) begin
                page_ticks <= 0;
                requested_mode <= requested_mode == 2'd2 ? 2'd0 : requested_mode+2'd1;
                if(requested_mode == 2'd2) cycle_complete <= 1;
            end else page_ticks <= page_ticks+1'b1;
            case(state)
                WAIT_FRAME: begin
                    if(requested_mode != 0) begin
                        capture_mode <= requested_mode;
                        raw_addr <= 0;
                        state <= SNAPSHOT;
                    end else if(frame_event) begin
                        capture_mode <= 0;
                        picture_words <= 0; picture_bad <= 0;
                        state <= PICTURE;
                    end
                end
                PICTURE: begin
                    if(requested_mode != 0) begin
                        // Discard the unpublished partial picture bank.
                        capture_mode <= requested_mode;
                        raw_addr <= 0;
                        state <= SNAPSHOT;
                    end else begin
                        if(picture_word_ok) begin
                            wr_en <= 1;
                            wr_addr <= (back_bank ? BANK_PIXELS : 0) + picture_addr;
                            wr_data <= picture_data;
                            picture_words <= picture_words_next;
                        end
                        if(picture_word_bad) picture_bad <= 1;
                        if(frame_event) begin
                            last_picture_words <= picture_words_next;
                            // bit0: attempted; bit1: empty; bit2: incomplete;
                            // bit3: duplicate/out-of-order/out-of-range/extra word.
                            last_picture_flags <= {4'b0,
                                (picture_bad || picture_word_bad),
                                (picture_words_next != BANK_PIXELS),
                                (picture_words_next == 0),1'b1};
                            picture_words <= 0; picture_bad <= 0;
                            if(picture_complete) begin
                                published_bank <= back_bank;
                                published_mode <= 0;
                                accepted_pictures <= accepted_pictures + 1'b1;
                                state <= PUBLISH;
                            end else begin
                                if(!(&rejected_pictures))
                                    rejected_pictures <= rejected_pictures + 1'b1;
                                // Stay armed on this new field boundary. Never
                                // relabel stale diagnostic RAM as a picture.
                            end
                        end
                    end
                end
                SNAPSHOT: begin
                    wr_en <= 1;
                    wr_addr <= (back_bank ? BANK_PIXELS : 0) + raw_addr;
                    if(NIBBLE_RAW) begin
                        // Wide estimate has four meaningful high bits. Store
                        // one complete sample each13.5MHz cycle, not alternate
                        // bytes at6.75MHz, for unaliased color-burst inspection.
                        wr_data <= capture_mode == 2 ? raw_addr[3:0] : raw_level[7:4];
                    end else if(!raw_addr[0]) begin
                        wr_data <= capture_byte[7:4];
                        raw_low <= capture_byte[3:0];
                    end else wr_data <= raw_low;
                    if(raw_addr == BANK_PIXELS-1) begin
                        published_bank <= back_bank;
                        published_mode <= capture_mode;
                        state <= PUBLISH;
                    end else raw_addr <= raw_addr+1'b1;
                end
                PUBLISH: begin
                    // The memory consumes the final registered write on this
                    // edge. Only now announce the completed buffer.
                    published_toggle <= ~published_toggle;
                    state <= WAIT_ACK;
                end
                WAIT_ACK: begin
                    if(ack_sync == published_toggle) begin
                        back_bank <= ~published_bank;
                        state <= published_mode == 0 ? WAIT_FRAME : HOLD_PAGE;
                    end
                end
                HOLD_PAGE: if(requested_mode != published_mode) state <= WAIT_FRAME;
                default: state <= WAIT_FRAME;
            endcase
        end
    end
endmodule
