`timescale 1ns/1ps
module full_raster_tb;
    reg sys_clk=0,pix_clk=0,rst_n=0,pix_rst_n=0;
    always #10 sys_clk=~sys_clk;
    always #20 pix_clk=~pix_clk;
    reg pixel_valid=0,frame_start=0,frame_end=0;
    reg [23:0] pixel_data=0;
    wire ready,done,write_ready,error,led;
    wire [23:0] rgb,hdmi_rgb;
    wire valid,frame_ready,underflow,req,blank,de;
    wire [9:0] x,y;
    memory_top dut(
        .SYS_CLK(sys_clk),.Reset_n(rst_n),.pixel_valid(pixel_valid),.pixel_data(pixel_data),.pixel_ready(ready),
        .frame_start(frame_start),.frame_base_addr(21'd0),.frame_width(16'd640),.frame_height(16'd480),.frame_top_down(1'b1),
        .frame_end(frame_end),.frame_abort(1'b0),.frame_write_done_sync(done),.frame_write_ready(write_ready),.frame_error(error),
        .display_clk(pix_clk),.display_reset_n(pix_rst_n),.display_frame_sync(blank),.display_pixel_req(req),
        .display_pixel_rgb(rgb),.display_pixel_valid(valid),.display_frame_ready(frame_ready),.display_underflow(underflow),.LED(led)
    );
    read_RAM timing(.clk25M(pix_clk),.reset_n(pix_rst_n),.pix_rgb(rgb),.pix_valid(valid),
        .pix_req(req),.frame_sync(blank),.HDMI_EN(de),.HDMI_HSYNC(),.HDMI_VSYNC(),.HDMI_X(x),.HDMI_Y(y),.HDMI_D(hdmi_rgb));
    integer seeds[0:1],frames=0,pixels=0,concurrent_reads=0,stalls=0,min_used=2048;
    reg writing_second=0;
    function [23:0] pattern(input integer tag,xx,yy);
        pattern={tag[7:0],yy[7:0],xx[7:0]} ^ (xx[8] ? 24'h005a00 : 0);
    endfunction
    always @(posedge pix_clk)if(req && frame_ready)begin
        if(!valid || underflow)$fatal(1,"full raster underrun xy=%0d,%0d fifo=%0d reader=%0d",x,y,dut.u_display_fifo.wr_used,dut.u_reader.state);
        if(hdmi_rgb!==pattern(seeds[dut.front_base==0?0:1],x,y))
            $fatal(1,"full raster pixel xy=%0d,%0d got=%h expected=%h",x,y,hdmi_rgb,pattern(seeds[dut.front_base==0?0:1],x,y));
        pixels=pixels+1;
        if(dut.u_display_fifo.wr_used<min_used)min_used=dut.u_display_fifo.wr_used;
        if(x==639 && y==479)begin frames=frames+1;$display("FULL_FRAME_RESULT frame=%0d pixels=%0d time=%0t",frames,pixels,$time);end
    end
    always @(posedge dut.Clk)if(dut.mem_reset_n)begin
        if(dut.App_rd_en && writing_second)concurrent_reads=concurrent_reads+1;
        if(dut.App_wr_en && dut.front_valid && dut.App_wr_addr>=dut.front_base && dut.App_wr_addr<dut.front_base+307200)
            $fatal(1,"full raster front overwrite");
        if(dut.refresh_error || error)$fatal(1,"full raster controller error");
        if(dut.u_display_fifo.wr_used>2048)$fatal(1,"FIFO occupancy out of range");
    end
    task send_frame(input integer tag);
        integer k,b;
        wait(write_ready);b=dut.u_frame_buffers.bank_sync[1];seeds[b]=tag;
        @(negedge sys_clk);frame_start=1;
        @(negedge sys_clk);frame_start=0;
        for(k=0;k<307200;k=k+1)begin
            @(negedge sys_clk);
            while(!ready)begin stalls=stalls+1;@(negedge sys_clk);end
            pixel_valid=1;pixel_data=pattern(tag,k%640,k/640);
        end
        @(negedge sys_clk);pixel_valid=0;frame_end=1;
        @(negedge sys_clk);frame_end=0;
        wait(done);wait(write_ready);
    endtask
    initial begin
        #100;rst_n=1;wait(led);@(negedge pix_clk);pix_rst_n=1;
        send_frame(1);
        writing_second=1;send_frame(2);writing_second=0;
        wait(frames>=3);
        if(dut.front_base!=307200)$fatal(1,"second completed image was not displayed");
        if(concurrent_reads<1000 || dut.u2_ram.refreshes<100)$fatal(1,"full raster coverage missing");
        $display("FULL_RASTER_PASS pixels=%0d frames=%0d concurrent_reads=%0d source_stalls=%0d minimum_fifo_used=%0d refreshes=%0d",pixels,frames,concurrent_reads,stalls,min_used,dut.u2_ram.refreshes);
        $finish;
    end
    initial begin #120000000;$fatal(1,"full raster timeout frames=%0d",frames);end
endmodule
