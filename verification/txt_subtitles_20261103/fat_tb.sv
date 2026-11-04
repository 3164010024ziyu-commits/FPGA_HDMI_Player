`timescale 1ns/1ps
module caption_fat_tb;
 reg clk=0;always #10 clk=~clk;reg rst_n=0,start=0,select_last=0;
 reg [15:0]file_index=0;reg [1:0]aux_kind=0;reg [31:0]aux_offset=0;reg [15:0]aux_length=0;
 wire busy,done,error,file_open,valid,last,req_valid,sec_ready;
 wire [7:0]error_code,data;wire [31:0]file_size,req_lba;wire [87:0]short_name;wire [15:0]opened_index;
 reg ready=1,req_ready=1,sec_valid=0,sec_last=0,sec_error=0;reg [7:0]sec_data=0;
 wire [63:0] match_name=64'd0;
 fat32_bmp_reader #(.ENABLE_AUX(1)) dut(.*);
 `include "virtual_card.svh"
 integer pending=0,lba=0,pos=0,seen=0,requests=0,cycles=0,cases=0,expected_offset=0,expected_length=0;
 reg stalled=0;reg [8:0]held;
 always @(negedge clk)begin
  ready=cycles%7!=0 && cycles%11!=0;req_ready=!pending;sec_valid=0;sec_last=0;
  if(pending && cycles%5!=0)begin sec_valid=1;sec_data=card_byte(lba,pos);sec_last=pos==511;end
 end
 always @(posedge clk)begin
  cycles=cycles+1;if(cycles>5000000)$fatal(1,"FAT aux watchdog");
  if(!rst_n)begin pending=0;stalled=0;end else begin
   if(req_valid && req_ready)begin lba=req_lba;pos=0;pending=1;requests=requests+1;end
   if(sec_valid && sec_ready)begin if(sec_last)pending=0;else pos=pos+1;end
   if(stalled && (!valid || {last,data}!==held))$fatal(1,"aux stall instability");
   stalled=valid && !ready;held={last,data};
   if(valid && ready)begin
    if(data!==payload(expected_offset+seen) || last!==(seen==expected_length-1))
     $fatal(1,"range mismatch offset=%h byte=%0d got=%h want=%h last=%b",expected_offset,seen,data,payload(expected_offset+seen),last);
    seen=seen+1;
   end
  end
 end
 task reset;
  begin @(negedge clk);rst_n=0;repeat(3)@(negedge clk);rst_n=1;repeat(3)@(negedge clk);end
 endtask
 task test_range(input integer off,len,expected_error);
  begin
   @(negedge clk);aux_kind=2;aux_offset=off;aux_length=len;expected_offset=off;
   expected_length=off+len>32'h2200000 ? 32'h2200000-off:len;seen=0;requests=0;start=1;
   @(negedge clk);start=0;wait(done || error);
   if(expected_error==0)begin if(error || seen!=expected_length)$fatal(1,"range failed off=%h seen=%0d code=%h",off,seen,error_code);end
   else if(!error || error_code!=expected_error)$fatal(1,"expected range error %h got %h",expected_error,error_code);
   repeat(4)@(negedge clk);cases=cases+1;$display("FAT_AUX_CASE_PASS case=%0d offset=%h bytes=%0d sectors=%0d error=%h",cases,off,seen,requests,error_code);
  end
 endtask
 initial begin
  reset();test_range(0,32,0);test_range('h4e2d*32,32,0);test_range('h20bb7*32,32,0);
  test_range('h10ffff*32,32,0);test_range(511,32,0);test_range(65520,32,0);
  test_range('h21ffff0,32,0);test_range('h2200000,32,'h37);test_range(0,0,'h37);
  reset();missing_font=1;test_range(0,32,'h36);missing_font=0;
  reset();bad_link=1;test_range(65536,32,'h38);bad_link=0;
  $display("CAPTION_FAT_PASS cases=%0d fragmented=1 unicode_max=1 sector_crossing=1 cluster_crossing=1 stalls=1",cases);$finish;
 end
endmodule
