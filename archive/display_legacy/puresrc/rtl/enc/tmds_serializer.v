// -----------------------------------------------------------------------------
// 10:1 TMDS serializer for Anlogic EG4.
//
// The PLL provides a 5x pixel clock.  A 10-bit word is shifted two bits per 5x
// cycle and driven through EG_LOGIC_ODDR (DDR), giving the 10x TMDS bit rate.
// Bit 0 of each TMDS word is transmitted first (HDMI 1.4a section 5.4.1).
// -----------------------------------------------------------------------------
module tmds_serializer (
    input  wire clk_pixel,
    input  wire clk_pixel_x5,
    input  wire reset,
    input  wire [9:0] tmds0,
    input  wire [9:0] tmds1,
    input  wire [9:0] tmds2,
    output wire HDMI_CLK_P,
    output wire HDMI_D0_P,
    output wire HDMI_D1_P,
    output wire HDMI_D2_P
);

    // ------------------------------------------------------------------
    // Load pulse in the 5x clock domain.  PCLK and PCLK_5X come from the
    // same PLL with an exact 5:1 ratio; the two synchronizer stages give a
    // fixed phase so each word occupies exactly five 5x periods.
    // ------------------------------------------------------------------
    reg [3:0] pclk_sync;
    always @(posedge clk_pixel_x5 or posedge reset)
        if (reset) pclk_sync <= 4'b0000;
        else       pclk_sync <= {pclk_sync[2:0], clk_pixel};

    // one load pulse per pixel period, ~3 5x cycles after the pixel rising edge
    wire load = pclk_sync[2] & ~pclk_sync[3];

    reg [9:0] sh0, sh1, sh2, shc;

    // Drive the ODDR cells from the combinational next state so d0/d1 are
    // stable before the 5x rising edge that captures them.
    wire [9:0] n0  = load ? tmds0 : {2'b00, sh0[9:2]};
    wire [9:0] n1  = load ? tmds1 : {2'b00, sh1[9:2]};
    wire [9:0] n2  = load ? tmds2 : {2'b00, sh2[9:2]};
    wire [9:0] nc  = load ? 10'b0000011111 : {2'b00, shc[9:2]};

    always @(posedge clk_pixel_x5 or posedge reset) begin
        if (reset) begin
            sh0 <= 10'd0;
            sh1 <= 10'd0;
            sh2 <= 10'd0;
            shc <= 10'b0000011111;
        end else begin
            sh0 <= n0;
            sh1 <= n1;
            sh2 <= n2;
            shc <= nc;
        end
    end

    // d0 goes out on the rising edge, d1 on the falling edge.
    eg_oddr u_oddr_clk (.q(HDMI_CLK_P), .clk(clk_pixel_x5),
                        .d0(nc[0]), .d1(nc[1]), .rst(reset));
    eg_oddr u_oddr_d0  (.q(HDMI_D0_P),  .clk(clk_pixel_x5),
                        .d0(n0[0]), .d1(n0[1]), .rst(reset));
    eg_oddr u_oddr_d1  (.q(HDMI_D1_P),  .clk(clk_pixel_x5),
                        .d0(n1[0]), .d1(n1[1]), .rst(reset));
    eg_oddr u_oddr_d2  (.q(HDMI_D2_P),  .clk(clk_pixel_x5),
                        .d0(n2[0]), .d1(n2[1]), .rst(reset));

endmodule
