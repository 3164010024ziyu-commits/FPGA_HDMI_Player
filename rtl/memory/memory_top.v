`include "../../include/global_def.v"

module memory_top #(
    parameter integer DISPLAY_WIDTH=640,
    parameter integer DISPLAY_HEIGHT=480,
    parameter integer DISPLAY_FIFO_ADDR_WIDTH=11
)(
    input wire SYS_CLK,
    
    input wire Reset_n,

    input wire pixel_valid,
    input wire [23:0] pixel_data,
    output wire pixel_ready,

    input wire frame_start,
    input wire [`ADDR_WIDTH-1:0] frame_base_addr,
    input wire [15:0] frame_width,
    input wire [15:0] frame_height,
    input wire frame_top_down,
    input wire frame_end,

    input wire frame_abort,
    output wire frame_write_done_sync,
    output wire frame_write_ready,
    output wire frame_error,

    input wire display_clk,
    input wire display_reset_n,
    input wire display_frame_sync,
    input wire display_pixel_req,
    output wire [23:0] display_pixel_rgb,
    output wire display_pixel_valid,
    output wire display_frame_ready,
    output wire display_underflow,

    output wire [2:0] debug_error_flags, // {refresh, read timeout, FIFO underflow}
    output wire LED
);

localparam ADDR_WIDTH = 4;

wire            lock,local_clk,Clk,Clk_sft,Rst;

