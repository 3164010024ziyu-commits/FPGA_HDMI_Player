`timescale 1ns/1ps
module last_storage_tb;
    reg clk=0; always #10 clk=~clk;
    reg rst_n=0,start=0;
    reg [15:0] file_index=0;wire [15:0] opened_index;
    wire cs,sck,mosi,miso,ready,busy,card_initialized,done,error,meta_valid,top_down;
    wire [7:0] error_code;
    wire [87:0] short_name;
    wire [31:0] file_size,addr;
    wire [15:0] width,height,px,py,rgb565;
    wire [23:0] rgb;
    wire pixel_valid,sof,eol,eof;
    reg pixel_ready=0;
    reg high_capacity=1,corrupt_crc=0;
    integer reads,commands;
    storage_pipeline #(.INIT_HALF_PERIOD(3),.MAX_WIDTH(64),.MAX_HEIGHT(64)) dut(
        .clk(clk),.rst_n(rst_n),.sd_cs_n(cs),.sd_sck(sck),.sd_mosi(mosi),.sd_miso(miso),
        .start(start),.file_index(file_index),.select_last(1'b1),.opened_index(opened_index),.ready(ready),.busy(busy),
        .card_initialized(card_initialized),.done(done),.error(error),.error_code(error_code),
        .short_name(short_name),.file_size(file_size),.meta_valid(meta_valid),
        .width(width),.height(height),.top_down(top_down),.pixel_valid(pixel_valid),
        .pixel_ready(pixel_ready),.pixel_rgb888(rgb),.pixel_rgb565(rgb565),
        .pixel_x(px),.pixel_y(py),.pixel_addr(addr),.pixel_sof(sof),.pixel_eol(eol),.pixel_eof(eof));
    sd_spi_card_model card(.rst_n(rst_n),.cs_n(cs),.sck(sck),.mosi(mosi),.miso(miso),
        .high_capacity(high_capacity),.corrupt_crc(corrupt_crc),.suppress_token(1'b0),
        .bad_token(1'b0),.bad_cmd8(1'b0),.suppress_response(1'b0),.reads(reads),.commands(commands));
    integer seen=0,cycles=0,cases=0,stall_count=0,launch_cycle;
    reg done_seen=0,inject_late_crc=0;
    reg [31:0] random_state=32'hf579d134;
    reg [23:0] expected_rgb;
    always @(negedge clk) begin
        random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
        if(seen==180 && stall_count<1000) begin pixel_ready=0; stall_count=stall_count+1; end
        else pixel_ready=random_state[0] || random_state[4];
        if(inject_late_crc && seen>=180) corrupt_crc=1;
    end
    always @(posedge clk) if(rst_n) begin
        cycles=cycles+1;
        if(cycles>4000000) $fatal(1,"pipeline watchdog");
        if(meta_valid && (width!=17 || height!=23 || top_down)) $fatal(1,"pipeline metadata");
        if(pixel_valid && pixel_ready) begin
            expected_rgb={8'(8'h80+seen/17+seen%17),8'(seen%17),8'(8'h30+seen/17)};
            if(rgb!==expected_rgb || px!==16'(seen%17) || py!==16'(22-seen/17) ||
               addr!==32'((22-seen/17)*17+seen%17) ||
               sof!==(seen==0) || eol!==(seen%17==16) || eof!==(seen==390))
                $fatal(1,"pipeline pixel %0d rgb=%h",seen,rgb);
            seen=seen+1;
        end
        if(done) done_seen=1;
    end
    task run_case(input integer idx,expected_error);
        begin
            cases=cases+1; seen=0; done_seen=0; stall_count=0;
            wait(ready); @(negedge clk); start=1; file_index=idx; launch_cycle=cycles;
            @(negedge clk); start=0;
            wait(!busy); repeat(3) @(negedge clk);
            if(expected_error==0) begin
                if(error || !done_seen || seen!=391) $fatal(1,"pipeline failed code=%h pixels=%0d",error_code,seen);
                $display("Pipeline successful frame: %0d system clocks including stalls",cycles-launch_cycle);
            end else if(!error || error_code!=expected_error || done_seen)
                $fatal(1,"pipeline error expected=%h actual=%h done=%b",expected_error,error_code,done_seen);
        end
    endtask
    task reload;
        begin $readmemh("tb/storage/vectors/card.hex",card.card);end
    endtask
    task partial_collision;
        begin card.card[11]=0;card.card[12]=2;card.card[13]=1;end
    endtask
    task checked_case(input [8*64-1:0] label,input integer expected_error,expected_reads);
        integer before_reads;
        begin
            before_reads=reads;run_case(0,expected_error);
            if(reads-before_reads!=expected_reads) $fatal(1,"MBR_PIN_FAIL case=%0s reads=%0d expected=%0d",label,reads-before_reads,expected_reads);
            $display("MBR_PIN_CASE_PASS case=%0d name=%0s pixels=%0d reads=%0d error=%h",cases,label,seen,reads-before_reads,error_code);
        end
    endtask
    always @(posedge clk)if(meta_valid && opened_index!=1)$fatal(1,"last SPI index feedback");
    initial begin
        repeat(4) @(negedge clk);rst_n=1;
        checked_case("normal_mbr",0,10);
        reload();partial_collision();
        checked_case("partial_bpb_collision",0,10);
        reload();for(integer n=0;n<64;n=n+1) card.card[n]=card.card[512+n];
        card.card[32]=0;card.card[33]=0;card.card[34]=1;card.card[35]=0;
        checked_case("geometry_collision",0,10);
        reload();for(integer n=0;n<512;n=n+1) card.card[n]=card.card[512+n];
        card.card[14]='h20;card.card[15]='h08;
        card.card[32]='h40;card.card[33]='h1e;card.card[34]=1;card.card[35]=0;
        card.card[450]='h0c;card.card[454]=0;card.card[455]='h10;card.card[458]=0;card.card[459]=4;
        checked_case("valid_superfloppy_with_fake_mbr",0,9);
        reload();partial_collision();card.card[512+13]=3;
        checked_case("bad_partition_stops_after_fallback",'h34,2);
        reload();checked_case("successful_retry_after_error",0,10);
        $display("LAST_STORAGE_SPI_PASS cases=%0d",cases);
        $finish;
    end
endmodule
