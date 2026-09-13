create_clock -name clk_27m -period 37.037 [get_ports {clk_27m}]
# First-stage synchronizers only; the second-stage and ownership logic remain timed.
set_false_path -to [get_pins {core/status_snapshot/request_meta_s0/D core/status_snapshot/ack_meta_s0/D core/sync_meta_s0/D}]
set_false_path -to [get_pins {core/streaming.queue/returned_meta*_s0/D core/streaming.queue/published_meta*_s0/D}]
set_false_path -to [get_pins {core/streaming.transmitter/lock_meta_s0/D core/streaming.transmitter/color_meta_s0/D}]
# Status holds through ACK. Tags hold from line START until consumer RELEASE;
# their publication token is emitted after the last RAM write and crosses 2 FFs.
# One pixel period bounds each bundled-data path; no broad clock-group exceptions.
set_max_delay -from [get_pins {core/status_snapshot/held_data*_s0/Q}] -to [get_pins {core/status_snapshot/dst_data*_s0/D}] 39.682
# Include synthesis replicas (_s1 etc.) of the same held tag registers.
set_max_delay -from [get_pins {core/streaming.queue/tag*_s*/Q}] 39.682
set_false_path -to [get_pins {core/streaming.transmitter/serializers[0]/RESET core/streaming.transmitter/serializers[1]/RESET core/streaming.transmitter/serializers[2]/RESET}]
