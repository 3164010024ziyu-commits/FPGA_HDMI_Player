// Scratch testbench: audio source (48 kHz, 50 MHz sys clk) -> audio_fifo ->
// hdmi_tx_core packet picker.  Prints every scheduled packet.
`timescale 1ns/1ps

module tb_audio_pipe;

    reg clk_pix = 1'b0;
    reg clk5    = 1'b0;
    reg clk50   = 1'b0;
    reg reset   = 1'b1;

    always #20 clk_pix = ~clk_pix;   // 25 MHz
    always #4  clk5    = ~clk5;      // 125 MHz
    always #10 clk50   = ~clk50;     // 50 MHz

    // ---------------------------------------------------- 640x480 timing
    localparam H_TOTAL = 800;
    localparam V_TOTAL = 525;
    localparam H_SYNC_START = 656, H_SYNC_END = 752;
    localparam V_SYNC_START = 490, V_SYNC_END = 492;

    reg [9:0] hcnt = 10'd0;
    reg [9:0] vcnt = 10'd0;
    reg hs = 1'b1;
    reg vs = 1'b1;

    always @(posedge clk_pix) begin
        if (hcnt < H_TOTAL-1) hcnt <= hcnt + 1'b1;
        else                  hcnt <= 10'd0;
    end
    always @(posedge clk_pix) begin
        if (hcnt == H_TOTAL-1) vcnt <= (vcnt < V_TOTAL-1) ? vcnt + 1'b1 : 10'd0;
    end
    always @(posedge clk_pix)
        hs <= !((hcnt >= H_SYNC_START) && (hcnt < H_SYNC_END));
    always @* vs = !((vcnt >= V_SYNC_START) && (vcnt < V_SYNC_END));

    // ---------------------------------------------------- 48 kHz source
    localparam integer SYS_HZ = 50_000_000;
    localparam integer FS     = 48_000;

    reg [31:0] fs_acc = 32'd0;
    reg [15:0] sample = 16'd0;
    reg        avalid = 1'b0;
    always @(posedge clk50 or posedge reset) begin
        if (reset) begin fs_acc <= 0; sample <= 0; avalid <= 0; end
        else if (fs_acc + FS >= SYS_HZ) begin
            fs_acc  <= fs_acc + FS - SYS_HZ;
            sample  <= sample + 16'd1;
            avalid  <= 1'b1;
        end else begin
            fs_acc <= fs_acc + FS;
            avalid <= 1'b0;
        end
    end
    wire [31:0] audio_sample = {sample, sample};

    // ------------------------------------------------------------ DUTs
    wire [31:0] rd_data;
    wire        empty, full, ovf, pop;
    wire [1:0]  status;
    wire        audio_pkt;

    audio_fifo #(.AWIDTH(5)) u_fifo (
        .wr_clk(clk50), .wr_rst(reset), .wr_en(avalid), .wr_data(audio_sample),
        .full(full), .overflow(ovf),
        .rd_clk(clk_pix), .rd_rst(reset), .rd_en(pop), .rd_data(rd_data),
        .empty(empty)
    );

    wire [23:0] pkt_header = u_core.pkt_header;
    wire [7:0]  pkt_type   = u_core.pkt_type;
    wire [8:0]  pkt_data   = u_core.pkt_data;
    wire [55:0] pkt_sub0   = u_core.pkt_sub0;
    wire [55:0] pkt_sub1   = u_core.pkt_sub1;
    wire [55:0] pkt_sub2   = u_core.pkt_sub2;
    wire [55:0] pkt_sub3   = u_core.pkt_sub3;
    wire [9:0]  tmds0, tmds1, tmds2;

    hdmi_tx_core #(
        .AUDIO_EN(1), .DVI_MODE(0), .AUDIO_FS(48000), .IT_CONTENT(1)
    ) u_core (
        .clk_pixel(clk_pix), .clk_pixel_x5(clk5), .reset(reset),
        .hcnt(hcnt), .vcnt(vcnt), .rgb(24'h123456), .hs(hs), .vs(vs),
        .audio_sample(rd_data), .audio_vol(8'hFF),
        .audio_empty(empty), .audio_overflow(ovf),
        .audio_pop(pop), .audio_status(status), .audio_pkt(audio_pkt),
        .HDMI_CLK_P(), .HDMI_D0_P(), .HDMI_D1_P(), .HDMI_D2_P()
    );

    // ---------------------------------------------------------- monitors
    integer n_acr = 0, n_aud = 0, n_avi = 0, n_aif = 0, n_spd = 0, n_null = 0;
    integer n_bstart = 0;
    integer n_pix = 0;
    integer n_frames = 0;
    integer cts_min = 32'h000FFFFF, cts_max = 0, cts_sum = 0, cts_n = 0;

    always @(posedge clk_pix) begin
        n_pix <= n_pix + 1;
        if (hcnt == 10'd799 && vcnt == 10'd524) begin
            n_frames <= n_frames + 1;
            $display("FRAME %0d  pix=%0d acr=%0d aud=%0d avi=%0d aif=%0d spd=%0d null=%0d fifo_empty=%b ovf=%b",
                     n_frames, n_pix, n_acr, n_aud, n_avi, n_aif, n_spd, n_null, empty, ovf);
        end

        // packet loaded at the slot pulse; inspect one cycle after the slot
        if (hcnt == 10'd654 || hcnt == 10'd686 || hcnt == 10'd718 || hcnt == 10'd750) begin
            case (pkt_type)
                8'h01: n_acr  <= n_acr  + 1;
                8'h02: n_aud  <= n_aud  + 1;
                8'h82: n_avi  <= n_avi  + 1;
                8'h84: n_aif  <= n_aif  + 1;
                8'h83: n_spd  <= n_spd  + 1;
                default: n_null <= n_null + 1;
            endcase
            if (pkt_type == 8'h01) begin
                cts_n   <= cts_n + 1;
                cts_sum <= cts_sum + u_core.u_picker.acr_cts;
                if (u_core.u_picker.acr_cts < cts_min) cts_min <= u_core.u_picker.acr_cts;
                if (u_core.u_picker.acr_cts > cts_max) cts_max <= u_core.u_picker.acr_cts;
            end
            if (pkt_type == 8'h02 && pkt_header[20])
                n_bstart <= n_bstart + 1;
            if (pkt_type == 8'h02 && u_core.u_picker.frame_counter > 8'd188)
                $display("ERROR frame_counter out of range at %0t: %0d", $time,
                         u_core.u_picker.frame_counter);
            if (n_frames < 2 && (pkt_type == 8'h02 || pkt_type == 8'h01))
                $display("t=%0t line=%0d slot=%0d type=%02h hdr=%06h s0=%014h s1=%014h s2=%014h s3=%014h",
                         $time, vcnt, (hcnt==654)?0:(hcnt==686)?1:(hcnt==718)?2:3,
                         pkt_type, pkt_header, pkt_sub0, pkt_sub1, pkt_sub2, pkt_sub3);
        end
    end

    // dump the 9-bit island stream of one complete island (line 0, first island)
    always @(posedge clk_pix) begin
        if (vcnt == 10'd0 && hcnt >= 10'd654 && hcnt < 10'd782)
            $display("ISL %0d %03h", hcnt - 654, pkt_data);
    end

    // dump TMDS symbols around the leading guard band of line 0
    always @(posedge clk_pix) begin
        if (vcnt == 10'd0 && ((hcnt >= 10'd640 && hcnt < 10'd665) ||
                              (hcnt >= 10'd778 && hcnt < 10'd792)))
            $display("PIX %0d mode=%0d t0=%03h t1=%03h t2=%03h isl=%03h",
                     hcnt, u_core.mode_r, u_core.tmds0, u_core.tmds1, u_core.tmds2, u_core.island_r);
    end

    initial begin
        reset = 1'b1;
        repeat (20) @(posedge clk_pix);
        reset = 1'b0;
        repeat (3000000) @(posedge clk_pix);
        $display("DONE frames=%0d pix=%0d acr=%0d aud=%0d avi=%0d aif=%0d spd=%0d null=%0d bstart=%0d",
                 n_frames, n_pix, n_acr, n_aud, n_avi, n_aif, n_spd, n_null, n_bstart);
        $display("CTS min=%0d max=%0d avg=%0d n=%0d", cts_min, cts_max,
                 (cts_n == 0) ? 0 : cts_sum / cts_n, cts_n);
        $finish;
    end

endmodule
