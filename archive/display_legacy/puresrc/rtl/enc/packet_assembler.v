// -----------------------------------------------------------------------------
// HDMI data island packet assembler.
//
// A data island packet occupies 32 TMDS clock periods.  Each of the four
// subpackets (56 data bits + 8 BCH parity bits) is transmitted two bits per
// clock on channels 1/2, while the 32-bit packet header (24 data + 8 BCH) is
// transmitted one bit per clock on channel 0.
//
// References: HDMI 1.4a sections 5.2.3.4 and figure 5-4/5-5.  ECC recurrence
// verified against hdl-util/hdmi (src/packet_assembler.sv, MIT OR Apache-2.0).
// -----------------------------------------------------------------------------
module hdmi_packet_assembler (
    input  wire        clk,
    input  wire        reset,
    input  wire        in_island,     // 1 during the 32-clock packet
    input  wire        slot_start,    // pulse at first clock of a packet
    input  wire [23:0] header,
    input  wire [55:0] sub0,
    input  wire [55:0] sub1,
    input  wire [55:0] sub2,
    input  wire [55:0] sub3,
    output reg  [8:0]  packet_data
);

    reg [4:0]  cnt;
    reg [7:0]  p0, p1, p2, p3, p4;

    function [7:0] next_ecc;
        input [7:0] ecc;
        input       bit_in;
        begin
            next_ecc = (ecc >> 1) ^ ((ecc[0] ^ bit_in) ? 8'h83 : 8'h00);
        end
    endfunction

    function [7:0] next_ecc2;
        input [7:0] ecc;
        input       b0;
        input       b1;
        begin
            next_ecc2 = next_ecc(next_ecc(ecc, b0), b1);
        end
    endfunction

    wire [63:0] bch0 = {p0, sub0};
    wire [63:0] bch1 = {p1, sub1};
    wire [63:0] bch2 = {p2, sub2};
    wire [63:0] bch3 = {p3, sub3};
    wire [31:0] bch4 = {p4, header};

    wire [5:0] idx_lo = {cnt, 1'b0};
    wire [5:0] idx_hi = {cnt, 1'b1};

    always @* begin
        packet_data[8] = bch3[idx_hi];
        packet_data[7] = bch2[idx_hi];
        packet_data[6] = bch1[idx_hi];
        packet_data[5] = bch0[idx_hi];
        packet_data[4] = bch3[idx_lo];
        packet_data[3] = bch2[idx_lo];
        packet_data[2] = bch1[idx_lo];
        packet_data[1] = bch0[idx_lo];
        packet_data[0] = bch4[cnt];
    end

    always @(posedge clk) begin
        if (reset)
            cnt <= 5'd0;
        else if (slot_start)
            cnt <= 5'd0;
        else if (in_island)
            cnt <= cnt + 5'd1;
    end

    always @(posedge clk) begin
        if (reset || !in_island) begin
            p0 <= 8'd0;
            p1 <= 8'd0;
            p2 <= 8'd0;
            p3 <= 8'd0;
            p4 <= 8'd0;
        end else if (cnt == 5'd31) begin
            // last clock of the packet: prepare for the next packet
            p0 <= 8'd0;
            p1 <= 8'd0;
            p2 <= 8'd0;
            p3 <= 8'd0;
            p4 <= 8'd0;
        end else if (cnt < 5'd28) begin
            p0 <= next_ecc2(p0, sub0[idx_lo], sub0[idx_hi]);
            p1 <= next_ecc2(p1, sub1[idx_lo], sub1[idx_hi]);
            p2 <= next_ecc2(p2, sub2[idx_lo], sub2[idx_hi]);
            p3 <= next_ecc2(p3, sub3[idx_lo], sub3[idx_hi]);
            if (cnt < 5'd24)
                p4 <= next_ecc(p4, header[cnt]);
        end
    end

endmodule
