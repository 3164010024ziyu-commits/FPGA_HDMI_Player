// -----------------------------------------------------------------------------
// HDMI display component: 640x480p60 video + audio + two-slot Chinese OSD.
//
// Video is always available; audio and subtitles can be disabled with the
// HDMI_AUDIO_EN / HDMI_SUBTITLE_EN parameters.  Runtime control comes from
// seven debounced keys.  Four are momentary push buttons (active low, pressed
// = 0, one action per press):
//
//   key_in[0]  VOL+      20-step volume, level 0..19 -> 0 .. 255 (5 %/step)
//   key_in[1]  VOL-      (level 0 is digital silence, level 19 is 0 dB)
//   key_in[5]  SUB <-    move the normal subtitle one character (16 px) left
//   key_in[6]  SUB ->    move the normal subtitle one character (16 px) right
//
// Three are latching toggle switches, read as levels (SWITCH_ON_LOW=1 means
// the "on" position pulls the pin low):
//
//   key_in[2]  MUTE      mute on/off, the volume level is kept
//   key_in[3]  SUB ON    normal subtitle on/off
//   key_in[4]  TS ON     timestamp subtitle on/off (independent of SUB ON)
//
// All key processing runs in the pixel clock domain: two flip-flop
// synchroniser, ~10 ms debounce per key, then a one-cycle press strobe for
// the momentary keys.
// -----------------------------------------------------------------------------
module hdmi_tx_display #(
    parameter integer AUDIO_FS        = 48000,  // 44100 or 48000
    parameter integer HDMI_AUDIO_EN   = 1,
    parameter integer HDMI_SUBTITLE_EN = 1,
    parameter integer HDMI_LOGO_EN    = 1,   // fixed bitmap watermark (BRAM)
    parameter integer IMAGE_FADE_EN    = 0,
    parameter integer ENABLE_AV_SYNC   = 0,
    parameter integer ENABLE_SPECTRUM = 0,
    parameter integer SPECTRUM_DB_CYCLES = 262144,
    parameter integer DVI_MODE        = 0,
    parameter integer TS_X            = 8,
    parameter integer TS_Y            = 448,
    parameter integer SUB_X_INIT      = 200,    // normal subtitle start column
    parameter integer KEY_ACTIVE_LOW  = 1,
    parameter integer SWITCH_ON_LOW   = 1,
    // parameter banner on-time: 3 s at 25 MHz (override in simulation)
    parameter integer BANNER_CYCLES   = 75_000_000
) (
    input  wire        sys_clk,
    input  wire        sys_rst_n,

    // video source interface
    input  wire [23:0] pix_rgb,
    input  wire [5:0]  fade_level, // pixel-domain Q5 gain 0..32
    input  wire        pix_valid,
    input  wire        frame_ready,
    input  wire        pix_underflow,

    output wire        pix_clk,
    output wire        pix_reset_n,
    output wire        pix_req,
    output wire        frame_sync,

    // audio source interface (asynchronous sample clock domain)
    input  wire        audio_clk,
    input  wire [31:0] audio_sample,   // {L[15:0], R[15:0]}
    input  wire        audio_valid,
    input wire [2:0] audio_tag,input wire audio_epoch,
    output reg transition_toggle,output reg pause_request,
    input wire display_info_valid,input wire [135:0] display_info,
    input wire text_glyph_we,input wire [9:0] text_glyph_addr,input wire [15:0] text_glyph_data,
    input wire text_commit,input wire [6:0] text_length,input wire text_has_text,input wire text_abort,
    output wire text_cache_ready,
    output wire        audio_ready,
    output wire [1:0]  audio_status,   // {overflow, underflow}
    output wire        audio_pkt,      // Audio Sample Packet activity

    // runtime key control (pixel clock domain, debounced internally)
    input  wire [6:0]  key_in,
    // image adjustment keys: {CON-, CON+, BRT-, BRT+}, pressed = 0
    input  wire [3:0]  key_img,
    input wire spectrum_key_n,audio_playing,

    // OSD text write port (content is supplied by the top level)
    input  wire        osd_slot,
    input  wire [3:0]  osd_char_idx,
    input  wire [15:0] osd_char_code,  // GB2312
    input  wire        osd_char_we,
    input  wire [9:0]  osd_y,
    input  wire [23:0] osd_fg,

    output wire        HDMI_CLK_P,
    output wire        HDMI_D2_P,
    output wire        HDMI_D1_P,
    output wire        HDMI_D0_P
);

    wire        VGA_DE;
    wire [23:0] VGA_D;
    wire [23:0] OSD_D;
    wire [23:0] SPECTRUM_D;
    wire        VGA_HS, VGA_VS;
    wire [9:0]  VGA_X;
    wire [9:0]  VGA_Y;

    wire pixel_clk;
