`timescale 1ns/1ps
module writer_address_tb;
    parameter EXPECT_ERRORS=4;
    reg Clk=0; always #4 Clk=~Clk;
    reg Reset_n=1,wr_en=0,dst_valid=0,top_down=1,pending=0;
    reg [31:0] wr_data=0;
    reg [20:0] base=100;
    reg [15:0] width=4,height=2;
    wire full,empty,rd_en,rd_valid,app_en;
    wire [31:0] rd_data,app_data;
    wire [20:0] app_addr;
    wire [3:0] app_dm;
    sync_fifo #(.DATA_WIDTH(32),.ADDR_WIDTH(4)) fifo(
        .Clk(Clk),.Reset_n(Reset_n),.wr_en(wr_en),.wr_data(wr_data),.full(full),
        .rd_en(rd_en),.rd_data(rd_data),.rd_valid(rd_valid),.empty(empty));
    sdram_write_ctrl writer(
        .Clk(Clk),.Reset_n(Reset_n),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),.Sdr_refresh_pending(pending),.Sdr_busy(1'b0),
        .dst_valid(dst_valid),.dst_base_addr(base),.dst_width(width),.dst_height(height),.dst_top_down(top_down),
        .fifo_rd_data(rd_data),.fifo_rd_valid(rd_valid),.fifo_empty(empty),.fifo_rd_en(rd_en),
        .App_wr_en(app_en),.App_wr_addr(app_addr),.App_wr_din(app_data),.App_wr_dm(app_dm));
    integer seen=0,case_id=0,errors=0,total_errors=0,cases=0;
    integer logical_y,expected_addr;
    reg [20:0] actual[0:7];
    always @(posedge Clk) if(Reset_n && app_en) begin
        if(seen>=8) $fatal(1,"ADDRESS_DIAG unexpected extra word");
        if(app_data!==(32'hda710000^seen) || app_dm!==0) $fatal(1,"ADDRESS_DIAG unexpected data/mask");
        logical_y=top_down ? seen/width : height-1-seen/width;
        expected_addr=100+logical_y*width+seen%width;
        actual[seen]=app_addr;
        if(app_addr!==21'(expected_addr)) errors=errors+1;
        $display("ADDRESS_TRACE case=%0d word=%0d data=%h actual=%0d expected=%0d",case_id,seen,app_data,app_addr,expected_addr);
        seen=seen+1;
    end
    task run_case(input integer which,input bit direction,input bit refresh_hold);
        begin
            @(negedge Clk); #1;
            Reset_n=0;wr_en=0;dst_valid=0;pending=refresh_hold;top_down=direction;
            repeat(3) @(negedge Clk);#1;
            Reset_n=1;seen=0;errors=0;case_id=which;
            @(negedge Clk);#1;dst_valid=1;
            @(negedge Clk);#1;dst_valid=0;
            for(integer n=0;n<8;n=n+1) begin
                @(negedge Clk);#1;wr_en=1;wr_data=32'hda710000^n;
            end
            @(negedge Clk);#1;wr_en=0;
            if(refresh_hold) begin
                repeat(20) @(negedge Clk);#1;
                if(seen!=0 || writer.recv_cnt!=4) $fatal(1,"ADDRESS_DIAG refresh hold failed");
                pending=0;
                wait(seen==1);@(negedge Clk);#1;pending=1;
                repeat(20) @(negedge Clk);#1;
                if(seen!=4 || writer.recv_cnt!=4) $fatal(1,"ADDRESS_DIAG active group interrupted or next not held");
                pending=0;
            end
            wait(seen==8); repeat(8) @(negedge Clk);#1;
            if(errors!=EXPECT_ERRORS || !empty || (EXPECT_ERRORS!=0 && actual[3]!==actual[4]))
                $fatal(1,"ADDRESS_DIAG expected=%0d actual=%0d",EXPECT_ERRORS,errors);
            total_errors=total_errors+errors;cases=cases+1;
            $display("ADDRESS_CASE_RESULT case=%0d top_down=%b words=8 address_errors=%0d boundary_prev=%0d boundary_next=%0d refresh_hold=%b",which,top_down,errors,actual[3],actual[4],refresh_hold);
        end
    endtask
    initial begin
        #1;Reset_n=0;
        run_case(0,1,0);
        run_case(1,0,0);
        run_case(2,1,1);
        $display("ADDRESS_DIAG_COMPLETE syntax_only_copy=1 cases=%0d data_words_checked=24 address_errors=%0d",cases,total_errors);
        $finish;
    end
    initial begin #30000;$fatal(1,"ADDRESS_DIAG watchdog");end
endmodule
