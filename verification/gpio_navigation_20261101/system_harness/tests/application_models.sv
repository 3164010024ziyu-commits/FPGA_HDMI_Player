`timescale 1ns/1ps
// Test-only application-port model. The production encrypted SDRAM IP is
// separately compiled and tested; this model permits deterministic stalls.
module clk_pll(input refclk,reset,output reg extlock=0,
                output reg clk0_out=0,clk1_out=0,clk2_out=0);
    always #5 clk0_out=~clk0_out;
    always #5 clk1_out=~clk1_out;
    always #5 clk2_out=~clk2_out;
    initial begin #80; extlock=1; end
endmodule

module sdr_as_ram #(parameter self_refresh_open=0)(
    input Sdr_clk,Sdr_clk_sft,Rst,
    output reg Sdr_init_done=0,Sdr_init_ref_vld=0,Sdr_busy=0,
    input App_ref_req,App_wr_en,input [20:0] App_wr_addr,
    input [3:0] App_wr_dm,input [31:0] App_wr_din,
    input App_rd_en,input [20:0] App_rd_addr,
    output reg Sdr_rd_en=0,output reg [31:0] Sdr_rd_dout=0,
    output SDRAM_CLK,SDR_RAS,SDR_CAS,SDR_WE,
    output [1:0] SDR_BA,output [10:0] SDR_ADDR,output [3:0] SDR_DM,
    inout [31:0] SDR_DQ
);
    reg [31:0] data [0:2097151];
    reg [20:0] addresses [0:3];
    integer init_count=0,write_drain=0,read_delay=0,read_index=0,issued=0,refresh_count=0;
    integer reads=0,writes=0,refreshes=0;
    integer extra_read_delay=0;
    reg returning=0;
    assign SDRAM_CLK=Sdr_clk_sft;
    assign {SDR_RAS,SDR_CAS,SDR_WE}=3'b111;
    assign SDR_BA=0;assign SDR_ADDR=0;assign SDR_DM=0;
    always @(posedge Sdr_clk or posedge Rst) begin
        if(Rst) begin
            init_count=0;Sdr_init_done<=0;Sdr_init_ref_vld<=1;Sdr_busy<=0;
            Sdr_rd_en<=0;Sdr_rd_dout<=0;write_drain=0;read_delay=0;
            read_index=0;issued=0;returning=0;refresh_count=0;
        end else begin
            Sdr_rd_en<=0;
            if(!Sdr_init_done) begin
                init_count=init_count+1;
                if(init_count==12) begin Sdr_init_done<=1;Sdr_init_ref_vld<=0;end
            end else begin
                if(App_wr_en && App_rd_en) $fatal(1,"MODEL simultaneous read and write");
                if((App_wr_en || App_rd_en) && Sdr_init_ref_vld) $fatal(1,"MODEL application during refresh");
                if(App_wr_en) begin
                    data[App_wr_addr]=App_wr_din;
                    writes=writes+1; write_drain=5;
                end else if(write_drain>0) write_drain=write_drain-1;
                if(App_rd_en) begin
                    if(issued>=4 || returning) $fatal(1,"MODEL overlapping read groups");
                    addresses[issued]=App_rd_addr;issued=issued+1;
                    if(issued==4) begin read_delay=3+extra_read_delay;read_index=0;returning=1;end
                end else if(returning) begin
                    if(read_delay>0) read_delay=read_delay-1;
                    else begin
                        Sdr_rd_en<=1;Sdr_rd_dout<=data[addresses[read_index]];
                        reads=reads+1;
                        if(read_index==3) begin returning=0;issued=0;end
                        else read_index=read_index+1;
                    end
                end
                if(App_ref_req) begin
                    if(Sdr_busy || Sdr_init_ref_vld) $fatal(1,"MODEL refresh before drain");
                    refresh_count=9;refreshes=refreshes+1;Sdr_init_ref_vld<=1;
                end else if(refresh_count>0) begin
                    refresh_count=refresh_count-1;
                    if(refresh_count==0) Sdr_init_ref_vld<=0;
                end
                Sdr_busy <= write_drain>0 || issued>0 || returning || Sdr_rd_en;
            end
        end
    end
endmodule

module EG_PHY_SDRAM_2M_32(input clk,ras_n,cas_n,we_n,input [10:0] addr,
    input [1:0] ba,inout [31:0] dq,input cs_n,dm0,dm1,dm2,dm3,cke);
endmodule

// Display PLL model for full-system functional tests. Real PLL hierarchy is
// elaborated separately; this model has the same 50 -> 125/25 MHz frequencies.
module clk_wize(input refclk,reset,output reg extlock=0,
                output reg clk0_out=0,clk1_out=0);
    always #4 clk0_out=~clk0_out;
    always #20 clk1_out=~clk1_out;
    initial begin #80;extlock=1;end
endmodule
