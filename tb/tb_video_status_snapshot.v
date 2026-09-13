`timescale 1ns/1ps
module tb_video_status_snapshot;
    reg src_clk=0, dst_clk=0, reset=1, request=0;
    reg [15:0] sequence_id=0;
    wire [47:0] source={sequence_id,~sequence_id,sequence_id^16'h55aa};
    wire [47:0] result;
    integer k, changes=0;
    reg [47:0] previous=0;
    always #7 src_clk=~src_clk;
    always #11 dst_clk=~dst_clk;
    always @(posedge src_clk) if(reset) sequence_id<=0; else sequence_id<=sequence_id+1;
    video_status_snapshot dut(.src_clk(src_clk),.src_reset(reset),.src_data(source),
        .dst_clk(dst_clk),.dst_reset(reset),.dst_request(request),.dst_data(result));
    always @(negedge dst_clk) if(!reset && result!=previous) begin
        changes=changes+1; previous=result;
        if(result[31:16] !== ~result[47:32] || result[15:0] !== (result[47:32]^16'h55aa))
            $fatal(1,"torn status snapshot");
    end
    initial begin
        repeat(6) @(negedge dst_clk); reset=0;
        for(k=0;k<1000;k=k+1) begin
            @(negedge dst_clk); request=($urandom_range(0,3)==0);
        end
        request=0; repeat(15) @(negedge dst_clk);
        if(changes<40) $fatal(1,"status handshake stalled");
        $display("PASS %d coherent asynchronous snapshots",changes);
        $finish;
    end
endmodule
