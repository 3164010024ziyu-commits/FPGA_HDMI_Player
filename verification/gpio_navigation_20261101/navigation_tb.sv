`timescale 1ns/1ps
module navigation_tb;
reg clk=0,rst=0,reload=0,prev=0,next=0;
always #10 clk=~clk;
wire start,pending,reported,select_last;wire [15:0] file_index,current;
reg done=0,error=0;reg [7:0] code=0;
integer countdown=0,launches=0,force_failure=0,last_launched=-1;
reg accept_enable=1,empty_card=0;
reg [15:0] last_available=2;
wire ready=accept_enable && countdown==0;
image_navigation_ctrl dut(.clk(clk),.reset_n(rst),.reload_press(reload),.previous_press(prev),.next_press(next),
.select_last(select_last),.opened_index(select_last ? last_available : file_index),.load_ready(ready),.load_done(done),.load_error(error),.load_error_code(code),.start(start),
.file_index(file_index),.current_index(current),.request_pending(pending),.report_load_error(reported));
always @(posedge clk)begin
done<=0;
if(!rst)begin countdown<=0;error<=0;code<=0;end
else if(start)begin
 if(!ready)$fatal(1,"request while busy");
 countdown<=12;launches=launches+1;last_launched=select_last ? last_available : file_index;error<=0;code<=0;
end else if(countdown>0)begin
 countdown<=countdown-1;
 if(countdown==5)begin
  if(empty_card || (!select_last && file_index>last_available))begin error<=1;code<=8'h36;end
  else if(force_failure)begin error<=1;code<=8'h21;end
  else done<=1;
 end
end
end
task cycles(input integer n);repeat(n)@(negedge clk);endtask
task press(input integer command);
begin @(negedge clk);reload=command==1;prev=command==2;next=command==3;@(negedge clk);reload=0;prev=0;next=0;end
endtask
task idle;
integer stable;
begin stable=0;while(stable<4)begin @(negedge clk);if(countdown==0 && !dut.in_flight && !pending)stable=stable+1;else stable=0;end end
endtask
integer saved;
initial begin
cycles(2);rst=1;
// Before the first image, NEXT opens image zero rather than skipping it.
press(3);idle();if(current!=0 || last_launched!=0)$fatal(1,"first navigation");
// Busy NEXT events must use the newly committed index, not the old index.
press(3);wait(countdown>0);press(3);idle();if(current!=2)$fatal(1,"busy next queue");
press(3);idle();if(current!=0 || reported)$fatal(1,"last to first wrap");
press(2);repeat(3)begin @(negedge clk);if(reported)$fatal(1,"stale boundary fault leaked");end
idle();if(current!=2 || reported)$fatal(1,"first to last wrap");
press(3);idle();if(current!=0)$fatal(1,"next wrap");
press(3);idle();if(current!=1)$fatal(1,"next failed");
force_failure=1;press(3);idle();if(current!=1 || !reported)$fatal(1,"failed load changed displayed index");
force_failure=0;press(3);idle();if(current!=2 || reported)$fatal(1,"recovery");
// simultaneous direction events cancel; reset discards queued work.
saved=launches;@(negedge clk);prev=1;next=1;cycles(1);prev=0;next=0;cycles(5);
if(launches!=saved)$fatal(1,"simultaneous keys");
accept_enable=0;press(3);cycles(5);if(!pending)$fatal(1,"busy queue lost");
rst=0;cycles(2);rst=1;accept_enable=1;cycles(8);
if(pending || current!=0 || launches!=saved)$fatal(1,"reset did not cancel request");
press(2);idle();if(current!=2)$fatal(1,"first previous must find last");
press(1);idle();if(current!=2 || last_launched!=2)$fatal(1,"reload must retain nonzero selection");
// With one image, both directions remain on zero. An empty card is an error.
rst=0;cycles(2);last_available=0;rst=1;
press(3);idle();press(3);idle();press(2);idle();
if(current!=0 || reported)$fatal(1,"single image circular navigation");
rst=0;cycles(2);empty_card=1;rst=1;press(2);idle();
if(!reported || code!=8'h36 || dut.image_loaded)$fatal(1,"empty card error was suppressed");
$display("NAVIGATION_PASS first_load=0 next_previous=1 busy_queue=1 circular_wrap=1 single_image=1 empty_error=1 failure_rollback=1 stale_error_filtered=1 simultaneous_ignore=1 reload_nonzero=1 reset=1");$finish;
end
initial begin #100000;$fatal(1,"navigation timeout current=%d state=%b",current,dut.in_flight);end
endmodule
