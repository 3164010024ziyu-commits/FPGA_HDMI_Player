// Elaboration-only stubs for modules implemented as IP / VHDL / other files.
`timescale 1ns/1ps

module clk_wize (input refclk, input reset, output extlock, output clk0_out, output clk1_out);
    assign extlock = !reset;
    assign clk0_out = refclk;
    assign clk1_out = refclk;
endmodule

module read_RAM (
    input clk25M, input reset_n,
    input [23:0] pix_rgb, input pix_valid,
    output pix_req, output frame_sync,
    output HDMI_HSYNC, output HDMI_VSYNC,
    output [9:0] HDMI_X, output [9:0] HDMI_Y,
    output HDMI_EN, output [23:0] HDMI_D
);
    assign pix_req = 0; assign frame_sync = 0;
    assign HDMI_HSYNC = 0; assign HDMI_VSYNC = 0;
    assign HDMI_X = 0; assign HDMI_Y = 0;
    assign HDMI_EN = 0; assign HDMI_D = 0;
endmodule

module osd_overlay #(parameter OSD_EN = 1, TS_X = 8, TS_Y = 448) (
    input clk, input reset, input de,
    input [9:0] x, input [9:0] y,
    input [23:0] rgb_in, output reg [23:0] rgb_out,
    input [1:0] osd_en, input osd_slot,
    input [3:0] char_idx, input [15:0] char_code, input char_we,
    input [9:0] sub_x, input [9:0] sub_y, input [23:0] fg
);
    always @* rgb_out = rgb_in;
endmodule

module audio_fifo #(parameter AWIDTH = 4) (
    input wr_clk, input wr_rst, input wr_en, input [31:0] wr_data,
    output full, output overflow,
    input rd_clk, input rd_rst, input rd_en,
    output [31:0] rd_data, output empty
);
    assign full = 1'b0; assign overflow = 1'b0;
    assign rd_data = 32'd0; assign empty = 1'b1;
endmodule

module hdmi_tx #(parameter FAMILY = "EG4", AUDIO_EN = 1, DVI_MODE = 0, AUDIO_FS = 48000) (
    input PXLCLK_I, input PXLCLK_5X_I, input RST_N,
    input [9:0] H_COUNT, input [9:0] V_COUNT,
    input VGA_HS, input VGA_VS, input [23:0] VGA_RGB,
    input [31:0] AUDIO_I, input [7:0] AUDIO_VOL,
    input AUDIO_EMPTY, input AUDIO_OVF,
    output AUDIO_POP, output [1:0] AUDIO_STATUS, output AUDIO_PKT,
    output HDMI_CLK_P, output HDMI_D0_P, output HDMI_D1_P, output HDMI_D2_P
);
    assign AUDIO_POP = 0; assign AUDIO_STATUS = 0; assign AUDIO_PKT = 0;
    assign HDMI_CLK_P = 0; assign HDMI_D0_P = 0; assign HDMI_D1_P = 0; assign HDMI_D2_P = 0;
endmodule
