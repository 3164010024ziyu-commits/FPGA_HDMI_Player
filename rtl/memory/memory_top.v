
`include "../../include/global_def.v"

module memory_top(   
		input   SYS_CLK,
		input wr_en,
        input [`DATA_WIDTH-1:0]wr_data,
		output full,

		output			LED
	);

localparam ADDR_WIDTH = 4;

wire			lock,local_clk,Clk,Clk_sft,Rst;

wire fifo_empty;
wire [`DATA_WIDTH-1:0]fifo_rd_data;
wire fifo_rd_en;
wire fifo_rd_valid;

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
assign Check_ok = lock && Sdr_init_done;
assign LED=Check_ok;

assign App_rd_en = 0;
assign App_rd_addr = 21'd0;


clk_pll u0_clk(
		.refclk(SYS_CLK),
		.reset(1'b0),
		.extlock(lock),
		.clk0_out(local_clk),
		.clk1_out(Clk),
		.clk2_out(Clk_sft)
		);
assign Rst=!lock;

sync_fifo #(
    .DATA_WIDTH(`DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH)
) dut (
    .Clk(Clk),
    .Reset_n(~Rst),

    // Write interface
    .wr_en(wr_en),
    .wr_data(wr_data),
    .full(full),

    // Read interface
    .rd_en(fifo_rd_en),
    .rd_data(fifo_rd_data),
    .rd_valid(fifo_rd_valid),
    .empty(fifo_empty)
);

sdram_write_ctrl uut (
        .Clk                (Clk                ),
        .Reset_n            (~Rst            ),
        .Sdr_init_done      (Sdr_init_done      ),
        .Sdr_init_ref_vld   (Sdr_init_ref_vld   ),
        .fifo_rd_data       (fifo_rd_data      ),
        .fifo_rd_valid      (fifo_rd_valid      ),
        .fifo_empty         (fifo_empty        ),
        .fifo_rd_en         (fifo_rd_en       ),
        .App_wr_en          (App_wr_en          ),
        .App_wr_addr        (App_wr_addr        ),
        .App_wr_din         (App_wr_din         ),
        .App_wr_dm          (App_wr_dm          )
    );


sdr_as_ram  #( .self_refresh_open(1'b1))
	u2_ram( 
		.Sdr_clk(Clk),
		.Sdr_clk_sft(Clk_sft),
		.Rst(Rst),
			  			  
		.Sdr_init_done(Sdr_init_done),
		.Sdr_init_ref_vld(Sdr_init_ref_vld),
		.Sdr_busy(Sdr_busy),
		
		.App_ref_req(1'b0),
		
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