// Check that AVI/AIF/SPD InfoFrames are still scheduled when AUDIO_EN=0.
`timescale 1ns/1ps

module tb_avi_check;

    reg clk_pix = 1'b0;
    reg clk5    = 1'b0;
    reg reset   = 1'b1;

    always #20 clk_pix = ~clk_pix;   // 25 MHz
    always #4  clk5    = ~clk5;      // 125 MHz

    reg [9:0] hcnt = 10'd0;
    reg [9:0] vcnt = 10'd0;
    reg hs = 1'b1, vs = 1'b1;

    always @(posedge clk_pix) begin
        if (hcnt < 10'd799) hcnt <= hcnt + 1'b1;
        else hcnt <= 10'd0;
    end
    always @(posedge clk_pix)
        if (hcnt == 10'd799) vcnt <= (vcnt < 10'd524) ? vcnt + 1'b1 : 10'd0;
    always @(posedge clk_pix)
        hs <= !((hcnt >= 10'd656) && (hcnt < 10'd752));
    always @* vs = !((vcnt >= 10'd490) && (vcnt < 10'd492));

    wire [23:0] pkt_header = u_core.pkt_header;
    wire [7:0]  pkt_type   = u_core.pkt_type;

    hdmi_tx_core #(
        .AUDIO_EN(0), .DVI_MODE(0), .AUDIO_FS(48000), .IT_CONTENT(1)
    ) u_core (
        .clk_pixel(clk_pix), .clk_pixel_x5(clk5), .reset(reset),
        .hcnt(hcnt), .vcnt(vcnt), .rgb(24'h123456), .hs(hs), .vs(vs),
        .audio_sample(32'd0), .audio_vol(8'hFF),
        .audio_empty(1'b1), .audio_overflow(1'b0),
        .audio_pop(), .audio_status(), .audio_pkt(),
        .HDMI_CLK_P(), .HDMI_D0_P(), .HDMI_D1_P(), .HDMI_D2_P()
    );

    integer n_avi = 0, n_aif = 0, n_spd = 0, n_null = 0, n_aud = 0;
    always @(posedge clk_pix) begin
        if (hcnt == 10'd654 || hcnt == 10'd686 ||
            hcnt == 10'd718 || hcnt == 10'd750) begin
            if (vcnt == 10'd0)
                $display("line0 slot type=%02h hdr=%06h", pkt_type, pkt_header);
            case (pkt_type)
                8'h82: n_avi  <= n_avi  + 1;
                8'h84: n_aif  <= n_aif  + 1;
                8'h83: n_spd  <= n_spd  + 1;
                8'h02: n_aud  <= n_aud  + 1;
                default: n_null <= n_null + 1;
            endcase
        end
    end

    reg [9:0] vpkt_line;
    always @* vpkt_line = vcnt;

    initial begin
        repeat (10) @(posedge clk_pix);
        reset = 1'b0;
        repeat (2_000_000) @(posedge clk_pix);   // ~1.6 frames
        $display("AUDIO_EN=0: avi=%0d aif=%0d spd=%0d aud=%0d null=%0d",
                 n_avi, n_aif, n_spd, n_aud, n_null);
        $finish;
    end

endmodule
