// Prefetch before the five-second deadline; release a prepared transition on
// the deadline. Actual video-transition events anchor the next interval.
module av_slideshow_ctrl #(
 parameter INTERVAL_CYCLES=250000000,PRELOAD_CYCLES=100000000,AUDIO_LEAD_CYCLES=500000
)(
 input wire clk,reset_n,toggle_press,manual_press,can_advance,image_loaded,transition_start,
 output reg enabled,output reg next_press,output wire hold_presentation,output wire audio_prepare_window
);
 localparam BITS=INTERVAL_CYCLES>1?$clog2(INTERVAL_CYCLES+1):1;
 localparam LEAD=PRELOAD_CYCLES<INTERVAL_CYCLES ? PRELOAD_CYCLES : INTERVAL_CYCLES/2;
 localparam THRESHOLD=INTERVAL_CYCLES-LEAD;
 localparam AUDIO_LEAD=AUDIO_LEAD_CYCLES<INTERVAL_CYCLES ? AUDIO_LEAD_CYCLES:INTERVAL_CYCLES/4;
 reg [BITS-1:0]age;
 reg anchored,requested,initial_request,manual_wait,busy_seen;
 assign hold_presentation=enabled && requested && anchored && age<INTERVAL_CYCLES;
 // Keep refilling the OLD PCM bank while a prefetched image waits. Its 42ms
 // bank covers a 10ms audio lead plus one 16.8ms video-frame quantization.
 assign audio_prepare_window=!enabled || !requested || !anchored || age>=INTERVAL_CYCLES-AUDIO_LEAD;
 always @(posedge clk or negedge reset_n)begin
  if(!reset_n)begin enabled<=0;next_press<=0;age<=0;anchored<=0;requested<=0;initial_request<=0;manual_wait<=0;busy_seen<=0;end
  else begin
   next_press<=0;
   if(transition_start)begin age<=0;anchored<=1;requested<=0;manual_wait<=0;end
   else if(enabled && anchored && age<INTERVAL_CYCLES)age<=age+1'b1;
   if(toggle_press)begin
    enabled<=!enabled;age<=0;requested<=0;manual_wait<=0;busy_seen<=0;
    initial_request<=!enabled && !image_loaded;
    if(image_loaded)anchored<=1;
   end else if(manual_press)begin
    requested<=0;initial_request<=0;manual_wait<=1;busy_seen<=0;age<=0;
   end else if(manual_wait)begin
    if(!can_advance)busy_seen<=1;
    if(busy_seen && can_advance)begin manual_wait<=0;age<=0;end
   end else if(enabled && !requested && can_advance && !transition_start &&
                (initial_request || (anchored && age>=THRESHOLD)))begin
    next_press<=1;requested<=1;initial_request<=0;
   end
  end
 end
endmodule
