`include "../../include/global_def.v"

module memory_top (
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

assign App_rd_en = 0;
assign App_rd_addr = 21'd0;

wire full;
assign pixel_ready = sys_reset_n && init_done_sync[1] && !full;

//负责由frame_desc_cdc输送给sdram_write_ctrl的帧描述信息
wire dst_valid;     
wire [20:0]dst_base_addr;  
wire [15:0]dst_width;      
wire [15:0]dst_height;     
wire dst_top_down;   

wire frame_write_done;

clk_pll u0_clk(
		.refclk(SYS_CLK),
		.reset(1'b0),
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
    .Reset_n(!reset_request),

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
        .src_valid      (frame_start && init_done_sync[1]),
        .src_ready      (      ),
        .src_base_addr  (frame_base_addr  ),
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
        .Reset_n            (mem_reset_n      ),
        .Sdr_init_done      (Sdr_init_done      ),
        .Sdr_init_ref_vld   (Sdr_init_ref_vld   ),
        .Sdr_refresh_pending(refresh_pending   ),
        .Sdr_busy           (Sdr_busy          ),
        .fifo_rd_data       (fifo_rd_data      ),
        .fifo_rd_valid      (fifo_rd_valid      ),
        .fifo_empty         (fifo_empty        ),
        .fifo_rd_en         (fifo_rd_en       ),
        .App_wr_en          (App_wr_en          ),
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


// Quiesce application traffic before issuing a single refresh request.
// 1875 cycles at 125 MHz = 15 us (EM638325: 4096 refreshes / 64 ms).
sdram_refresh_ctrl u_refresh (
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