// Keep the PLL running. External reset or loss of lock discards the memory task.
wire reset_request = !Reset_n || !lock;
reg [1:0] sys_reset_release;
reg [1:0] mem_reset_release;
always @(posedge SYS_CLK or posedge reset_request) begin
    if(reset_request) sys_reset_release <= 2'b00;
    else sys_reset_release <= {sys_reset_release[0],1'b1};
end
always @(posedge Clk or posedge reset_request) begin
    if(reset_request) mem_reset_release <= 2'b00;
    else mem_reset_release <= {mem_reset_release[0],1'b1};
end
wire sys_reset_n = sys_reset_release[1];
wire mem_reset_n = mem_reset_release[1];
reg [1:0] init_done_sync;

wire fifo_empty;
wire [`DATA_WIDTH-1:0]fifo_rd_data;
wire fifo_rd_en;
wire fifo_rd_valid;

wire [`DATA_WIDTH-1:0]fifo_wr_data;
assign fifo_wr_data = {8'b0,pixel_data};

// Physical interface to the SDRAM packaged with EG4S20.
wire SDRAM_CLK;
wire SDR_RAS;
wire SDR_CAS;
wire SDR_WE;
wire [`BA_WIDTH-1:0] SDR_BA;
wire [`ROW_WIDTH-1:0] SDR_ADDR;
wire [`DM_WIDTH-1:0] SDR_DM;
wire [`DATA_WIDTH-1:0] SDR_DQ;
wire Sdr_busy;
wire refresh_pending;
wire refresh_error;
wire app_refresh_req;
wire manual_refresh_req = 1'b0;

wire 		Sdr_init_done,Sdr_init_ref_vld;

wire 					App_wr_en;
wire [`ADDR_WIDTH-1:0]	App_wr_addr;  	
wire [`DM_WIDTH-1:0]	App_wr_dm;
wire [`DATA_WIDTH-1:0]	App_wr_din;//synthesis keep

wire 					App_rd_en;
wire [`ADDR_WIDTH-1:0]	App_rd_addr;
wire 					Sdr_rd_en;
wire [`DATA_WIDTH-1:0]	Sdr_rd_dout;

wire		Check_ok;//synthesis keep

// Initialization status only; data readback is not checked here.
// Readiness is in SYS_CLK; a reset domain that has not resumed cannot be ready.
always @(posedge SYS_CLK or negedge sys_reset_n) begin
    if(!sys_reset_n) init_done_sync <= 2'b00;
    else init_done_sync <= {init_done_sync[0],mem_reset_n && Sdr_init_done};
end
assign Check_ok = sys_reset_n && init_done_sync[1];
assign LED=Check_ok;

// Read and write groups share the application port; refresh can stop both.
wire write_request, write_grant, write_owned;
wire read_request, read_grant, read_active;
wire writer_reset_n, write_block;
wire desc_ready, desc_valid, pixel_accept;
wire [20:0] desc_base;
wire front_valid;
wire [20:0] front_base;
wire [15:0] front_width, front_height;
wire read_fifo_full, read_fifo_wr_en, read_error, read_urgent;
wire read_raster_active;
wire [23:0] read_fifo_data;
wire display_path_reset_n = !reset_request && display_reset_n;
reg [1:0] blank_sync;
always @(posedge Clk or negedge mem_reset_n) begin
    if(!mem_reset_n) blank_sync <= 0;
    else blank_sync <= {blank_sync[0],display_frame_sync && display_reset_n};
end
wire blank_flush = blank_sync[1];
reg [1:0] read_error_sync;
always @(posedge display_clk or negedge display_path_reset_n) begin
    if(!display_path_reset_n) read_error_sync <= 0;
    else read_error_sync <= {read_error_sync[0],read_error};
end
wire pixel_fifo_valid, pixel_fifo_underflow;
assign display_pixel_valid = pixel_fifo_valid && !read_error_sync[1];
assign display_underflow = pixel_fifo_underflow || read_error_sync[1];
assign debug_error_flags = {refresh_error,read_error,pixel_fifo_underflow};

wire full;
assign pixel_ready = sys_reset_n && init_done_sync[1] && pixel_accept && !full;

//负责由frame_desc_cdc输送给sdram_write_ctrl的帧描述信息
wire dst_valid;     
wire [20:0]dst_base_addr;  
wire [15:0]dst_width;      
wire [15:0]dst_height;     
wire dst_top_down;   

wire frame_write_done;

// Start the PLL once after FPGA configuration. Keep its SDRAM clock
// running across task resets so reset cannot truncate a clock pulse.
reg [7:0] pll_boot_release = 0;
always @(posedge SYS_CLK) pll_boot_release <= {pll_boot_release[6:0],1'b1};
clk_pll u0_clk(
		.refclk(SYS_CLK),
		.reset(!pll_boot_release[7]),
		.extlock(lock),
		.clk0_out(local_clk),
		.clk1_out(Clk),
		.clk2_out(Clk_sft)
		);
assign Rst = !mem_reset_n;

async_fifo #(
    .DATA_WIDTH(`DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH)
) dut (
    .wr_clk(SYS_CLK),
    .rd_clk(Clk),
    .Reset_n(!reset_request && writer_reset_n),

    // Write interface
    .wr_en(pixel_valid && pixel_ready),
    .wr_data(fifo_wr_data),
    .full(full),

    // Read interface
    .rd_en(fifo_rd_en),
    .rd_data(fifo_rd_data),
    .rd_valid(fifo_rd_valid),
    .empty(fifo_empty)
);

frame_desc_cdc ucdc (
        .src_clk        (SYS_CLK        ),
        .src_rst_n      (sys_reset_n),
        .src_valid      (desc_valid),
        .src_ready      (desc_ready),
        .src_base_addr  (desc_base  ),
        .src_width      (frame_width      ),
        .src_height     (frame_height     ),
        .src_top_down   (frame_top_down   ),


        .dst_clk        (Clk        ),
        .dst_rst_n      (mem_reset_n),
        .dst_valid      (dst_valid      ),
        .dst_base_addr  (dst_base_addr  ),
        .dst_width      (dst_width      ),
        .dst_height     (dst_height     ),
        .dst_top_down   (dst_top_down   ),

        .frame_write_done(frame_write_done),
        .frame_write_done_sync(frame_write_done_sync)
    );


sdram_write_ctrl uut (
        .Clk                (Clk                ),
        .Reset_n            (writer_reset_n   ),
        .Sdr_init_done      (Sdr_init_done      ),
        .Sdr_init_ref_vld   (Sdr_init_ref_vld   ),
        .Sdr_refresh_pending(refresh_pending || !write_grant || write_block),
        .Sdr_busy           (Sdr_busy          ),
        .fifo_rd_data       (fifo_rd_data      ),
        .fifo_rd_valid      (fifo_rd_valid      ),
        .fifo_empty         (fifo_empty        ),
        .fifo_rd_en         (fifo_rd_en       ),
        .App_wr_en          (App_wr_en          ),
        .write_request      (write_request      ),
        .App_wr_addr        (App_wr_addr        ),
        .App_wr_din         (App_wr_din         ),
        .App_wr_dm          (App_wr_dm          ),

        .dst_valid(dst_valid),     
        .dst_base_addr(dst_base_addr),  
        .dst_width(dst_width),      
        .dst_height(dst_height),     
        .dst_top_down(dst_top_down),   

        .frame_write_done(frame_write_done)

    );


frame_buffer_ctrl #(
    .DISPLAY_WIDTH(DISPLAY_WIDTH), .DISPLAY_HEIGHT(DISPLAY_HEIGHT)
) u_frame_buffers (
    .sys_clk(SYS_CLK), .sys_rst_n(sys_reset_n), .initialized(init_done_sync[1]),
    .frame_start(frame_start), .frame_end(frame_end), .frame_abort(frame_abort),
    .frame_base_addr(frame_base_addr), .frame_width(frame_width), .frame_height(frame_height),
    .desc_ready(desc_ready), .desc_valid(desc_valid), .desc_base(desc_base),
    .pixel_accept(pixel_accept), .frame_write_ready(frame_write_ready), .frame_error(frame_error),
    .mem_clk(Clk), .mem_rst_n(mem_reset_n), .dst_valid(dst_valid),
    .dst_base(dst_base_addr), .dst_width(dst_width), .dst_height(dst_height),
    .writer_done(frame_write_done), .write_owned(write_owned), .read_active(read_active),
    .blank_flush(blank_flush), .writer_reset_n(writer_reset_n), .write_block(write_block),
    .front_valid(front_valid), .front_base(front_base),
    .front_width(front_width), .front_height(front_height)
);

// Sdr_busy, read_active and read_return cover physical drain.
// Retain one idle cycle after all three are inactive before granting again.
sdram_app_arbiter #(.QUIET_CYCLES(1)) u_app_arbiter (
    .Clk(Clk), .Reset_n(mem_reset_n), .initialized(Sdr_init_done),
    .refresh_pending(refresh_pending), .refresh_active(Sdr_init_ref_vld), .sdram_busy(Sdr_busy),
    .write_request(write_request && !write_block), .write_active(App_wr_en),
    .read_request(read_request), .read_urgent(read_urgent && read_raster_active), .read_active(read_active), .read_return(Sdr_rd_en),
    .write_grant(write_grant), .read_grant(read_grant), .write_owned(write_owned)
);

