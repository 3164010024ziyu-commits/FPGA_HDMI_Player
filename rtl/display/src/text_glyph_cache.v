// Two 64-character glyph banks. Write only the inactive bank; publish at a
// complete video-frame boundary and acknowledge before the next bank reuse.
module text_glyph_cache(
    input wire src_clk,pix_clk,rst_n,
    input wire write_enable,input wire [9:0] write_addr,input wire [15:0] write_data,
    input wire commit,input wire [6:0] src_length,input wire src_has_text,
    output wire src_ready,
    input wire frame_end,input wire [9:0] read_addr,output reg [15:0] read_data,
    output reg [6:0] text_length,output reg has_text,output reg changed
);
    reg [15:0] mem[0:2047];
    reg write_bank,active_bank;
    reg [8:0] held;
    reg request,ack;
    reg [1:0] req_sync,ack_sync;
    assign src_ready=request==ack_sync[1];
    always @(posedge src_clk)if(write_enable && src_ready)mem[{write_bank,write_addr}]<=write_data;
    always @(posedge pix_clk)read_data<=mem[{active_bank,read_addr}];
    always @(posedge src_clk or negedge rst_n)begin
        if(!rst_n)begin write_bank<=1;held<=0;request<=0;ack_sync<=0;end
        else begin
            ack_sync<={ack_sync[0],ack};
            if(commit && src_ready)begin
                held<={write_bank,src_has_text,src_length};request<=!request;write_bank<=!write_bank;
            end
        end
    end
    always @(posedge pix_clk or negedge rst_n)begin
        if(!rst_n)begin req_sync<=0;ack<=0;active_bank<=0;text_length<=0;has_text<=0;changed<=0;end
        else begin
            req_sync<={req_sync[0],request};changed<=0;
            if(frame_end && req_sync[1]!=ack)begin
                active_bank<=held[8];has_text<=held[7];text_length<=held[6:0];ack<=req_sync[1];changed<=1;
            end
        end
    end
endmodule
