// 16x16 GB2312 font ROM built from 16 x 32Kb block RAMs (16 x 2048 x 16).
// Bank files are produced by tools/gen_font_rom.ps1 (font_bank_XX.dat).
// Read latency: two pixel clocks (BRAM address sampled on the next edge).
module font_16x16_rom (
    input  wire        clk,
    input  wire [11:0] idx,
    input  wire [3:0]  row,
    output wire [15:0] bits
);

    wire [14:0] waddr = {idx, 4'b0} + {11'd0, row};
    reg  [3:0]  bank_r;
    always @(posedge clk) begin
        bank_r <= waddr[14:11];
    end

    wire [15:0] d00;
    wire [15:0] d01;
    wire [15:0] d02;
    wire [15:0] d03;
    wire [15:0] d04;
    wire [15:0] d05;
    wire [15:0] d06;
    wire [15:0] d07;
    wire [15:0] d08;
    wire [15:0] d09;
    wire [15:0] d10;
    wire [15:0] d11;
    wire [15:0] d12;
    wire [15:0] d13;
    wire [15:0] d14;
    wire [15:0] d15;

    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(16), .DATA_WIDTH_B(16),
        .ADDR_WIDTH_A(11), .ADDR_WIDTH_B(11),
        .DATA_DEPTH_A(2048), .DATA_DEPTH_B(2048),
        .BYTE_ENABLE(0), .BYTE_A(1), .BYTE_B(1),
        .MODE("SP"),
        .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"), .WRITEMODE_B("NORMAL"),
        .RESETMODE("SYNC"), .DEBUGGABLE("NO"), .PACKABLE("NO"),
        .FORCE_KEEP("OFF"),
        .INIT_FILE("D:/FPGA_HDMI_Player/FPGA_HDMI_Player/rtl/display/src/font_bank_00.dath"),
        .FILL_ALL("NONE"), .IMPLEMENT("32K")
    ) u_bank00 (
        .doa(d00), .dob(), .dia(16'd0), .dib(16'd0),
        .cea(1'b1), .ocea(1'b1), .clka(clk), .wea(1'b0), .rsta(1'b0),
        .ceb(1'b0), .oceb(1'b0), .clkb(clk), .web(1'b0), .rstb(1'b0),
        .bea(1'b0), .beb(1'b0),
        .addra(waddr[10:0]), .addrb(11'd0)
    );

    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(16), .DATA_WIDTH_B(16),
        .ADDR_WIDTH_A(11), .ADDR_WIDTH_B(11),
        .DATA_DEPTH_A(2048), .DATA_DEPTH_B(2048),
        .BYTE_ENABLE(0), .BYTE_A(1), .BYTE_B(1),
        .MODE("SP"),
        .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"), .WRITEMODE_B("NORMAL"),
        .RESETMODE("SYNC"), .DEBUGGABLE("NO"), .PACKABLE("NO"),
        .FORCE_KEEP("OFF"),
        .INIT_FILE("D:/FPGA_HDMI_Player/FPGA_HDMI_Player/rtl/display/src/font_bank_01.dath"),
        .FILL_ALL("NONE"), .IMPLEMENT("32K")
    ) u_bank01 (
        .doa(d01), .dob(), .dia(16'd0), .dib(16'd0),
        .cea(1'b1), .ocea(1'b1), .clka(clk), .wea(1'b0), .rsta(1'b0),
        .ceb(1'b0), .oceb(1'b0), .clkb(clk), .web(1'b0), .rstb(1'b0),
        .bea(1'b0), .beb(1'b0),
        .addra(waddr[10:0]), .addrb(11'd0)
    );

    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(16), .DATA_WIDTH_B(16),
        .ADDR_WIDTH_A(11), .ADDR_WIDTH_B(11),
        .DATA_DEPTH_A(2048), .DATA_DEPTH_B(2048),
        .BYTE_ENABLE(0), .BYTE_A(1), .BYTE_B(1),
        .MODE("SP"),
        .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"), .WRITEMODE_B("NORMAL"),
        .RESETMODE("SYNC"), .DEBUGGABLE("NO"), .PACKABLE("NO"),
        .FORCE_KEEP("OFF"),
        .INIT_FILE("D:/FPGA_HDMI_Player/FPGA_HDMI_Player/rtl/display/src/font_bank_02.dath"),
        .FILL_ALL("NONE"), .IMPLEMENT("32K")
    ) u_bank02 (
        .doa(d02), .dob(), .dia(16'd0), .dib(16'd0),
        .cea(1'b1), .ocea(1'b1), .clka(clk), .wea(1'b0), .rsta(1'b0),
        .ceb(1'b0), .oceb(1'b0), .clkb(clk), .web(1'b0), .rstb(1'b0),
        .bea(1'b0), .beb(1'b0),
        .addra(waddr[10:0]), .addrb(11'd0)
    );

    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(16), .DATA_WIDTH_B(16),
        .ADDR_WIDTH_A(11), .ADDR_WIDTH_B(11),
        .DATA_DEPTH_A(2048), .DATA_DEPTH_B(2048),
        .BYTE_ENABLE(0), .BYTE_A(1), .BYTE_B(1),
        .MODE("SP"),
        .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"), .WRITEMODE_B("NORMAL"),
        .RESETMODE("SYNC"), .DEBUGGABLE("NO"), .PACKABLE("NO"),
        .FORCE_KEEP("OFF"),
        .INIT_FILE("D:/FPGA_HDMI_Player/FPGA_HDMI_Player/rtl/display/src/font_bank_03.dath"),
        .FILL_ALL("NONE"), .IMPLEMENT("32K")
    ) u_bank03 (
        .doa(d03), .dob(), .dia(16'd0), .dib(16'd0),
        .cea(1'b1), .ocea(1'b1), .clka(clk), .wea(1'b0), .rsta(1'b0),
        .ceb(1'b0), .oceb(1'b0), .clkb(clk), .web(1'b0), .rstb(1'b0),
        .bea(1'b0), .beb(1'b0),
        .addra(waddr[10:0]), .addrb(11'd0)
    );

    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(16), .DATA_WIDTH_B(16),
        .ADDR_WIDTH_A(11), .ADDR_WIDTH_B(11),
        .DATA_DEPTH_A(2048), .DATA_DEPTH_B(2048),
        .BYTE_ENABLE(0), .BYTE_A(1), .BYTE_B(1),
        .MODE("SP"),
        .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"), .WRITEMODE_B("NORMAL"),
        .RESETMODE("SYNC"), .DEBUGGABLE("NO"), .PACKABLE("NO"),
        .FORCE_KEEP("OFF"),
        .INIT_FILE("D:/FPGA_HDMI_Player/FPGA_HDMI_Player/rtl/display/src/font_bank_04.dath"),
        .FILL_ALL("NONE"), .IMPLEMENT("32K")
    ) u_bank04 (
        .doa(d04), .dob(), .dia(16'd0), .dib(16'd0),
        .cea(1'b1), .ocea(1'b1), .clka(clk), .wea(1'b0), .rsta(1'b0),
        .ceb(1'b0), .oceb(1'b0), .clkb(clk), .web(1'b0), .rstb(1'b0),
        .bea(1'b0), .beb(1'b0),
        .addra(waddr[10:0]), .addrb(11'd0)
    );

    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(16), .DATA_WIDTH_B(16),
        .ADDR_WIDTH_A(11), .ADDR_WIDTH_B(11),
        .DATA_DEPTH_A(2048), .DATA_DEPTH_B(2048),
        .BYTE_ENABLE(0), .BYTE_A(1), .BYTE_B(1),
        .MODE("SP"),
        .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"), .WRITEMODE_B("NORMAL"),
        .RESETMODE("SYNC"), .DEBUGGABLE("NO"), .PACKABLE("NO"),
        .FORCE_KEEP("OFF"),
        .INIT_FILE("D:/FPGA_HDMI_Player/FPGA_HDMI_Player/rtl/display/src/font_bank_05.dath"),
        .FILL_ALL("NONE"), .IMPLEMENT("32K")
    ) u_bank05 (
        .doa(d05), .dob(), .dia(16'd0), .dib(16'd0),
        .cea(1'b1), .ocea(1'b1), .clka(clk), .wea(1'b0), .rsta(1'b0),
        .ceb(1'b0), .oceb(1'b0), .clkb(clk), .web(1'b0), .rstb(1'b0),
        .bea(1'b0), .beb(1'b0),
        .addra(waddr[10:0]), .addrb(11'd0)
    );

    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(16), .DATA_WIDTH_B(16),
        .ADDR_WIDTH_A(11), .ADDR_WIDTH_B(11),
        .DATA_DEPTH_A(2048), .DATA_DEPTH_B(2048),
        .BYTE_ENABLE(0), .BYTE_A(1), .BYTE_B(1),
        .MODE("SP"),
        .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"), .WRITEMODE_B("NORMAL"),
        .RESETMODE("SYNC"), .DEBUGGABLE("NO"), .PACKABLE("NO"),
        .FORCE_KEEP("OFF"),
        .INIT_FILE("D:/FPGA_HDMI_Player/FPGA_HDMI_Player/rtl/display/src/font_bank_06.dath"),
        .FILL_ALL("NONE"), .IMPLEMENT("32K")
    ) u_bank06 (
        .doa(d06), .dob(), .dia(16'd0), .dib(16'd0),
        .cea(1'b1), .ocea(1'b1), .clka(clk), .wea(1'b0), .rsta(1'b0),
        .ceb(1'b0), .oceb(1'b0), .clkb(clk), .web(1'b0), .rstb(1'b0),
        .bea(1'b0), .beb(1'b0),
        .addra(waddr[10:0]), .addrb(11'd0)
    );

    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(16), .DATA_WIDTH_B(16),
        .ADDR_WIDTH_A(11), .ADDR_WIDTH_B(11),
        .DATA_DEPTH_A(2048), .DATA_DEPTH_B(2048),
        .BYTE_ENABLE(0), .BYTE_A(1), .BYTE_B(1),
        .MODE("SP"),
        .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"), .WRITEMODE_B("NORMAL"),
        .RESETMODE("SYNC"), .DEBUGGABLE("NO"), .PACKABLE("NO"),
        .FORCE_KEEP("OFF"),
        .INIT_FILE("D:/FPGA_HDMI_Player/FPGA_HDMI_Player/rtl/display/src/font_bank_07.dath"),
        .FILL_ALL("NONE"), .IMPLEMENT("32K")
    ) u_bank07 (
        .doa(d07), .dob(), .dia(16'd0), .dib(16'd0),
        .cea(1'b1), .ocea(1'b1), .clka(clk), .wea(1'b0), .rsta(1'b0),
        .ceb(1'b0), .oceb(1'b0), .clkb(clk), .web(1'b0), .rstb(1'b0),
        .bea(1'b0), .beb(1'b0),
        .addra(waddr[10:0]), .addrb(11'd0)
    );

    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(16), .DATA_WIDTH_B(16),
        .ADDR_WIDTH_A(11), .ADDR_WIDTH_B(11),
        .DATA_DEPTH_A(2048), .DATA_DEPTH_B(2048),
        .BYTE_ENABLE(0), .BYTE_A(1), .BYTE_B(1),
        .MODE("SP"),
        .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"), .WRITEMODE_B("NORMAL"),
        .RESETMODE("SYNC"), .DEBUGGABLE("NO"), .PACKABLE("NO"),
        .FORCE_KEEP("OFF"),
        .INIT_FILE("D:/FPGA_HDMI_Player/FPGA_HDMI_Player/rtl/display/src/font_bank_08.dath"),
        .FILL_ALL("NONE"), .IMPLEMENT("32K")
    ) u_bank08 (
        .doa(d08), .dob(), .dia(16'd0), .dib(16'd0),
        .cea(1'b1), .ocea(1'b1), .clka(clk), .wea(1'b0), .rsta(1'b0),
        .ceb(1'b0), .oceb(1'b0), .clkb(clk), .web(1'b0), .rstb(1'b0),
        .bea(1'b0), .beb(1'b0),
        .addra(waddr[10:0]), .addrb(11'd0)
    );

    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(16), .DATA_WIDTH_B(16),
        .ADDR_WIDTH_A(11), .ADDR_WIDTH_B(11),
        .DATA_DEPTH_A(2048), .DATA_DEPTH_B(2048),
        .BYTE_ENABLE(0), .BYTE_A(1), .BYTE_B(1),
        .MODE("SP"),
        .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"), .WRITEMODE_B("NORMAL"),
        .RESETMODE("SYNC"), .DEBUGGABLE("NO"), .PACKABLE("NO"),
        .FORCE_KEEP("OFF"),
        .INIT_FILE("D:/FPGA_HDMI_Player/FPGA_HDMI_Player/rtl/display/src/font_bank_09.dath"),
        .FILL_ALL("NONE"), .IMPLEMENT("32K")
    ) u_bank09 (
        .doa(d09), .dob(), .dia(16'd0), .dib(16'd0),
        .cea(1'b1), .ocea(1'b1), .clka(clk), .wea(1'b0), .rsta(1'b0),
        .ceb(1'b0), .oceb(1'b0), .clkb(clk), .web(1'b0), .rstb(1'b0),
        .bea(1'b0), .beb(1'b0),
        .addra(waddr[10:0]), .addrb(11'd0)
    );

    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(16), .DATA_WIDTH_B(16),
        .ADDR_WIDTH_A(11), .ADDR_WIDTH_B(11),
        .DATA_DEPTH_A(2048), .DATA_DEPTH_B(2048),
        .BYTE_ENABLE(0), .BYTE_A(1), .BYTE_B(1),
        .MODE("SP"),
        .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"), .WRITEMODE_B("NORMAL"),
        .RESETMODE("SYNC"), .DEBUGGABLE("NO"), .PACKABLE("NO"),
        .FORCE_KEEP("OFF"),
        .INIT_FILE("D:/FPGA_HDMI_Player/FPGA_HDMI_Player/rtl/display/src/font_bank_10.dath"),
        .FILL_ALL("NONE"), .IMPLEMENT("32K")
    ) u_bank10 (
        .doa(d10), .dob(), .dia(16'd0), .dib(16'd0),
        .cea(1'b1), .ocea(1'b1), .clka(clk), .wea(1'b0), .rsta(1'b0),
        .ceb(1'b0), .oceb(1'b0), .clkb(clk), .web(1'b0), .rstb(1'b0),
        .bea(1'b0), .beb(1'b0),
        .addra(waddr[10:0]), .addrb(11'd0)
    );

    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(16), .DATA_WIDTH_B(16),
        .ADDR_WIDTH_A(11), .ADDR_WIDTH_B(11),
        .DATA_DEPTH_A(2048), .DATA_DEPTH_B(2048),
        .BYTE_ENABLE(0), .BYTE_A(1), .BYTE_B(1),
        .MODE("SP"),
        .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"), .WRITEMODE_B("NORMAL"),
        .RESETMODE("SYNC"), .DEBUGGABLE("NO"), .PACKABLE("NO"),
        .FORCE_KEEP("OFF"),
        .INIT_FILE("D:/FPGA_HDMI_Player/FPGA_HDMI_Player/rtl/display/src/font_bank_11.dath"),
        .FILL_ALL("NONE"), .IMPLEMENT("32K")
    ) u_bank11 (
        .doa(d11), .dob(), .dia(16'd0), .dib(16'd0),
        .cea(1'b1), .ocea(1'b1), .clka(clk), .wea(1'b0), .rsta(1'b0),
        .ceb(1'b0), .oceb(1'b0), .clkb(clk), .web(1'b0), .rstb(1'b0),
        .bea(1'b0), .beb(1'b0),
        .addra(waddr[10:0]), .addrb(11'd0)
    );

    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(16), .DATA_WIDTH_B(16),
        .ADDR_WIDTH_A(11), .ADDR_WIDTH_B(11),
        .DATA_DEPTH_A(2048), .DATA_DEPTH_B(2048),
        .BYTE_ENABLE(0), .BYTE_A(1), .BYTE_B(1),
        .MODE("SP"),
        .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"), .WRITEMODE_B("NORMAL"),
        .RESETMODE("SYNC"), .DEBUGGABLE("NO"), .PACKABLE("NO"),
        .FORCE_KEEP("OFF"),
        .INIT_FILE("D:/FPGA_HDMI_Player/FPGA_HDMI_Player/rtl/display/src/font_bank_12.dath"),
        .FILL_ALL("NONE"), .IMPLEMENT("32K")
    ) u_bank12 (
        .doa(d12), .dob(), .dia(16'd0), .dib(16'd0),
        .cea(1'b1), .ocea(1'b1), .clka(clk), .wea(1'b0), .rsta(1'b0),
        .ceb(1'b0), .oceb(1'b0), .clkb(clk), .web(1'b0), .rstb(1'b0),
        .bea(1'b0), .beb(1'b0),
        .addra(waddr[10:0]), .addrb(11'd0)
    );

    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(16), .DATA_WIDTH_B(16),
        .ADDR_WIDTH_A(11), .ADDR_WIDTH_B(11),
        .DATA_DEPTH_A(2048), .DATA_DEPTH_B(2048),
        .BYTE_ENABLE(0), .BYTE_A(1), .BYTE_B(1),
        .MODE("SP"),
        .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"), .WRITEMODE_B("NORMAL"),
        .RESETMODE("SYNC"), .DEBUGGABLE("NO"), .PACKABLE("NO"),
        .FORCE_KEEP("OFF"),
        .INIT_FILE("D:/FPGA_HDMI_Player/FPGA_HDMI_Player/rtl/display/src/font_bank_13.dath"),
        .FILL_ALL("NONE"), .IMPLEMENT("32K")
    ) u_bank13 (
        .doa(d13), .dob(), .dia(16'd0), .dib(16'd0),
        .cea(1'b1), .ocea(1'b1), .clka(clk), .wea(1'b0), .rsta(1'b0),
        .ceb(1'b0), .oceb(1'b0), .clkb(clk), .web(1'b0), .rstb(1'b0),
        .bea(1'b0), .beb(1'b0),
        .addra(waddr[10:0]), .addrb(11'd0)
    );

    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(16), .DATA_WIDTH_B(16),
        .ADDR_WIDTH_A(11), .ADDR_WIDTH_B(11),
        .DATA_DEPTH_A(2048), .DATA_DEPTH_B(2048),
        .BYTE_ENABLE(0), .BYTE_A(1), .BYTE_B(1),
        .MODE("SP"),
        .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"), .WRITEMODE_B("NORMAL"),
        .RESETMODE("SYNC"), .DEBUGGABLE("NO"), .PACKABLE("NO"),
        .FORCE_KEEP("OFF"),
        .INIT_FILE("D:/FPGA_HDMI_Player/FPGA_HDMI_Player/rtl/display/src/font_bank_14.dath"),
        .FILL_ALL("NONE"), .IMPLEMENT("32K")
    ) u_bank14 (
        .doa(d14), .dob(), .dia(16'd0), .dib(16'd0),
        .cea(1'b1), .ocea(1'b1), .clka(clk), .wea(1'b0), .rsta(1'b0),
        .ceb(1'b0), .oceb(1'b0), .clkb(clk), .web(1'b0), .rstb(1'b0),
        .bea(1'b0), .beb(1'b0),
        .addra(waddr[10:0]), .addrb(11'd0)
    );

    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(16), .DATA_WIDTH_B(16),
        .ADDR_WIDTH_A(11), .ADDR_WIDTH_B(11),
        .DATA_DEPTH_A(2048), .DATA_DEPTH_B(2048),
        .BYTE_ENABLE(0), .BYTE_A(1), .BYTE_B(1),
        .MODE("SP"),
        .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"), .WRITEMODE_B("NORMAL"),
        .RESETMODE("SYNC"), .DEBUGGABLE("NO"), .PACKABLE("NO"),
        .FORCE_KEEP("OFF"),
        .INIT_FILE("D:/FPGA_HDMI_Player/FPGA_HDMI_Player/rtl/display/src/font_bank_15.dath"),
        .FILL_ALL("NONE"), .IMPLEMENT("32K")
    ) u_bank15 (
        .doa(d15), .dob(), .dia(16'd0), .dib(16'd0),
        .cea(1'b1), .ocea(1'b1), .clka(clk), .wea(1'b0), .rsta(1'b0),
        .ceb(1'b0), .oceb(1'b0), .clkb(clk), .web(1'b0), .rstb(1'b0),
        .bea(1'b0), .beb(1'b0),
        .addra(waddr[10:0]), .addrb(11'd0)
    );

    reg [15:0] bits_r;
    always @* begin
        case (bank_r)
            4'd0: bits_r = d00;
            4'd1: bits_r = d01;
            4'd2: bits_r = d02;
            4'd3: bits_r = d03;
            4'd4: bits_r = d04;
            4'd5: bits_r = d05;
            4'd6: bits_r = d06;
            4'd7: bits_r = d07;
            4'd8: bits_r = d08;
            4'd9: bits_r = d09;
            4'd10: bits_r = d10;
            4'd11: bits_r = d11;
            4'd12: bits_r = d12;
            4'd13: bits_r = d13;
            4'd14: bits_r = d14;
            4'd15: bits_r = d15;
            default: bits_r = 16'd0;
        endcase
    end
    assign bits = bits_r;

endmodule
