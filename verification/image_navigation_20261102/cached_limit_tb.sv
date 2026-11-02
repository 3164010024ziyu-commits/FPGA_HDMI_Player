`timescale 1ns/1ps
module cached_limit_tb;
reg clk=0,rst=0,reload=0,prev=0,next=0;always #10 clk=~clk;
wire start,pending,reported,select_last;wire [15:0] target,current;
reg done=0,error=0;reg [7:0] code=0;reg [15:0] last_available=1;
integer remaining=0,reads=0;wire ready=remaining==0;
image_navigation_ctrl dut(.clk(clk),.reset_n(rst),.reload_press(reload),.previous_press(prev),.next_press(next),
 .load_ready(ready),.load_done(done),.load_error(error),.load_error_code(code),
 .opened_index(select_last?last_available:target),.start(start),.select_last(select_last),
 .file_index(target),.current_index(current),.request_pending(pending),.report_load_error(reported));
always @(posedge clk)begin
 done<=0;
 if(!rst)begin remaining<=0;error<=0;code<=0;end
 else if(start)begin remaining<=12;reads=reads+1;error<=0;code<=0;end
 else if(remaining>0)begin
  remaining<=remaining-1;
  if(remaining==5)begin
   if(!select_last && target>last_available)begin error<=1;code<=8'h36;end
   else done<=1;
  end
 end
end
task press(input integer previous,wanted);
integer stable;
begin
 @(negedge clk);prev=previous;next=!previous;@(negedge clk);prev=0;next=0;
 stable=0;while(stable<5)begin @(negedge clk);if(!dut.in_flight && !pending && ready)stable=stable+1;else stable=0;end
 $display("CACHE_RESULT available=%0d current=%0d expected=%0d storage_queries=%0d",last_available+1,current,wanted,reads);
 if(current!=wanted || reported)$fatal(1,"cached boundary caused wrong image: current=%d expected=%d",current,wanted);
end endtask
initial begin
 repeat(2)@(negedge clk);rst=1;
 press(0,0);press(0,1);press(0,0);
 // Directory becomes longer after an earlier observed end. The previous end
 // must not become a permanent limit. No electrical hotplug is modeled here.
 last_available=5;
 press(0,1);press(0,2);press(0,3);press(0,4);press(0,5);press(0,0);
 // A first-to-last operation must use the directory currently present, too.
 last_available=1;press(1,1);press(0,0);
 last_available=5;press(1,5);
 $display("CACHED_LIMIT_FIX_PASS initial_two=1 grows_to_six=1 shrinks_to_two=1 previous_rescans=1");$finish;
end
initial begin #100000;$fatal(1,"cache regression watchdog");end
endmodule
