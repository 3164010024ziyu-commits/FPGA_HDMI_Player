
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

assign LED=Check_ok;


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


endmodule