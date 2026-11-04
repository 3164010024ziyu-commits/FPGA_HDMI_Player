`timescale 1ns/1ps
module writer_address_matrix_tb;
    reg Clk=0;always #4 Clk=~Clk;
    reg rst_n=0,valid=0,wr_en=0,pending=0;
    reg [20:0] base=0;
    reg [15:0] width=0,height=0;
    reg top_down=1;
    reg [31:0] wr_data=0;
    wire full,empty,rd_en,rd_valid,app_en,done;
    wire [31:0] rd_data,app_data;
    wire [20:0] app_addr;
    wire [3:0] dm;
    sync_fifo #(.DATA_WIDTH(32),.ADDR_WIDTH(4)) fifo(
        .Clk(Clk),.Reset_n(rst_n),.wr_en(wr_en),.wr_data(wr_data),.full(full),
        .rd_en(rd_en),.rd_data(rd_data),.rd_valid(rd_valid),.empty(empty));
    sdram_write_ctrl dut(
        .Clk(Clk),.Reset_n(rst_n),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),
        .Sdr_refresh_pending(pending),.Sdr_busy(1'b0),
        .dst_valid(valid),.dst_base_addr(base),.dst_width(width),.dst_height(height),.dst_top_down(top_down),
        .frame_write_done(done),.fifo_rd_data(rd_data),.fifo_rd_valid(rd_valid),.fifo_empty(empty),.fifo_rd_en(rd_en),
        .App_wr_en(app_en),.write_request(),.App_wr_addr(app_addr),.App_wr_din(app_data),.App_wr_dm(dm));
    integer cases=0,words=0,seen=0,expected_words=0,tag=0,run_length=0;
    integer row,expected_address,total_stalls=0,pending_groups=0;
    reg checking=0;
    function [31:0] pattern(input integer seed,index);
        pattern=32'h513ce742 ^ (seed*32'h10203041) ^ index;
    endfunction
    always @(posedge Clk)if(rst_n)begin
        if(app_en)begin
            if(!checking || !dut.address_ready || seen>=expected_words)$fatal(1,"unexpected write");
            row=top_down?seen/width:height-1-seen/width;
            expected_address=(base+row*width+seen%width)&21'h1fffff;
            if(app_addr!==21'(expected_address) || app_data!==pattern(tag,seen) || dm!==0)
                $fatal(1,"matrix case=%0d index=%0d xy=%0d,%0d addr=%0d expected=%0d data=%h",cases,seen,seen%width,seen/width,app_addr,expected_address,app_data);
            if(pending)pending_groups=pending_groups+1;
            seen=seen+1;words=words+1;run_length=run_length+1;
        end else if(run_length!=0)begin
            if(run_length!=4)$fatal(1,"truncated write group");run_length=0;
        end
        if(checking && done && seen<expected_words && !valid)$fatal(1,"premature completion");
    end
    task frame(input integer w,h,td);
        integer k;
        @(negedge Clk);width=w;height=h;top_down=td;
        base=21'((cases*16384+128)&21'h1ffffc);
        if(base+w*h>2097152)base=128;
        tag=cases+1;expected_words=w*h;seen=0;valid=1;checking=1;
        @(negedge Clk);valid=0;
        for(k=0;k<expected_words;k=k+1)begin
            while(full || $urandom_range(0,3)==0)begin
                wr_en=0;pending=$urandom_range(0,5)==0;total_stalls=total_stalls+1;@(negedge Clk);
            end
            wr_en=1;wr_data=pattern(tag,k);pending=$urandom_range(0,4)==0;
            @(negedge Clk);
        end
        wr_en=0;pending=0;wait(done);@(negedge Clk);
        if(seen!=expected_words || !empty)$fatal(1,"frame did not drain");
        checking=0;cases=cases+1;
    endtask
    integer widths[0:6]='{4,8,12,16,20,64,640};
    integer heights[0:5]='{1,2,3,7,16,480};
    initial begin
        #1;rst_n=0;repeat(4)@(negedge Clk);rst_n=1;
        repeat(8)@(negedge Clk);
        if(done || app_en)$fatal(1,"activity without descriptor");
        for(integer w=0;w<7;w=w+1)
            for(integer h=0;h<6;h=h+1)begin frame(widths[w],heights[h],1);frame(widths[w],heights[h],0);end
        if(pending_groups==0)$fatal(1,"no in-group refresh-pending coverage");
        $display("WRITER_ADDRESS_MATRIX_PASS cases=%0d words=%0d stalls=%0d in_group_pending_beats=%0d",cases,words,total_stalls,pending_groups);
        $finish;
    end
    initial begin #100000000;$fatal(1,"matrix timeout cases=%0d seen=%0d",cases,seen);end
endmodule
