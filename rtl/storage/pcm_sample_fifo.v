// Synchronous block RAM with a separate output register. No reset of RAM data.
module pcm_sample_fifo #(parameter AW=12)(
    input wire clk,rst_n,
    input wire [31:0] in_data,input wire in_valid,output wire in_ready,
    output reg [31:0] out_data,output reg out_valid,input wire out_ready,
    output wire [AW+1:0] level
);
    localparam DEPTH=1<<AW;
    reg [31:0] mem[0:DEPTH-1];
    reg [AW-1:0] wp,rp;
    reg [AW:0] count;
    wire take=(!out_valid || out_ready) && count!=0;
    wire push=in_valid && in_ready;
    assign in_ready=count!=DEPTH;
    assign level={1'b0,count}+out_valid;
    always @(posedge clk) begin
        if(push)mem[wp]<=in_data;
        if(take)out_data<=mem[rp];
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin wp<=0;rp<=0;count<=0;out_valid<=0;end
        else begin
            if(push)wp<=wp+1'b1;
            if(take)begin rp<=rp+1'b1;out_valid<=1;end
            else if(out_ready)out_valid<=0;
            case({push,take})
                2'b10:count<=count+1'b1;
                2'b01:count<=count-1'b1;
                default:begin end
            endcase
        end
    end
endmodule
