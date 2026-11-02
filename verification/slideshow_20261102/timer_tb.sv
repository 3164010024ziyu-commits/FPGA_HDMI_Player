`timescale 1ns/1ps
module timer_tb;
reg clk=0,rst=0,toggle=0,manual=0,ready=1,loaded=1;
always #10 clk=~clk;
wire enabled,next;
slideshow_ctrl #(.INTERVAL_CYCLES(16)) dut(clk,rst,toggle,manual,ready,loaded,enabled,next);
task step;begin @(posedge clk);#1;end endtask
task toggle_key;begin @(negedge clk);toggle=1;step();@(negedge clk);toggle=0;end endtask
integer i;
initial begin
 step();rst=1;repeat(25)begin step();if(next || enabled)$fatal(1,"timer auto-started");end
 toggle_key();
 for(i=1;i<=16;i=i+1)begin step();if(next!==(i==16))$fatal(1,"timer period/off-by-one i=%d pulse=%b",i,next);end
 repeat(50)begin step();if(next)$fatal(1,"repeated request before busy ack");end
 ready=0;repeat(50)begin step();if(next)$fatal(1,"busy accumulated request");end
 ready=1;repeat(8)step();manual=1;step();manual=0;
 for(i=1;i<=16;i=i+1)begin step();if(next!==(i==16))$fatal(1,"manual did not restart period");end
 ready=0;step();ready=1;
 toggle_key();repeat(40)begin step();if(next || enabled)$fatal(1,"stop failed");end
 loaded=0;toggle_key();step();if(!next)$fatal(1,"enable without image must load index zero");
 repeat(20)begin step();if(next)$fatal(1,"first image request repeated");end
 // Failed initial load (still no image) must not hammer Storage immediately.
 ready=0;step();ready=1;
 for(i=1;i<=16;i=i+1)begin step();if(next!==(i==16))$fatal(1,"failed startup bypassed retry interval");end
 rst=0;step();if(enabled || next)$fatal(1,"reset did not stop timer");
 $display("SLIDESHOW_TIMER_PASS exact_interval=1 busy_no_queue=1 manual_restart=1 toggle_stop=1 initial_load=1 failed_startup_retry_interval=1 reset=1");$finish;
end
endmodule
