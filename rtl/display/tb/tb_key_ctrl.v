// Key-control testbench for hdmi_tx_display.
// Uses behavioural stubs for the PLL/read_RAM/OSD/FIFO/HDMI-TX so that the
// debounce and control registers can be exercised directly.
//   key_in[0..1,5,6] momentary, pressed = 0
//   key_in[2..4]     latching switches, on = 0
`timescale 1ns/1ps

module tb_key_ctrl;

    reg        clk = 1'b0;
    reg        rst_n = 1'b0;
    reg  [6:0] key_in = 7'h7F;
    reg  [3:0] key_img = 4'hF;

    always #10 clk = ~clk;   // 50 MHz (stub PLL passes sys_clk to the pixel domain)

    wire        pix_clk, pix_req, frame_sync;
    wire [1:0]  audio_status;
    wire        audio_pkt;

    hdmi_tx_display #(
        .AUDIO_FS(48000), .HDMI_AUDIO_EN(1), .HDMI_SUBTITLE_EN(1),
        .DVI_MODE(0), .TS_X(8), .TS_Y(448), .SUB_X_INIT(200),
        .KEY_ACTIVE_LOW(1), .SWITCH_ON_LOW(1), .BANNER_CYCLES(1_000_000)
    ) u_dut (
        .sys_clk(clk), .sys_rst_n(rst_n),
        .pix_rgb(24'd0), .pix_valid(1'b0), .frame_ready(1'b1), .pix_underflow(1'b0),
        .pix_clk(pix_clk), .pix_req(pix_req), .frame_sync(frame_sync),
        .audio_clk(clk), .audio_sample(32'd0), .audio_valid(1'b0),
        .audio_ready(), .audio_status(audio_status), .audio_pkt(audio_pkt),
        .key_in(key_in),
        .key_img(key_img),
        .osd_slot(1'b0), .osd_char_idx(4'd0), .osd_char_code(16'd0),
        .osd_char_we(1'b0), .osd_y(10'd420), .osd_fg(24'hFFFFFF),
        .HDMI_CLK_P(), .HDMI_D2_P(), .HDMI_D1_P(), .HDMI_D0_P()
    );

    // press/release both longer than the ~5.2 ms debounce at 50 MHz
    task press;
        input integer b;
        begin
            key_in[b] = 1'b0;
            #6_000_000;
            key_in[b] = 1'b1;
            #6_000_000;
        end
    endtask

    // set a latching switch and wait for the debounce
    task sw_set;
        input integer b;
        input integer v;
        begin
            key_in[b] = v[0];
            #6_000_000;
        end
    endtask

    task show;
        input [255:0] tag;
        begin
            $display("%0t %0s: lvl=%0d vol=%0d mute_sw=%b sub_sw=%b ts_sw=%b x=%0d osd_en=%b",
                     $time, tag, u_dut.vol_level, u_dut.volume, u_dut.sw_mute,
                     u_dut.sw_sub, u_dut.sw_ts, u_dut.sub_x, u_dut.osd_en);
        end
    endtask

    // press an image-adjustment key (key_img[0]=BRT+, [1]=BRT-, [2]=CON+, [3]=CON-)
    task press_img;
        input integer b;
        begin
            key_img[b] = 1'b0;
            #6_000_000;
            key_img[b] = 1'b1;
            #6_000_000;
        end
    endtask

    task show_img;
        input [255:0] tag;
        begin
            $display("%0t %0s: bri=%0d con=%0d sel=%0d val=%0d timer=%0d",
                     $time, tag, u_dut.bri, u_dut.con, u_dut.param_sel,
                     u_dut.param_val, u_dut.banner_timer);
        end
    endtask

    integer i;
    initial begin
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        #1000;
        show("initial      ");

        sw_set(3, 0);  show("SUB switch on ");
        sw_set(4, 0);  show("TS switch on  ");
        sw_set(2, 0);  show("MUTE on       ");
        sw_set(2, 1);  show("MUTE off      ");

        press(1);  show("vol-          ");   // 4 -> 3
        press(1);  show("vol-          ");   // 3 -> 2
        press(0);  show("vol+          ");   // 2 -> 3
        press(0);  show("vol+          ");   // 3 -> 4
        press(0);  show("vol+ at max   ");   // clamp

        press(5);  show("sub left      ");   // 200 -> 184
        press(5);  show("sub left      ");   // 184 -> 168
        press(6);  show("sub right     ");   // 168 -> 184
        for (i = 0; i < 13; i = i + 1) press(5);
        show("sub to min   ");
        for (i = 0; i < 27; i = i + 1) press(6);
        show("sub to max   ");

        sw_set(3, 1);  show("SUB switch off");
        sw_set(4, 1);  show("TS switch off ");

        // hold vol- for four debounce periods: exactly one step (4 -> 3)
        key_in[1] = 1'b0;
        #25_000_000;
        key_in[1] = 1'b1;
        #6_000_000;
        show("hold vol-     ");

        // image adjustment keys + parameter banner
        press_img(0);  show_img("BRT+          ");   // 10 -> 11
        press_img(2);  show_img("CON+          ");   // 10 -> 11, banner switches
        #15_000_000;
        show_img("banner expired");

        $display("DONE");
        $finish;
    end

endmodule
