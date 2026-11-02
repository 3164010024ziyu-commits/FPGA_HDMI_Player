`timescale 1ns/1ps
module fade_control_tb;
reg clk=0,rst=0,dst=0,done=0,blank=0,reading=0,abort_frame=0;
always #5 clk=~clk;
wire [4:0] level;wire valid,ready;wire [20:0] base;
frame_buffer_ctrl #(.ENABLE_FADE(1)) dut(
 .sys_clk(clk),.sys_rst_n(rst),.initialized(1'b1),.frame_start(1'b0),.frame_end(1'b0),.frame_abort(abort_frame),
 .frame_base_addr(21'd0),.frame_width(16'd16),.frame_height(16'd8),.desc_ready(1'b1),.frame_write_ready(ready),
 .mem_clk(clk),.mem_rst_n(rst),.dst_valid(dst),.dst_base(21'd307200),.dst_width(16'd16),.dst_height(16'd8),
 .writer_done(done),.write_owned(1'b0),.read_active(reading),.blank_flush(blank),.fade_step(level),.front_valid(valid),.front_base(base));
task cycles(input integer n);repeat(n)@(negedge clk);endtask
task load;begin dst=1;cycles(1);dst=0;cycles(2);done=1;cycles(1);done=0;cycles(2);end endtask
task frame(input integer wanted);begin
 blank=1;cycles(20);if(level!==wanted)$fatal(1,"fade advanced more than once per long blank want=%d got=%d",wanted,level);
 blank=0;cycles(10);
end endtask
integer i;
initial begin
 cycles(2);rst=1;cycles(6);load();frame(0);if(!valid)$fatal(1,"first frame not swapped");
 for(i=1;i<=16;i=i+1)frame(i);
 cycles(5);if(!ready)$fatal(1,"ready after initial fade");
 load();reading=1;
 for(i=15;i>=0;i=i-1)begin frame(i);if(!dut.pending_frame)$fatal(1,"swapped during active read or before black");end
 reading=0;blank=1;cycles(3);if(dut.pending_frame || level!=0)$fatal(1,"black swap missing");blank=0;cycles(3);
 for(i=1;i<=16;i=i+1)begin frame(i);if(i<16 && ready)$fatal(1,"ready before fade-in drained");end
 // A discarded back frame must restore the existing front image.
 load();frame(15);frame(14);abort_frame=1;cycles(1);abort_frame=0;cycles(30);
 if(dut.pending_frame)$fatal(1,"abort retained back frame");frame(15);frame(16);
 rst=0;cycles(2);if(valid || level!=16)$fatal(1,"fade reset");
 $display("FADE_CONTROL_PASS steps_per_half=16 long_blank_once=1 swap_at_black=1 read_drain=1 ready_after_fade=1 abort_restore=1 reset=1");$finish;
end
initial begin #100000;$fatal(1,"fade watchdog");end
endmodule
