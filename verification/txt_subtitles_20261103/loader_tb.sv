`timescale 1ns/1ps
module caption_loader_tb;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,start=0,cache_ready=1;
 wire done,job_start,ready,glyph_we,commit,has_text;
 wire [1:0]job_kind;wire [31:0]job_offset;wire [15:0]job_length,glyph_data;
 wire [9:0]glyph_addr;wire [6:0]length;wire [7:0]status;
 reg file_done=0,file_error=0,valid=0;reg [7:0]file_code=0,data=0;
 text_caption_loader dut(.*);
 reg [7:0]bytes[0:1023];reg [20:0]expected[0:63];
 integer n=0,count=0,idx=0,active=0,pos=0,total=0,jobs=0,writes=0,cases=0;
 integer mode=0,expected_status=0,expected_text=1,commits=0,cycles=0;
 reg [31:0]font_cp=0;reg sticky_error=0;
 function [15:0] rowbits(input integer cp,input integer rownum);
  rowbits=(cp*73)^(rownum*173)^16'h81a5;
 endfunction
 always @(negedge clk)begin
  valid=0;file_done=0;file_error=sticky_error;
  if(active==3)begin file_error=1;sticky_error=1;file_code='h36;active=0;end
  else if(active!=0)begin
   if(pos==total)begin file_done=1;active=0;end
   else if(ready && cycles%5!=0)begin
    valid=1;
    if(active==1)data=bytes[pos];
    else data=pos%2==0 ? (rowbits(font_cp,pos/2)>>8) : rowbits(font_cp,pos/2);
   end
  end
 end
 always @(posedge clk)begin
  cycles=cycles+1;if(cycles>250000)$fatal(1,"loader watchdog");
  if(valid && ready)pos=pos+1;
  if(job_start)begin
   sticky_error=0;
   jobs=jobs+1;
   if(job_kind==1)begin
    if(job_offset!=0 || job_length!=512)$fatal(1,"TXT request");
    if(mode==1)active=3;
    else begin active=1;pos=0;total=n;end
   end else begin
    if(idx>=count || job_kind!=2 || job_offset!=={6'd0,expected[idx],5'd0} || job_length!=32)
     $fatal(1,"font request case=%0d idx=%0d offset=%h expected=%h",cases,idx,job_offset,expected[idx]*32);
    font_cp=expected[idx];idx=idx+1;
    if(mode==2)active=3;
    else begin active=2;pos=0;total=mode==3 ? 30:32;end
   end
  end
  if(glyph_we)begin
   if(glyph_addr!==(writes%16+16*(writes/16)) || glyph_data!==rowbits(expected[writes/16],writes%16))
    $fatal(1,"glyph row ordering case=%0d write=%0d addr=%d data=%h",cases,writes,glyph_addr,glyph_data);
   writes=writes+1;
  end
  if(commit)begin
   commits=commits+1;
   if(!cache_ready || length!=count || has_text!==expected_text || status!==expected_status)
    $fatal(1,"commit case=%0d len=%d/%0d text=%b status=%h/%h",cases,length,count,has_text,status,expected_status);
  end
 end
 task run_case;
  begin
   @(negedge clk);start=1;idx=0;jobs=0;writes=0;commits=0;
   @(negedge clk);start=0;
   wait(done);@(negedge clk);
   if(commits!=1 || (expected_text && (idx!=count || writes!=16*count)))$fatal(1,"incomplete loader case");
   cases=cases+1;$display("LOADER_CASE_PASS case=%0d chars=%0d writes=%0d status=%h",cases,count,writes,status);
   repeat(3)@(negedge clk);
  end
 endtask
 task text_byte(input [7:0]b);begin bytes[n]=b;n=n+1;end endtask
 initial begin
  repeat(3)@(negedge clk);rst_n=1;
  // UTF-8 BOM, ASCII, Chinese, supplementary-plane Han, CRLF, TAB.
  n=0;count=7;
  text_byte('hef);text_byte('hbb);text_byte('hbf);text_byte("A");
  text_byte('he4);text_byte('hb8);text_byte('had);
  text_byte('hf0);text_byte('ha0);text_byte('hae);text_byte('hb7);
  text_byte(13);text_byte(10);text_byte("B");text_byte(9);text_byte("C");
  expected[0]=65;expected[1]='h4e2d;expected[2]='h20bb7;expected[3]=32;expected[4]=66;expected[5]=32;expected[6]=67;
  run_case();
  n=0;count=3;expected_status='h91;text_byte('he4);text_byte("X");text_byte('he4);text_byte('hb8);
  expected[0]='hfffd;expected[1]=88;expected[2]='hfffd;run_case();
  n=0;count=5;text_byte('he0);text_byte('h80);text_byte('h80);text_byte('hed);text_byte('ha0);text_byte('h80);
  text_byte('hf4);text_byte('h90);text_byte('h80);text_byte('h80);text_byte('hc0);text_byte('haf);
  for(integer k=0;k<5;k=k+1)expected[k]='hfffd;run_case();
  n=90;count=64;expected_status=0;
  for(integer k=0;k<90;k=k+1)bytes[k]=65+k%26;
  for(integer k=0;k<64;k=k+1)expected[k]=65+k%26;run_case();
  n=0;count=0;expected_text=0;run_case();
  n=1;bytes[0]=65;count=0;mode=1;expected_status='h90;run_case();
  count=1;expected[0]=65;mode=2;expected_status='h92;run_case();
  mode=3;expected_status='h93;run_case();
  // A new request must wait for the display's inactive-bank acknowledgement.
  mode=0;expected_status=0;expected_text=1;cache_ready=0;
  fork begin repeat(35)@(negedge clk);if(job_start)$fatal(1,"busy cache bypass");cache_ready=1;end
       run_case();join
  sticky_error=1;file_code='h36;run_case();
  $display("CAPTION_LOADER_PASS cases=%0d",cases);$finish;
 end
endmodule
