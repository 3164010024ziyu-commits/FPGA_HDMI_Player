`timescale 1ns/1ps
module hx4s20c_storage_bringup_tb;
    reg clk=0; always #10 clk=~clk;
    reg reset_key_n=0;
    wire sd_cs_n,sd_sck,sd_mosi,sd_miso;
    wire [3:0] led;
    reg corrupt_crc=0;
    integer reads,commands,cycles=0,cases=0;
    hx4s20c_storage_bringup dut(.*);
    sd_spi_card_model card(.rst_n(reset_key_n),.cs_n(sd_cs_n),.sck(sd_sck),
        .mosi(sd_mosi),.miso(sd_miso),.high_capacity(1'b1),.corrupt_crc(corrupt_crc),
        .suppress_token(1'b0),.bad_token(1'b0),.bad_cmd8(1'b0),
        .suppress_response(1'b0),.reads(reads),.commands(commands));
    always @(posedge clk) begin
        cycles=cycles+1;
        if(cycles>3000000) $fatal(1,"board top watchdog");
    end
    task run_case(input integer expected_error);
        begin
            cases=cases+1;
            @(negedge clk); reset_key_n=0;
            repeat(5) @(negedge clk); reset_key_n=1;
            wait(led[2] || led[3]); repeat(5) @(negedge clk);
            if(expected_error==0) begin
                if(led!==4'b0101 || dut.pixel_count!=391 || dut.expected_pixels!=391 ||
                   dut.rgb_sum!=32'he091921d) // independent Python sum of the fixture's RGB pixels
                    $fatal(1,"board success led=%b count=%0d sum=%h",led,dut.pixel_count,dut.rgb_sum);
            end else if(!led[3] || led[2] || dut.debug_error_code!=expected_error)
                $fatal(1,"board error %h expected %h",dut.debug_error_code,expected_error);
        end
    endtask
    initial begin
        run_case(0);
        corrupt_crc=1; run_case('h09); corrupt_crc=0;
        card.card[3072]=0; run_case('h20); card.card[3072]="B";
        run_case(0);
        $display("PASS hx4s20c_storage_bringup: %0d board-wrapper cases",cases);
        $finish;
    end
endmodule