wire pixel_clk_5x;
    wire pll_locked;
    wire reset_request = !sys_rst_n || !pll_locked;
    reg [1:0] pixel_release;
    always @(posedge pixel_clk or posedge reset_request) begin
        if(reset_request) pixel_release <= 0;
        else pixel_release <= {pixel_release[0],1'b1};
    end
    wire video_reset_n = pixel_release[1];
    assign pix_reset_n = video_reset_n;

    assign pix_clk = pixel_clk;

    // ------------------------------------------------------------------ PLL
    clk_wize u_clk_wize (
        .refclk   (sys_clk),
        .reset    (1'b0),
        .extlock  (pll_locked),
        .clk0_out (pixel_clk_5x),
        .clk1_out (pixel_clk)
    );

    // ------------------------------------------------------------- timing
    read_RAM u_read_RAM (
        .clk25M     (pixel_clk),
        .reset_n    (video_reset_n),
        .pix_rgb    (pix_rgb),
        .pix_valid  (pix_valid),

        .pix_req    (pix_req),
        .frame_sync (frame_sync),
        .HDMI_HSYNC (VGA_HS),
        .HDMI_VSYNC (VGA_VS),
        .HDMI_X     (VGA_X),
        .HDMI_Y     (VGA_Y),
        .HDMI_EN    (VGA_DE),
        .HDMI_D     (VGA_D)
    );

    // ------------------------------------------------------- key control
    localparam [4:0]  VOL_LEVEL_MAX = 5'd19;     // 0..19 -> twenty steps
    localparam [9:0]  SUB_STEP      = 10'd16;    // one 16-pixel character
    localparam [9:0]  SUB_X_START   = SUB_X_INIT[9:0];
    localparam [9:0]  SUB_X_MAX     = 10'd400;   // 640 - 15*16
    localparam [17:0] KEY_DB_MAX    = 18'h3FFFF; // ~10.5 ms at 25 MHz

    // 11 debounced keys: bits 0..6 come from key_in, bits 7..10 from key_img
    wire [10:0] keys_in = {key_img, key_in};
    reg [10:0] key_meta, key_sync, key_stable, key_stable_d;
    reg [17:0] key_timer [0:10];
    integer    ki;

    always @(posedge pixel_clk or negedge video_reset_n) begin
        if (!video_reset_n) begin
            key_meta     <= 11'd0;
            key_sync     <= 11'd0;
            key_stable   <= 11'h7FF;  // all released / switches "off"
            key_stable_d <= 11'h7FF;
            for (ki = 0; ki < 11; ki = ki + 1)
                key_timer[ki] <= 18'd0;
        end else begin
            key_meta     <= keys_in;
            key_sync     <= key_meta;
            key_stable_d <= key_stable;

            for (ki = 0; ki < 11; ki = ki + 1) begin
                if (key_sync[ki] == key_stable[ki]) begin
                    key_timer[ki] <= 18'd0;
                end else if (key_timer[ki] == KEY_DB_MAX) begin
                    key_stable[ki] <= key_sync[ki];
                    key_timer[ki]  <= 18'd0;
                end else begin
                    key_timer[ki] <= key_timer[ki] + 18'd1;
                end
            end
        end
    end

    // one-cycle press strobe for the momentary keys (active low: pressed = 0)
    wire [10:0] key_press = (KEY_ACTIVE_LOW != 0)
                            ? (~key_stable &  key_stable_d)
                            : ( key_stable & ~key_stable_d);

    // latching switches: the debounced pin level *is* the state
    wire sw_mute = (SWITCH_ON_LOW != 0) ? ~key_stable[2] : key_stable[2];
    wire sw_sub  = (SWITCH_ON_LOW != 0) ? ~key_stable[3] : key_stable[3];
    wire sw_ts   = (SWITCH_ON_LOW != 0) ? ~key_stable[4] : key_stable[4];

    reg [4:0]  vol_level;
    reg [9:0]  sub_x;

    // level 0..19 -> 0 .. 255 (255/19 = 13.42 per step)
    function [7:0] vol_code;
        input [4:0] lvl;
        begin
            case (lvl)
                5'd0:  vol_code = 8'd0;
                5'd1:  vol_code = 8'd13;
                5'd2:  vol_code = 8'd27;
                5'd3:  vol_code = 8'd40;
                5'd4:  vol_code = 8'd54;
                5'd5:  vol_code = 8'd67;
                5'd6:  vol_code = 8'd81;
                5'd7:  vol_code = 8'd94;
                5'd8:  vol_code = 8'd107;
                5'd9:  vol_code = 8'd121;
                5'd10: vol_code = 8'd134;
                5'd11: vol_code = 8'd148;
                5'd12: vol_code = 8'd161;
                5'd13: vol_code = 8'd174;
                5'd14: vol_code = 8'd188;
                5'd15: vol_code = 8'd201;
                5'd16: vol_code = 8'd215;
                5'd17: vol_code = 8'd228;
                5'd18: vol_code = 8'd242;
                5'd19: vol_code = 8'd255;
                default: vol_code = 8'd255;
            endcase
        end
    endfunction

    always @(posedge pixel_clk or negedge video_reset_n) begin
        if (!video_reset_n) begin
            vol_level <= VOL_LEVEL_MAX;
            sub_x     <= SUB_X_START;
        end else begin
            if (key_press[0] && (vol_level != VOL_LEVEL_MAX))
                vol_level <= vol_level + 5'd1;
            if (key_press[1] && (vol_level != 5'd0))
                vol_level <= vol_level - 5'd1;
            if (key_press[5] && (sub_x >= SUB_STEP))
                sub_x <= sub_x - SUB_STEP;
            if (key_press[6] && (sub_x <= SUB_X_MAX - SUB_STEP))
                sub_x <= sub_x + SUB_STEP;
        end
    end

    // key_in[2] is the mute switch again: silence the HDMI audio without
    // stopping the show.  It must not drive pause_request.
    wire [7:0] volume = sw_mute ? 8'd0 : vol_code(vol_level);
    wire [1:0] osd_en = (HDMI_SUBTITLE_EN != 0) ? {sw_ts, sw_sub} : 2'b00;

    // ------------------------------------------- image brightness / contrast
    localparam [4:0] IMG_LEVEL_MAX = 5'd20;   // 0..20, 5 % per step
    localparam [4:0] IMG_LEVEL_DEF = 5'd10;   // 1.0x gain, zero offset

    reg [4:0]  bri, con;
    reg [1:0]  param_sel;
    reg [4:0]  param_val;
    reg [26:0] banner_timer;
    reg        sw_mute_d;

    wire signed [8:0] img_off  = ($signed({1'b0, bri}) - 9'sd10) * 9'sd6; // -60..60
    wire [9:0]        con_gain = {2'b0, con} * 6'd16;                     // 0..320
    wire [6:0]        img_gain = 7'd32 + con_gain / 5;                    // Q6 0.5..1.5

    function [7:0] img_adj;
        input [7:0]        px;
        input signed [8:0] off;
        input [6:0]        gain;
        reg signed [17:0]  t;
        begin
            t = ($signed({1'b0, px}) - 18'sd128) * $signed({1'b0, gain});
            t = (t >>> 6) + 18'sd128 + off;
            img_adj = (t < 0) ? 8'd0 : (t > 18'sd255) ? 8'd255 : t[7:0];
        end
    endfunction

    wire [23:0] VGA_ADJ = {
        img_adj(VGA_D[23:16], img_off, img_gain),
        img_adj(VGA_D[15:8],  img_off, img_gain),
        img_adj(VGA_D[7:0],   img_off, img_gain)
    };

    // parameter banner: last adjusted parameter wins, visible for BANNER_CYCLES
    always @(posedge pixel_clk or negedge video_reset_n) begin
        if (!video_reset_n) begin
            bri          <= IMG_LEVEL_DEF;
            con          <= IMG_LEVEL_DEF;
            param_sel    <= 2'd0;
            param_val    <= 5'd0;
            banner_timer <= 27'd0;
            sw_mute_d    <= 1'b0;
        end else begin
            if (banner_timer != 27'd0)
                banner_timer <= banner_timer - 27'd1;
            sw_mute_d <= sw_mute;

            if (key_press[7] && (bri != IMG_LEVEL_MAX)) begin
                bri <= bri + 5'd1;
                param_sel <= 2'd0; param_val <= bri + 5'd1;
                banner_timer <= BANNER_CYCLES;
            end else if (key_press[8] && (bri != 5'd0)) begin
                bri <= bri - 5'd1;
                param_sel <= 2'd0; param_val <= bri - 5'd1;
                banner_timer <= BANNER_CYCLES;
            end else if (key_press[9] && (con != IMG_LEVEL_MAX)) begin
                con <= con + 5'd1;
                param_sel <= 2'd1; param_val <= con + 5'd1;
                banner_timer <= BANNER_CYCLES;
            end else if (key_press[10] && (con != 5'd0)) begin
                con <= con - 5'd1;
                param_sel <= 2'd1; param_val <= con - 5'd1;
                banner_timer <= BANNER_CYCLES;
            end else if (key_press[0] && (vol_level != VOL_LEVEL_MAX)) begin
                param_sel <= 2'd2; param_val <= vol_level + 5'd1;
                banner_timer <= BANNER_CYCLES;
            end else if (key_press[1] && (vol_level != 5'd0)) begin
                param_sel <= 2'd2; param_val <= vol_level - 5'd1;
                banner_timer <= BANNER_CYCLES;
            end else if (sw_mute != sw_mute_d) begin
                param_sel <= 2'd2;
                param_val <= sw_mute ? 5'd0 : vol_level;
                banner_timer <= BANNER_CYCLES;
            end
        end
    end


    // Fade adjusted image toward black; no extra SDRAM reads or pixel latency.
    // Apply after brightness so even a positive offset reaches true black.
    function [7:0] fade_channel;
        input [7:0] channel;
        input [5:0] level;
        reg [13:0] product;
        begin product=channel*level;fade_channel=product[12:5];end
    endfunction
    wire [23:0] FADE_D=IMAGE_FADE_EN ? {
        fade_channel(VGA_ADJ[23:16],fade_level),
        fade_channel(VGA_ADJ[15:8],fade_level),
        fade_channel(VGA_ADJ[7:0],fade_level)} : VGA_ADJ;
    wire [31:0] audio_rd_data;wire [2:0] audio_rd_tag;
    wire [31:0] queued_audio_data;wire [2:0] queued_audio_tag;wire queued_audio_epoch;
    reg [5:0] previous_fade;reg transition_start,expected_epoch;
    always @(posedge pixel_clk or negedge video_reset_n)begin
        if(!video_reset_n)begin previous_fade<=32;transition_start<=0;transition_toggle<=0;expected_epoch<=0;pause_request<=0;end
        else begin
            previous_fade<=fade_level;transition_start<=0;pause_request<=1'b0;
            if(ENABLE_AV_SYNC!=0 && (IMAGE_FADE_EN ?
                (previous_fade==32 && fade_level<32) : display_info_valid))begin
                transition_start<=1;transition_toggle<=!transition_toggle;expected_epoch<=!expected_epoch;
            end
        end
    end
    // On the first fading frame reject every queued sample from the old image.
    // Epoch travels with PCM through the same mailbox, never on a separate bus.
    wire epoch_matches=ENABLE_AV_SYNC==0 || queued_audio_epoch==expected_epoch;
    assign audio_rd_data=epoch_matches ? queued_audio_data : 32'd0;
    assign audio_rd_tag=epoch_matches ? queued_audio_tag : 3'b100;
    wire        audio_empty;
    wire        audio_full;
    wire        audio_overflow;
    wire        audio_pop;

    // ---------------------------------------------------------------- OSD
    generate if(HDMI_SUBTITLE_EN != 0) begin : g_subtitles
    wire [23:0] progress_bcd;wire progress_playing;
    wire [9:0] caption_addr;wire [15:0] caption_bits;
    wire [6:0] caption_length;wire caption_active,caption_changed;
    text_glyph_cache #(.WAIT_IMAGE(1)) u_text_cache(
       .src_clk(audio_clk),.pix_clk(pixel_clk),.rst_n(video_reset_n),
       .write_enable(text_glyph_we),.write_addr(text_glyph_addr),.write_data(text_glyph_data),
       .publish(display_info_valid),.discard(text_abort),
       .commit(text_commit),.src_length(text_length),.src_has_text(text_has_text),.src_ready(text_cache_ready),
       .frame_end(VGA_X==799 && VGA_Y==524),.read_addr(caption_addr),.read_data(caption_bits),
       .text_length(caption_length),.has_text(caption_active),.changed(caption_changed));
    audio_progress #(.FS(AUDIO_FS),.HOLD_IDLE(ENABLE_AV_SYNC)) u_progress(
      .clk(pixel_clk),.rst_n(video_reset_n),.consume(audio_pop && !audio_empty),
      .tag(audio_rd_tag),.restart(transition_start),.playing(progress_playing),.time_bcd(progress_bcd));
    subtitle_overlay #(.ENABLE_TEXT(1)) u_overlay(
      .clk(pixel_clk),.rst_n(video_reset_n),.de(VGA_DE),.frame_sync(frame_sync),
      .x(VGA_X),.y(VGA_Y),.rgb_in(FADE_D),.rgb_out(OSD_D),
      .sub_enable(sw_sub),.time_enable(sw_ts),
      .left_pressed(KEY_ACTIVE_LOW ? !key_stable[5]:key_stable[5]),
      .right_pressed(KEY_ACTIVE_LOW ? !key_stable[6]:key_stable[6]),
      .info_valid(display_info_valid),.info(display_info),
       .audio_playing(progress_playing),.audio_bcd(progress_bcd),
       .text_active(caption_active),.text_changed(caption_changed),.caption_length(caption_length),
       .caption_bits(caption_bits),.caption_addr(caption_addr));
    end else begin : g_no_osd
      assign OSD_D=FADE_D;
       assign text_cache_ready=1'b1;
    end endgenerate

    // ------------------------------------------- right-side parameter banner
    wire [23:0] PARAM_D;
    param_osd u_param_osd (
        .clk      (pixel_clk),
        .reset    (~video_reset_n),
        .de       (VGA_DE),
        .x        (VGA_X),
        .y        (VGA_Y),
        .rgb_in   (OSD_D),
        .rgb_out  (PARAM_D),
        .sel      (param_sel),
        .val      (param_val),
        .visible  (banner_timer != 27'd0)
    );

    // -------------------------------------------------------------- audio

    // Assert audio reset with video; release it in the source clock domain.
    wire audio_reset_request=~video_reset_n;
    reg [1:0] audio_reset_release;
    always @(posedge audio_clk or posedge audio_reset_request)begin
        if(audio_reset_request)audio_reset_release<=0;
        else audio_reset_release<={audio_reset_release[0],1'b1};
    end
    audio_fifo #(.AWIDTH(5),.DATA_WIDTH(36)) u_audio_fifo (
        .wr_clk   (audio_clk),
        .wr_rst   (~audio_reset_release[1]),
        .wr_en    (audio_valid && HDMI_AUDIO_EN != 0),
        .wr_data  ({ENABLE_AV_SYNC!=0 ? audio_epoch:1'b0,audio_tag,audio_sample}),
        .full     (audio_full),
        .overflow (audio_overflow),
        .rd_clk   (pixel_clk),
        .rd_rst   (~video_reset_n),
        .rd_en    (audio_pop),
        .rd_data  ({queued_audio_epoch,queued_audio_tag,queued_audio_data}),
        .empty    (audio_empty)
    );

    assign audio_ready = !audio_full;

    // Spectrum observes already-crossed PCM; no backpressure into audio/video.
    generate if(ENABLE_SPECTRUM != 0)begin:g_spectrum
        localparam DB_BITS=SPECTRUM_DB_CYCLES>1?$clog2(SPECTRUM_DB_CYCLES):1;
        reg spectrum_meta,spectrum_sync,spectrum_stable,spectrum_previous;
        reg [DB_BITS-1:0] spectrum_count;
        reg selected;
        reg [1:0] playing_sync;
        always @(posedge pixel_clk or negedge video_reset_n)begin
            if(!video_reset_n)begin
                spectrum_meta<=1;spectrum_sync<=1;spectrum_stable<=1;
                spectrum_previous<=1;spectrum_count<=0;selected<=0;playing_sync<=0;
            end else begin
                spectrum_meta<=spectrum_key_n;spectrum_sync<=spectrum_meta;
                spectrum_previous<=spectrum_stable;
                playing_sync<={playing_sync[0],audio_playing};
                if(spectrum_sync==spectrum_stable)spectrum_count<=0;
                else if(spectrum_count==SPECTRUM_DB_CYCLES-1)begin
                    spectrum_stable<=spectrum_sync;spectrum_count<=0;
                end else spectrum_count<=spectrum_count+1'b1;
                if(spectrum_previous && !spectrum_stable)selected<=!selected;
            end
        end
        wire running=selected && playing_sync[1];
        wire [111:0] levels;
        audio_spectrum u_analyzer(
            .clk(pixel_clk),.rst_n(video_reset_n),.enable(running),
            .sample(audio_rd_data),.sample_valid(audio_pop && !audio_empty),.volume(volume),
            .levels(levels),.update());
        spectrum_overlay u_overlay(
            .clk(pixel_clk),.rst_n(video_reset_n),.enable(running),.frame_sync(frame_sync),
            .de(VGA_DE),.x(VGA_X),.y(VGA_Y),.rgb_in(PARAM_D),.levels(levels),.rgb_out(SPECTRUM_D));
    end else begin:g_no_spectrum
        assign SPECTRUM_D=PARAM_D;
    end endgenerate

    // ------------------------------------------------------- fixed logo/watermark
    // Drawn last (after fade, subtitles, parameter bar and spectrum) so it stays
    // at full brightness during a cross-fade.
    wire [23:0] LOGO_D;
    generate if (HDMI_LOGO_EN != 0) begin : g_logo
        logo_overlay #(.LOGO_X(568), .LOGO_Y(8)) u_logo (
            .clk     (pixel_clk),
            .de      (VGA_DE),
            .x       (VGA_X),
            .y       (VGA_Y),
            .rgb_in  (SPECTRUM_D),
            .rgb_out (LOGO_D)
        );
    end else begin : g_no_logo
        assign LOGO_D = SPECTRUM_D;
    end endgenerate

    // ------------------------------------------------------------- HDMI TX
    hdmi_tx #(
        .FAMILY  ("EG4"),
        .AUDIO_EN(HDMI_AUDIO_EN),
        .DVI_MODE(DVI_MODE),
        .AUDIO_FS(AUDIO_FS)
    ) u3_hdmi_tx (
        .PXLCLK_I    (pixel_clk),
        .PXLCLK_5X_I (pixel_clk_5x),
        .RST_N       (video_reset_n),

        .H_COUNT     (VGA_X),
        .V_COUNT     (VGA_Y),
        .VGA_HS      (VGA_HS),
        .VGA_VS      (VGA_VS),
        .VGA_RGB     (LOGO_D),

        .AUDIO_I      (audio_rd_data),
        .AUDIO_VOL    (volume),
        .AUDIO_EMPTY  (audio_empty),
        .AUDIO_OVF    (audio_overflow),
        .AUDIO_POP    (audio_pop),
        .AUDIO_STATUS (audio_status),
        .AUDIO_PKT    (audio_pkt),

        .HDMI_CLK_P (HDMI_CLK_P),
        .HDMI_D2_P  (HDMI_D2_P),
        .HDMI_D1_P  (HDMI_D1_P),
        .HDMI_D0_P  (HDMI_D0_P)
    );

    // keep optional interface signals alive in the netlist
    wire unused = |{frame_ready, pix_underflow};

endmodule
