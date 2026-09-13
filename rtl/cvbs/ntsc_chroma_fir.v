// 16-phase sinusoidal reference (Q3 coefficients) and 16-sample sliding
// integration. Avoid the square-wave mixer's strong aliased odd harmonics.
module ntsc_chroma_fir (
    input wire clk, reset,
    input wire signed [13:0] chroma_q4,
    input wire [23:0] phase,
    output wire signed [14:0] mix_i, mix_q,
    output wire signed [15:0] filtered_i, filtered_q
);
    function signed [4:0] sine;
        input [3:0] p;
        begin
            case(p)
                0,8: sine=0;
                1,7: sine=3;
                2,6: sine=6;
                3,5: sine=7;
                4: sine=8;
                9,15: sine=-3;
                10,14: sine=-6;
                11,13: sine=-7;
                default: sine=-8;
            endcase
        end
    endfunction
    wire [3:0] cosine_phase=phase[23:20]+4'd4;
    wire signed [4:0] cos_c=sine(cosine_phase), sin_c=sine(phase[23:20]);
    wire signed [18:0] product_i=chroma_q4*cos_c, product_q=chroma_q4*sin_c;
    assign mix_i=product_i>>>3;
    assign mix_q=product_q>>>3;
    reg signed [14:0] history_i[0:15],history_q[0:15];
    reg signed [19:0] sum_i,sum_q;
    reg [3:0] pointer;
    integer k;
    wire signed [19:0] incoming_i={{5{mix_i[14]}},mix_i};
    wire signed [19:0] incoming_q={{5{mix_q[14]}},mix_q};
    wire signed [19:0] outgoing_i={{5{history_i[pointer][14]}},history_i[pointer]};
    wire signed [19:0] outgoing_q={{5{history_q[pointer][14]}},history_q[pointer]};
    always @(posedge clk) begin
        if(reset) begin
            pointer<=0; sum_i<=0; sum_q<=0;
            for(k=0;k<16;k=k+1) begin history_i[k]<=0; history_q[k]<=0; end
        end else begin
            sum_i<=sum_i+incoming_i-outgoing_i;
            sum_q<=sum_q+incoming_q-outgoing_q;
            history_i[pointer]<=mix_i; history_q[pointer]<=mix_q;
            pointer<=pointer+1'b1;
        end
    end
    assign filtered_i=sum_i>>>4;
    assign filtered_q=sum_q>>>4;
endmodule
