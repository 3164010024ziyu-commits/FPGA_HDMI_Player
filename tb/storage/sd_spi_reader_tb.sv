`timescale 1ns/1ps
module sd_spi_reader_tb;
    reg clk=0; always #10 clk=~clk;
    reg rst_n=0,req_valid=0,ready=0;
    reg [31:0] req_lba=7;
    wire cs,sck,mosi,miso,initialized,hc,req_ready,valid,last,done,error;
    wire [7:0] data,error_code;
    reg high_capacity=1,corrupt_crc=0,suppress_token=0,bad_token=0,bad_cmd8=0,suppress_response=0;
    integer reads,commands;
    sd_spi_reader #(.POWERUP_CYCLES(8),.INIT_HALF_PERIOD(3),.READ_HALF_PERIOD(1),
        .TOKEN_TIMEOUT_BYTES(16)) dut(
        .clk(clk),.rst_n(rst_n),.sd_cs_n(cs),.sd_sck(sck),.sd_mosi(mosi),.sd_miso(miso),
        .initialized(initialized),.high_capacity(hc),.req_valid(req_valid),.req_ready(req_ready),
        .req_lba(req_lba),.data(data),.valid(valid),.ready(ready),.last(last),.done(done),
        .error(error),.error_code(error_code));
    sd_spi_card_model card(.rst_n(rst_n),.cs_n(cs),.sck(sck),.mosi(mosi),.miso(miso),
        .high_capacity(high_capacity),.corrupt_crc(corrupt_crc),.suppress_token(suppress_token),
        .bad_token(bad_token),.bad_cmd8(bad_cmd8),.suppress_response(suppress_response),
        .reads(reads),.commands(commands));
    integer seen=0,cycles=0,cases=0;
    reg done_seen=0,error_seen=0,stalled=0,perf_mode=1;
    reg [8:0] held;
    reg [31:0] random_state=32'h6525ced8;
    always @(negedge clk) begin
        random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
        ready=perf_mode || random_state[0] || random_state[3];
    end
    always @(posedge clk) if(rst_n) begin
        cycles=cycles+1;
        if(cycles>2000000) $fatal(1,"SD watchdog");
        if(error) error_seen=1;
        if(done) done_seen=1;
        if(stalled && (!valid || {last,data}!==held)) $fatal(1,"SD stall instability");
        stalled=valid && !ready; held={last,data};
        if(valid && ready) begin
            if(data!==8'(7^seen) || last!==(seen==511)) $fatal(1,"SD byte %0d=%h",seen,data);
            seen=seen+1;
        end
    end
    task reset_card;
        begin
            @(negedge clk); rst_n=0; req_valid=0; seen=0; error_seen=0; done_seen=0; stalled=0;
            repeat(4) @(negedge clk); rst_n=1;
        end
    endtask
    task read_case(input integer expected_error);
        integer begin_cycle;
        begin
            cases=cases+1; seen=0; error_seen=0; done_seen=0;
            wait(req_ready); @(negedge clk); req_valid=1;
            begin_cycle=cycles;
            @(negedge clk); req_valid=0;
            wait(done_seen || error_seen);
            if(expected_error==0) begin
                if(error_seen || seen!=512) $fatal(1,"SD read failed code=%h seen=%0d",error_code,seen);
            end else if(error_code!=expected_error || seen!=0)
                $fatal(1,"SD error code=%h expected=%h published=%0d",error_code,expected_error,seen);
            if(perf_mode && expected_error==0)
                $display("SD no-stall CMD17 sector: %0d clocks, %.3f MB/s (model, 50 MHz)",
                         cycles-begin_cycle,512.0*50.0/(cycles-begin_cycle));
            repeat(4) @(negedge clk);
        end
    endtask
    initial begin
        reset_card(); wait(initialized); if(!hc) $fatal(1,"CCS");
        read_case(0); perf_mode=0; read_case(0);
        corrupt_crc=1; read_case('h09); corrupt_crc=0; read_case(0);
        suppress_token=1; read_case('h08); suppress_token=0;
        bad_token=1; read_case('h07); bad_token=0;
        high_capacity=0; reset_card(); wait(initialized); if(hc) $fatal(1,"SDSC CCS");
        read_case(0); // model checks CMD17 byte address and CMD16
        bad_cmd8=1; reset_card(); wait(error_seen);
        if(error_code!='h02 || initialized) $fatal(1,"CMD8 failure"); cases=cases+1;
        bad_cmd8=0; suppress_response=1; reset_card(); wait(error_seen);
        if(error_code!='h0b || initialized) $fatal(1,"R1 timeout"); cases=cases+1;
        $display("PASS sd_spi_reader: %0d cases, SDHC/SDSC, CRC rejection, timeouts, recovery",cases);
        $finish;
    end
endmodule
