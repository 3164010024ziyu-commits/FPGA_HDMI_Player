`timescale 1ns/1ps
module storage_pipeline_tb;
    reg clk=0; always #10 clk=~clk;
    reg rst_n=0,start=0;
    reg [15:0] file_index=1;
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
        .start(start),.file_index(file_index),.ready(ready),.busy(busy),
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
    initial begin
        repeat(4) @(negedge clk); rst_n=1;
        run_case(1,0);
        run_case(2,'h36); // nonexistent file
        card.card[6*512]=0; run_case(0,'h20); card.card[6*512]="B";
        corrupt_crc=1; run_case(0,'h09); corrupt_crc=0;
        inject_late_crc=1; run_case(0,'h09); inject_late_crc=0; corrupt_crc=0;
        if(seen==0) $fatal(1,"late CRC test did not exercise a partial frame");
        run_case(0,0); // recover without resetting the SD card
        $display("PASS storage_pipeline: %0d pin-level end-to-end cases",cases);
        $finish;
    end
endmodule
