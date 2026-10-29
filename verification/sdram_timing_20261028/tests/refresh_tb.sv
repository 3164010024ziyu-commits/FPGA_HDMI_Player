`timescale 1ns/1ps
module refresh_wait_tb;
    reg SYS_CLK=0,pix_clk=0,Reset_n=0,pixel_valid=0,frame_start=0;
    always #10 SYS_CLK=~SYS_CLK;
    always #20 pix_clk=~pix_clk;
    reg [23:0] pixel_data=0;
    wire ready,led,frame_ready;
    integer scenario=0,events,accepted=0,app_writes=0,physical_refreshes=0;
    reg observing=0,probe_bound=0,feed=0;
    realtime origin;
    memory_top dut(.SYS_CLK(SYS_CLK),.Reset_n(Reset_n),
        .pixel_valid(pixel_valid),.pixel_data(pixel_data),.pixel_ready(ready),
        .frame_start(frame_start),.frame_base_addr(21'd0),.frame_width(16'd640),.frame_height(16'd480),.frame_top_down(1'b1),
        .frame_end(1'b0),.frame_abort(1'b0),.frame_write_done_sync(),.frame_write_ready(frame_ready),.frame_error(),
        .display_clk(pix_clk),.display_reset_n(1'b0),.display_frame_sync(1'b0),.display_pixel_req(1'b0),
        .display_pixel_rgb(),.display_pixel_valid(),.display_frame_ready(),.display_underflow(),.LED(led));
    IS42s32200 dram(.Clk(dut.SDRAM_CLK),.Cke(1'b1),.Cs_n(1'b0),.Ras_n(dut.SDR_RAS),
        .Cas_n(dut.SDR_CAS),.We_n(dut.SDR_WE),.Ba(dut.SDR_BA),.Addr(dut.SDR_ADDR),.Dqm(dut.SDR_DM),.Dq(dut.SDR_DQ));
    task log_event(input [8*40-1:0] kind,input integer value);
        if(observing)$fdisplay(events,"%0.3f,%0.3f,%0s,%0d",$realtime,$realtime-origin,kind,value);
    endtask
    always @(negedge SYS_CLK)begin
        pixel_valid=feed && !(scenario==2 && accepted>=4096);
        pixel_data=24'h400000+accepted;
    end
    always @(posedge SYS_CLK)if(pixel_valid && ready)accepted=accepted+1;
    always @(posedge dut.Clk)if(observing)begin
        if(dut.refresh_error)$fatal(1,"refresh watchdog");
        if(dut.App_wr_en)begin
            if(dut.Sdr_init_ref_vld)$fatal(1,"write during refresh");
            if(dut.App_wr_addr!==app_writes || dut.App_wr_din!==32'h00400000+app_writes)
                $fatal(1,"write sequence addr=%d data=%h expected=%d",dut.App_wr_addr,dut.App_wr_din,app_writes);
            app_writes=app_writes+1;
        end
    end
    always @(dut.refresh_pending)log_event("REFRESH_PENDING",dut.refresh_pending);
    always @(dut.Sdr_init_ref_vld)log_event("REFRESH_VALID",dut.Sdr_init_ref_vld);
    always @(posedge dut.SDRAM_CLK)if(observing && {dut.SDR_RAS,dut.SDR_CAS,dut.SDR_WE}===3'b001)begin
        physical_refreshes=physical_refreshes+1;log_event("AUTO_REFRESH",physical_refreshes);
    end
    initial begin
        if(!$value$plusargs("SCENARIO=%d",scenario))scenario=0;
        events=$fopen("events.csv","w");
        $fdisplay(events,"absolute_ns,relative_ns,event,value");
        #100;Reset_n=1;wait(led && frame_ready);@(negedge SYS_CLK);
        if(!probe_bound)$fatal(1,"refresh observer did not bind");
        origin=$realtime;observing=1;
        if(scenario!=0)begin frame_start=1;@(negedge SYS_CLK);frame_start=0;feed=1;end
        #512000;
        if(physical_refreshes!=34)$fatal(1,"refresh count=%0d expected=34",physical_refreshes);
        if(scenario==2 && (accepted!=4096 || app_writes!=4096))$fatal(1,"pause drain incomplete");
        $display("CURRENT_REFRESH_PASS scenario=%0d accepted=%0d app_writes=%0d refreshes=%0d",scenario,accepted,app_writes,physical_refreshes);
        $fclose(events);$finish;
    end
    initial begin #3000000;$fatal(1,"refresh timeout");end
endmodule