sdram_read_ctrl #(
    .DISPLAY_WIDTH(DISPLAY_WIDTH), .DISPLAY_HEIGHT(DISPLAY_HEIGHT)
) u_reader (
    .Clk(Clk), .Reset_n(mem_reset_n), .blank_flush(blank_flush),
    .front_valid(front_valid), .front_base(front_base),
    .front_width(front_width), .front_height(front_height),
    .read_request(read_request), .read_grant(read_grant), .read_active(read_active),
    .raster_active(read_raster_active),
    .App_rd_en(App_rd_en), .App_rd_addr(App_rd_addr),
    .Sdr_rd_en(Sdr_rd_en), .Sdr_rd_dout(Sdr_rd_dout),
    .fifo_full(read_fifo_full), .fifo_wr_en(read_fifo_wr_en), .fifo_wr_data(read_fifo_data),
    .read_error(read_error)
);

display_pixel_fifo #(.ADDR_WIDTH(DISPLAY_FIFO_ADDR_WIDTH)) u_display_fifo (
    .mem_clk(Clk), .pix_clk(display_clk), .Reset_n(display_path_reset_n),
    .blank_flush(display_frame_sync), .frame_valid_mem(front_valid),
    .wr_en(read_fifo_wr_en), .wr_data(read_fifo_data), .full(read_fifo_full), .read_urgent(read_urgent),
    .pix_req(display_pixel_req), .pix_rgb(display_pixel_rgb), .pix_valid(pixel_fifo_valid),
    .frame_ready(display_frame_ready), .underflow(pixel_fifo_underflow)
);

// Quiesce application traffic before issuing a single refresh request.
// 1500 cycles at 100 MHz = 15 us (EM638325: 4096 refreshes / 64 ms).
sdram_refresh_ctrl #(.INTERVAL_CYCLES(1500)) u_refresh (
    .Clk(Clk), .Reset_n(mem_reset_n), .Sdr_init_done(Sdr_init_done),
    .Sdr_init_ref_vld(Sdr_init_ref_vld), .Sdr_busy(Sdr_busy),
    .App_wr_en(App_wr_en), .App_rd_en(App_rd_en),
    .manual_refresh_req(manual_refresh_req),
    .refresh_pending(refresh_pending), .App_ref_req(app_refresh_req),
    .refresh_error(refresh_error)
);



sdr_as_ram  #( .self_refresh_open(1'b0))
	u2_ram( 
		.Sdr_clk(Clk),
		.Sdr_clk_sft(Clk_sft),
		.Rst(Rst),
			  			  
		.Sdr_init_done(Sdr_init_done),
		.Sdr_init_ref_vld(Sdr_init_ref_vld),
		.Sdr_busy(Sdr_busy),
		
		.App_ref_req(app_refresh_req),
		
        .App_wr_en(App_wr_en), 
        .App_wr_addr(App_wr_addr),  	
		.App_wr_dm(App_wr_dm),
		.App_wr_din(App_wr_din),

		.App_rd_en(App_rd_en),
		.App_rd_addr(App_rd_addr),
		.Sdr_rd_en	(Sdr_rd_en),
		.Sdr_rd_dout(Sdr_rd_dout),
	
		.SDRAM_CLK(SDRAM_CLK),
		.SDR_RAS(SDR_RAS),
		.SDR_CAS(SDR_CAS),
		.SDR_WE(SDR_WE),
		.SDR_BA(SDR_BA),
		.SDR_ADDR(SDR_ADDR),
		.SDR_DM(SDR_DM),
		.SDR_DQ(SDR_DQ)	
	);


// Device primitive: connect the controller to the packaged SDRAM.
EG_PHY_SDRAM_2M_32 u_sdram_phy (
    .clk   (SDRAM_CLK),
    .ras_n (SDR_RAS),
    .cas_n (SDR_CAS),
    .we_n  (SDR_WE),
    .addr  (SDR_ADDR),
    .ba    (SDR_BA),
    .dq    (SDR_DQ),
    .cs_n  (1'b0),
    .dm0   (SDR_DM[0]),
    .dm1   (SDR_DM[1]),
    .dm2   (SDR_DM[2]),
    .dm3   (SDR_DM[3]),
    .cke   (1'b1)
);

endmodule
