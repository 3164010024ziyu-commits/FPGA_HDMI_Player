`timescale 1ns/1ps
module memory_display_tb;
    reg sys_clk=0,pix_clk=0,rst_n=0,pix_rst_n=0;
    always #10 sys_clk=~sys_clk;
    always #20 pix_clk=~pix_clk;
    reg pixel_valid=0,frame_start=0,frame_end=0,frame_abort=0;
    reg [23:0] pixel_data=0;
    reg [20:0] pool=128;
    reg [15:0] width=8,height=4;
    reg top_down=1;
    wire ready,done,write_ready,frame_error,led;
    wire [23:0] rgb;
    wire valid,front_ready,underflow;
    integer px=0,py=0;
    wire pix_req=pix_rst_n && px<16 && py<8;
    wire frame_sync=pix_rst_n && py==8;
    always @(posedge pix_clk or negedge pix_rst_n) begin
        if(!pix_rst_n)begin px<=0;py<=0;end
        else if(px==23)begin px<=0;py<=py==11?0:py+1;end
        else px<=px+1;
    end
    memory_top #(.DISPLAY_WIDTH(16),.DISPLAY_HEIGHT(8),.DISPLAY_FIFO_ADDR_WIDTH(3)) dut (
        .SYS_CLK(sys_clk),.Reset_n(rst_n),.pixel_valid(pixel_valid),.pixel_data(pixel_data),.pixel_ready(ready),
        .frame_start(frame_start),.frame_base_addr(pool),.frame_width(width),.frame_height(height),.frame_top_down(top_down),
        .frame_end(frame_end),.frame_abort(frame_abort),.frame_write_done_sync(done),.frame_write_ready(write_ready),.frame_error(frame_error),
        .display_clk(pix_clk),.display_reset_n(pix_rst_n),.display_frame_sync(frame_sync),.display_pixel_req(pix_req),
        .display_pixel_rgb(rgb),.display_pixel_valid(valid),.display_frame_ready(front_ready),.display_underflow(underflow),.LED(led)
    );
    integer checks=0,frames=0,swaps=0,aborts=0,format_errors=0,write_run=0,read_run=0;
    integer seeds[0:1], widths[0:1], heights[0:1];
    integer front_seed,fw,fh,bank;
    reg [20:0] previous_front=0;
    reg previous_front_valid=0;
    reg checking=1;
    function [23:0] color(input integer seed,x,y);
        color=24'h100000+seed*24'h010000+y*256+x;
    endfunction
    always @(posedge dut.Clk) begin
        if(rst_n && dut.mem_reset_n) begin
            if(dut.App_wr_en && dut.App_rd_en) $fatal(1,"application collision");
            if(dut.App_wr_en)begin
                write_run=write_run+1;
                if(dut.front_valid && dut.App_wr_addr>=dut.front_base && dut.App_wr_addr<dut.front_base+128)
                    $fatal(1,"front slot overwritten");
            end else if(write_run!=0)begin
                if(write_run!=4)$fatal(1,"write run=%0d",write_run);write_run=0;
            end
            if(dut.App_rd_en)read_run=read_run+1;
            else if(read_run!=0)begin
                if(read_run!=4)$fatal(1,"read run=%0d",read_run);read_run=0;
            end
            if(dut.refresh_error)$fatal(1,"refresh watchdog");
        end else begin write_run=0;read_run=0;end
        #0.001;
        if(dut.front_valid && (!previous_front_valid || dut.front_base!=previous_front))begin
            if(!dut.blank_flush || dut.read_active)$fatal(1,"unsafe frame swap");
            swaps=swaps+1;
        end
        previous_front_valid=dut.front_valid;previous_front=dut.front_base;
    end
    always @(posedge sys_clk) if(frame_error) format_errors=format_errors+1;
    always @(posedge pix_clk)begin
        if(pix_req && front_ready && checking)begin
            if(underflow || !valid)$fatal(1,"pixel underflow xy=%0d,%0d state=%0d",px,py,dut.u_reader.state);
            bank=dut.front_base==pool?0:1;
            front_seed=seeds[bank];fw=widths[bank];fh=heights[bank];
            if(rgb !== ((px<fw && py<fh)?color(front_seed,px,py):24'd0))
                $fatal(1,"pixel mismatch xy=%0d,%0d got=%h seed=%0d bank=%0d",px,py,rgb,front_seed,bank);
            checks=checks+1;
            if(px==15 && py==7)frames=frames+1;
        end
    end
    task descriptor(input integer w,h,td);
        wait(write_ready);@(negedge sys_clk);width=w;height=h;top_down=td;frame_start=1;
        @(negedge sys_clk);frame_start=0;
    endtask
    task send_pixels(input integer n,seed,w,h,td);
        integer k,row;
        for(k=0;k<n;k=k+1)begin
            @(negedge sys_clk);
            while(!ready)@(negedge sys_clk);
            row=td?k/w:h-1-k/w;
            pixel_valid=1;pixel_data=color(seed,k%w,row);
        end
        @(negedge sys_clk);pixel_valid=0;
    endtask
    task send_frame(input integer seed,w,h,td);
        integer b;
        wait(write_ready);b=dut.u_frame_buffers.bank_sync[1];
        seeds[b]=seed;widths[b]=w;heights[b]=h;
        descriptor(w,h,td);send_pixels(w*h,seed,w,h,td);
        frame_end=1;@(negedge sys_clk);frame_end=0;
        wait(!done);wait(done);
        if(write_ready)$fatal(1,"back slot reused before publication");
        wait(write_ready);
    endtask
    initial begin
        #100;rst_n=1;wait(led);@(negedge pix_clk);pix_rst_n=1;
        send_frame(1,8,4,1);
        wait(frames>=2);
        send_frame(2,16,8,0);
        wait(frames>=4);
        // Abort an incomplete four-word prefetch, retaining the old front.
        descriptor(8,4,1);send_pixels(3,3,8,4,1);
        frame_abort=1;@(negedge sys_clk);frame_abort=0;aborts=aborts+1;
        wait(write_ready);
        // Abort while an accepted group is already being written; the
        // arbiter must retain ownership until all four beats and drain end.
        descriptor(8,4,1);
        fork
            send_pixels(4,3,8,4,1);
            begin
                wait(dut.App_wr_en);@(negedge sys_clk);frame_abort=1;
                @(negedge sys_clk);frame_abort=0;aborts=aborts+1;
            end
        join
        wait(write_ready);
        send_frame(4,8,4,1);wait(frames>=6);
        // Unsupported width is rejected and cannot publish a stale frame.
        descriptor(7,4,1);wait(format_errors>0);wait(write_ready);
        send_frame(5,16,8,1);wait(frames>=8);
        // A late group may blacken a frame, but must not shift pixels in the
        // following frame. Exercise ordinary underflow and response timeout.
        checking=0;dut.u2_ram.extra_read_delay=80;
        wait(underflow);#0.01;
        if(valid)$fatal(1,"underflow did not mask pixels");
        dut.u2_ram.extra_read_delay=0;
        wait(frame_sync);wait(!frame_sync);checking=1;wait(frames>=10);
        checking=0;dut.u2_ram.extra_read_delay=400;
        wait(dut.read_error);dut.u2_ram.extra_read_delay=0;
        wait(frame_sync);wait(!frame_sync);checking=1;wait(frames>=12);
        // Explicit reset invalidates both banks and all queued pixels.
        @(negedge sys_clk);rst_n=0;pix_rst_n=0;pixel_valid=0;
        #120;rst_n=1;wait(led);@(negedge pix_clk);pix_rst_n=1;
        send_frame(6,8,4,0);wait(frames>=14);
        if(dut.u2_ram.refreshes<2)$fatal(1,"refresh coverage missing");
        $display("MEMORY_DISPLAY_PASS pixels=%0d frames=%0d swaps=%0d aborts=%0d format_errors=%0d refreshes=%0d underflow_recovery=1 timeout_recovery=1",checks,frames,swaps,aborts,format_errors,dut.u2_ram.refreshes);
        $finish;
    end
    initial begin #2000000;$fatal(1,"timeout state=%0d done=%b ready=%b",dut.u_reader.state,done,write_ready);end
endmodule
