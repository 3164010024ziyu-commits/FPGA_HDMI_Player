// Behavioural 16x16 font ROM for simulation, loaded from the real bank files.
// Latency: 2 clocks (address register + memory), matching font_16x16_rom.v.
`timescale 1ns/1ps

module font_16x16_rom (
    input  wire        clk,
    input  wire [11:0] idx,
    input  wire [3:0]  row,
    output wire [15:0] bits
);

    reg [15:0] mem [0:32767];
    reg [15:0] d;

    integer b;
    initial begin
        $readmemh("src/font_bank_00.dath", mem, 0,     2047);
        $readmemh("src/font_bank_01.dath", mem, 2048,  4095);
        $readmemh("src/font_bank_02.dath", mem, 4096,  6143);
        $readmemh("src/font_bank_03.dath", mem, 6144,  8191);
        $readmemh("src/font_bank_04.dath", mem, 8192, 10239);
        $readmemh("src/font_bank_05.dath", mem, 10240, 12287);
        $readmemh("src/font_bank_06.dath", mem, 12288, 14335);
        $readmemh("src/font_bank_07.dath", mem, 14336, 16383);
        $readmemh("src/font_bank_08.dath", mem, 16384, 18431);
        $readmemh("src/font_bank_09.dath", mem, 18432, 20479);
        $readmemh("src/font_bank_10.dath", mem, 20480, 22527);
        $readmemh("src/font_bank_11.dath", mem, 22528, 24575);
        $readmemh("src/font_bank_12.dath", mem, 24576, 26623);
        $readmemh("src/font_bank_13.dath", mem, 26624, 28671);
        $readmemh("src/font_bank_14.dath", mem, 28672, 30719);
        $readmemh("src/font_bank_15.dath", mem, 30720, 32767);
    end

    always @(posedge clk) begin
        d <= mem[{idx, 4'b0} + {11'd0, row}];
    end

    assign bits = d;

endmodule
