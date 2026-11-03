// Tags accompany the PCM word through exactly the same CDC queue:
// [2] source enabled, [1] actual file sample, [0] first sample of this loop.
// Silence for prefill/underrun is not file progress. Muted file samples are.
module audio_progress #(parameter FS=48000,parameter HOLD_IDLE=0)(
 input wire clk,rst_n,consume,input wire [2:0] tag,input wire restart,
 output reg playing,output reg [23:0] time_bcd
);
 localparam BITS=FS>1?$clog2(FS):1;
 reg [BITS-1:0] samples;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin samples<=0;time_bcd<=0;playing<=0;end
  else if(HOLD_IDLE!=0 && restart)begin samples<=0;time_bcd<=0;playing<=1;end
  else if(consume)begin
   if(!tag[2])begin samples<=0;time_bcd<=0;playing<=0;end
   else if(tag[1])begin
    playing<=1;
    if(tag[0])begin samples<=FS==1?0:1;time_bcd<=FS==1?24'h000001:0;end
    else if(samples==FS-1)begin
     samples<=0;
     if(time_bcd[3:0]!=9)time_bcd[3:0]<=time_bcd[3:0]+1'b1;
     else begin time_bcd[3:0]<=0;
      if(time_bcd[7:4]!=5)time_bcd[7:4]<=time_bcd[7:4]+1'b1;
      else begin time_bcd[7:4]<=0;
       if(time_bcd[11:8]!=9)time_bcd[11:8]<=time_bcd[11:8]+1'b1;
       else begin time_bcd[11:8]<=0;
        if(time_bcd[15:12]!=5)time_bcd[15:12]<=time_bcd[15:12]+1'b1;
        else begin time_bcd[15:12]<=0;
         if(time_bcd[19:16]!=9)time_bcd[19:16]<=time_bcd[19:16]+1'b1;
         else begin time_bcd[19:16]<=0;
          time_bcd[23:20]<=time_bcd[23:20]==9?0:time_bcd[23:20]+1'b1;
         end
        end
       end
      end
     end
    end else samples<=samples+1'b1;
   end else if(HOLD_IDLE!=0)playing<=1;else playing<=0;
  end
 end
endmodule
