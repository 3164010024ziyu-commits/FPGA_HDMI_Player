// Stable-data request/ack crossing. Both domains share an asynchronous reset.
// Payload is held until the destination has captured it and acknowledged.
module subtitle_mailbox #(parameter WIDTH=136)(
 input wire src_clk,dst_clk,rst_n,
 input wire src_valid,input wire [WIDTH-1:0] src_data,output wire src_ready,
 output reg dst_valid,output reg [WIDTH-1:0] dst_data
);
 reg [WIDTH-1:0] held;
 reg request,ack;
 reg [1:0] req_sync,ack_sync;
 assign src_ready=request==ack_sync[1];
 always @(posedge src_clk or negedge rst_n)begin
  if(!rst_n)begin held<=0;request<=0;ack_sync<=0;end
  else begin
   ack_sync<={ack_sync[0],ack};
   if(src_valid && src_ready)begin held<=src_data;request<=!request;end
  end
 end
 always @(posedge dst_clk or negedge rst_n)begin
  if(!rst_n)begin req_sync<=0;ack<=0;dst_data<=0;dst_valid<=0;end
  else begin
   req_sync<={req_sync[0],request};dst_valid<=0;
   if(req_sync[1]!=ack)begin dst_data<=held;dst_valid<=1;ack<=req_sync[1];end
  end
 end
endmodule
