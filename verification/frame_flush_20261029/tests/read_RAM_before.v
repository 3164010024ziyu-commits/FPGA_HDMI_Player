// -----------------------------------------------------------------------------
// 640x480p60 timing generator.
//   H: 640 active + 16 front porch + 96 sync + 48 back porch = 800
//   V: 480 active + 10 front porch +  2 sync + 33 back porch = 525
// -----------------------------------------------------------------------------
module read_RAM_before
(
	input        clk25M,     // 25 MHz pixel clock
	input        reset_n,

	input  [23:0] pix_rgb,
	input         pix_valid,

	output        pix_req,
	output        frame_sync,

	output        HDMI_EN,
	output        HDMI_HSYNC,
	output        HDMI_VSYNC,
	output [9:0]  HDMI_X,    //像素坐标
	output [9:0]  HDMI_Y,    //像素坐标
	output [23:0] HDMI_D
);

	localparam [9:0] H_ACTIVE     = 10'd640;
	localparam [9:0] H_TOTAL      = 10'd800;
	localparam [9:0] H_SYNC_START = 10'd656;
	localparam [9:0] H_SYNC_END   = 10'd752;
	localparam [9:0] V_ACTIVE     = 10'd480;
	localparam [9:0] V_TOTAL      = 10'd525;
	localparam [9:0] V_SYNC_START = 10'd490;
	localparam [9:0] V_SYNC_END   = 10'd492;
	localparam [9:0] FRAME_LINE   = 10'd480;

	reg [9:0] hcnt;
	reg [9:0] vcnt;
	reg       hs;
	reg       vs;
	reg       frame;

	wire dis_en = (hcnt < H_ACTIVE) && (vcnt < V_ACTIVE);

	assign HDMI_VSYNC = vs;    //场同步
	assign HDMI_HSYNC = hs;    //行同步
	assign HDMI_X     = hcnt;
	assign HDMI_Y     = vcnt;
	assign HDMI_EN    = dis_en;

	// Consume exactly one FIFO pixel for each active coordinate.
    // The FIFO adapter prefetches independently during blanking.
    assign pix_req = dis_en;
	assign frame_sync = frame;

	// pixel data, DE and coordinates come from the same clock edge
	assign HDMI_D = dis_en && pix_valid ? pix_rgb : 24'd0;

	always @(posedge clk25M or negedge reset_n) begin
		if (!reset_n)
			hcnt <= 10'd0;
		else if (hcnt < H_TOTAL - 10'd1)
			hcnt <= hcnt + 10'd1;
		else
			hcnt <= 10'd0;
	end

	always @(posedge clk25M or negedge reset_n) begin
		if (!reset_n)
			vcnt <= 10'd0;
		else if (hcnt == H_TOTAL - 10'd1) begin
			if (vcnt < V_TOTAL - 10'd1)
				vcnt <= vcnt + 10'd1;
			else
				vcnt <= 10'd0;
		end
	end

	always @(posedge clk25M or negedge reset_n) begin
		if (!reset_n)
			hs <= 1'b1;
		else
			hs <= !((hcnt >= H_SYNC_START) && (hcnt < H_SYNC_END));
	end

	// VSYNC and frame_sync are combinational from vcnt.
	always @* begin
		if (!reset_n) begin
			vs    = 1'b1;
			frame = 1'b0;
		end else begin
			vs    = !((vcnt >= V_SYNC_START) && (vcnt < V_SYNC_END));
			frame = (vcnt == FRAME_LINE);
		end
	end

endmodule
