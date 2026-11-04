// -----------------------------------------------------------------------------
// TMDS encoder: video 8b/10b, control codes, TERC4 and both guard bands.
//
// Protocol references: HDMI 1.4a section 5.4.2 (control), 5.4.3 (TERC4),
// 5.4.4 (video encoding), 5.2.2.1 (video guard band) and 5.2.3.3 (data island
// guard bands).  Algorithm cross-checked against hdl-util/hdmi
// (src/tmds_channel.sv, Copyright (c) Sameer Puri, MIT OR Apache-2.0).
// -----------------------------------------------------------------------------
module tmds_encoder #(
    parameter CHANNEL = 0
) (
    input  wire       clk,
    input  wire       reset,
    input  wire [7:0] video_data,
    input  wire [3:0] island_data,
    input  wire [1:0] control_data,
    input  wire [2:0] mode,          // 0=control 1=video 2=video guard 3=island 4=island guard
    output reg  [9:0] tmds
);

    // ---- control symbols (section 5.4.2) --------------------------------
    function [9:0] control_symbol;
        input [1:0] c;
        begin
            case (c)
                2'b00: control_symbol = 10'b1101010100;
                2'b01: control_symbol = 10'b0010101011;
                2'b10: control_symbol = 10'b0101010100;
                2'b11: control_symbol = 10'b1010101011;
            endcase
        end
    endfunction

    // ---- TERC4 symbols (section 5.4.3, Table 5-5) ------------------------
    function [9:0] terc4_symbol;
        input [3:0] d;
        begin
            case (d)
                4'h0: terc4_symbol = 10'b1010011100;
                4'h1: terc4_symbol = 10'b1001100011;
                4'h2: terc4_symbol = 10'b1011100100;
                4'h3: terc4_symbol = 10'b1011100010;
                4'h4: terc4_symbol = 10'b0101110001;
                4'h5: terc4_symbol = 10'b0100011110;
                4'h6: terc4_symbol = 10'b0110001110;
                4'h7: terc4_symbol = 10'b0100111100;
                4'h8: terc4_symbol = 10'b1011001100;
                4'h9: terc4_symbol = 10'b0100111001;
                4'hA: terc4_symbol = 10'b0110011100;
                4'hB: terc4_symbol = 10'b1011000110;
                4'hC: terc4_symbol = 10'b1010001110;
                4'hD: terc4_symbol = 10'b1001110001;
                4'hE: terc4_symbol = 10'b0101100011;
                4'hF: terc4_symbol = 10'b1011000011;
            endcase
        end
    endfunction

    // ---- guard bands -----------------------------------------------------
    wire [9:0] video_guard_symbol =
        (CHANNEL == 1) ? 10'b0100110011 : 10'b1011001100;
    // Channel 0 carries TERC4({11, HS, VS}) during the data island guard
    // band, channels 1/2 carry the fixed 0100110011 pattern.
    wire [9:0] island_guard_symbol =
        (CHANNEL == 1 || CHANNEL == 2) ? 10'b0100110011
                                       : terc4_symbol({2'b11, control_data});

    // ---- video 8b/10b (section 5.4.4, figure 5-7) ------------------------
    reg  [8:0]        q_m;
    reg  [9:0]        q_out;
    reg  [3:0]        n1d;
    reg  [3:0]        n1q_m;
    reg  signed [4:0] acc;
    reg  signed [4:0] acc_add;
    reg               use_xnor;
    reg               qm_bit;
    integer           i;

    // One combinational block: avoids zero-delay races between intermediate
    // signals (q_m -> n1q_m -> q_out) in event-driven simulators.
    always @* begin
        n1d = video_data[0] + video_data[1] + video_data[2] + video_data[3] +
              video_data[4] + video_data[5] + video_data[6] + video_data[7];

        // Run the XOR/XNOR chain in a local variable: q_m must not be read in
        // the same always block that writes it (delta-cycle hazard).
        use_xnor = (n1d > 4'd4) || (n1d == 4'd4 && video_data[0] == 1'b0);
        qm_bit   = video_data[0];
        q_m[0]   = qm_bit;
        for (i = 0; i < 7; i = i + 1) begin
            if (use_xnor)
                qm_bit = qm_bit ~^ video_data[i + 1];
            else
                qm_bit = qm_bit ^ video_data[i + 1];
            q_m[i + 1] = qm_bit;
        end
        q_m[8] = use_xnor ? 1'b0 : 1'b1;

        n1q_m = q_m[0] + q_m[1] + q_m[2] + q_m[3] +
                q_m[4] + q_m[5] + q_m[6] + q_m[7];

        if (acc == 5'sd0 || n1q_m == (4'd8 - n1q_m)) begin
            if (q_m[8]) begin
                acc_add = $signed({1'b0, n1q_m}) -
                          $signed({1'b0, (4'd8 - n1q_m)});
                q_out   = {~q_m[8], q_m[8], q_m[7:0]};
            end else begin
                acc_add = $signed({1'b0, (4'd8 - n1q_m)}) -
                          $signed({1'b0, n1q_m});
                q_out   = {~q_m[8], q_m[8], ~q_m[7:0]};
            end
        end else begin
            if ((acc > 5'sd0 && n1q_m > (4'd8 - n1q_m)) ||
                (acc < 5'sd0 && n1q_m < (4'd8 - n1q_m))) begin
                q_out   = {1'b1, q_m[8], ~q_m[7:0]};
                acc_add = $signed({1'b0, (4'd8 - n1q_m)}) -
                          $signed({1'b0, n1q_m}) +
                          (q_m[8] ? 5'sd2 : 5'sd0);
            end else begin
                q_out   = {1'b0, q_m[8], q_m[7:0]};
                acc_add = $signed({1'b0, n1q_m}) -
                          $signed({1'b0, (4'd8 - n1q_m)}) -
                          (~q_m[8] ? 5'sd2 : 5'sd0);
            end
        end
    end

    always @(posedge clk) begin
        if (reset)
            acc <= 5'sd0;
        else if (mode != 3'd1)
            acc <= 5'sd0;
        else
            acc <= acc + acc_add;
    end

    // ---- output register -------------------------------------------------
    always @(posedge clk) begin
        if (reset)
            tmds <= 10'b1101010100;
        else case (mode)
            3'd0: tmds <= control_symbol(control_data);
            3'd1: tmds <= q_out;
            3'd2: tmds <= video_guard_symbol;
            3'd3: tmds <= terc4_symbol(island_data);
            3'd4: tmds <= island_guard_symbol;
            default: tmds <= 10'b1101010100;
        endcase
    end

endmodule
