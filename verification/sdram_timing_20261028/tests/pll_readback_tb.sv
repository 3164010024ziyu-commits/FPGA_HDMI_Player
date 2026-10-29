`timescale 1ns/1ps
module real_ip_display_tb;
    reg SYS_CLK=0,mem_clk=0,pix_clk=0,rst_n=0,pix_rst_n=0;
    always #10 SYS_CLK=~SYS_CLK;
    always #4 mem_clk=~mem_clk;
    always #20 pix_clk=~pix_clk;
    reg pixel_valid=0,frame_start=0,frame_end=0;
    reg [23:0] pixel_data=0;
    reg top_down=1;
    wire ready,done,write_ready,error,led;
    wire [23:0] rgb;
    wire valid,frame_ready,underflow;
    integer x=0,y=0;
    wire req=pix_rst_n && x<16 && y<8;
    wire blank=pix_rst_n && y==8;
    always @(posedge pix_clk or negedge pix_rst_n) begin
        if(!pix_rst_n)begin x<=0;y<=0;end
        else if(x==23)begin x<=0;y<=y==11?0:y+1;end
        else x<=x+1;
    end
    memory_top #(.DISPLAY_WIDTH(16),.DISPLAY_HEIGHT(8),.DISPLAY_FIFO_ADDR_WIDTH(4)) dut(
        .SYS_CLK(SYS_CLK),.Reset_n(rst_n),.pixel_valid(pixel_valid),.pixel_data(pixel_data),.pixel_ready(ready),
        .frame_start(frame_start),.frame_base_addr(21'd128),.frame_width(16'd8),.frame_height(16'd4),.frame_top_down(top_down),
        .frame_end(frame_end),.frame_abort(1'b0),.frame_write_done_sync(done),.frame_write_ready(write_ready),.frame_error(error),
        .display_clk(pix_clk),.display_reset_n(pix_rst_n),.display_frame_sync(blank),.display_pixel_req(req),
        .display_pixel_rgb(rgb),.display_pixel_valid(valid),.display_frame_ready(frame_ready),.display_underflow(underflow),.LED(led)
    );
    IS42s32200 dram(.Clk(dut.SDRAM_CLK),.Cke(1'b1),.Cs_n(1'b0),.Ras_n(dut.SDR_RAS),
        .Cas_n(dut.SDR_CAS),.We_n(dut.SDR_WE),.Ba(dut.SDR_BA),.Addr(dut.SDR_ADDR),.Dqm(dut.SDR_DM),.Dq(dut.SDR_DQ));
    real last_mem_edge=0.0;
    integer clock_checks=0, traced=0;
    always @(posedge dut.Clk) if(dut.lock) begin
        if(last_mem_edge>0 && ($realtime-last_mem_edge<9.999 || $realtime-last_mem_edge>10.001))
            $fatal(1,"unexpected memory PLL period %0.4f",$realtime-last_mem_edge);
        last_mem_edge=$realtime;
    end else last_mem_edge=0.0;
    always @(posedge dut.Clk_sft) if(dut.lock && last_mem_edge>0 && clock_checks<100) begin
        if($realtime-last_mem_edge<8.499 || $realtime-last_mem_edge>8.501)
            $fatal(1,"unexpected forwarded phase %0.4f",$realtime-last_mem_edge);
        clock_checks=clock_checks+1;
    end
    always @(dram.Dq_reg) if(traced<20 && dram.Dq_reg!==32'hzzzzzzzz)begin
        traced=traced+1;
        $display("DQ_WINDOW time_ns=%0.3f value=%h",$realtime,dram.Dq_reg);
    end
    integer sample_trace=0;
    always @(posedge dut.Clk)begin
        #0.001;
        if(dut.Sdr_rd_en && sample_trace<20)begin
            sample_trace=sample_trace+1;
            $display("QUALIFIED_READ time_ns=%0.3f value=%h",$realtime,dut.Sdr_rd_dout);
        end
    end
    integer pixels=0,frames=0,errors=0,z_words=0,refreshes=0,seed=1;
    integer seeds[0:1];
    reg [23:0] expected;
    always @(posedge dut.SDRAM_CLK)
        if({dut.SDR_RAS,dut.SDR_CAS,dut.SDR_WE}===3'b001)refreshes=refreshes+1;
    always @(posedge pix_clk)begin
        if(req && frame_ready)begin
            if(underflow || !valid)$fatal(1,"real IP pixel underflow xy=%0d,%0d",x,y);
            expected=(x<8 && y<4)?24'h100000+seeds[dut.front_base==128?0:1]*24'h10000+y*256+x:0;
            if(rgb!==expected)begin
                errors=errors+1;
                if(rgb===24'hzzzzzz)z_words=z_words+1;
                if(errors<5)$display("REAL_IP_MISMATCH phase_deg=%0d xy=%0d,%0d got=%h expected=%h",306,x,y,rgb,expected);
            end
            pixels=pixels+1;
            if(x==15 && y==7)frames=frames+1;
        end
        if(rst_n && dut.refresh_error)$fatal(1,"refresh watchdog");
    end
    task send_frame(input integer tag,td);
        integer k,row,b;
        wait(write_ready);b=dut.u_frame_buffers.bank_sync[1];seeds[b]=tag;
        @(negedge SYS_CLK);top_down=td;frame_start=1;
        @(negedge SYS_CLK);frame_start=0;
        for(k=0;k<32;k=k+1)begin
            @(negedge SYS_CLK);while(!ready)@(negedge SYS_CLK);
            row=td?k/8:3-k/8;pixel_valid=1;
            pixel_data=24'h100000+tag*24'h10000+row*256+k%8;
        end
        @(negedge SYS_CLK);pixel_valid=0;frame_end=1;
        @(negedge SYS_CLK);frame_end=0;
        wait(done);wait(write_ready);
    endtask
    initial begin





        #100;rst_n=1;wait(led);@(negedge pix_clk);pix_rst_n=1;
        send_frame(1,1);wait(frames>=2);
        send_frame(2,0);wait(frames>=4);
        if(errors!=0)$fatal(1,"production read errors=%0d",errors);
        if(clock_checks<100)$fatal(1,"PLL phase coverage missing");
        @(negedge SYS_CLK);rst_n=0;pix_rst_n=0;
        #103;rst_n=1;wait(led);@(negedge pix_clk);pix_rst_n=1;
        send_frame(3,1);wait(frames>=6);
        if(errors!=0)$fatal(1,"readback after PLL restart errors=%0d",errors);
        $display("PLL_RESTART_READBACK_PASS phase_checks=%0d",clock_checks);
        $display("PRODUCTION_PLL_READ_PASS phase_deg=%0d pixels=%0d frames=%0d errors=%0d z_words=%0d refreshes=%0d",306,pixels,frames,errors,z_words,refreshes);
        $finish;
    end
    initial begin #4000000;$fatal(1,"real IP timeout state=%0d done=%b",dut.u_reader.state,done);end
endmodule
