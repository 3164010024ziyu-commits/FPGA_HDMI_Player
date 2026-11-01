// One physical card, two independent file streams. Ownership covers the full
// CRC-checked 512-byte response. Round robin bounds contention to one sector.
module sd_sector_arbiter (
    input wire clk,rst_n,
    input wire a_req,input wire [31:0] a_lba,output wire a_grant,
    output wire a_valid,a_last,a_error,output reg [7:0] a_code,input wire a_ready,
    input wire b_enable,b_req,input wire [31:0] b_lba,output wire b_grant,
    output wire b_valid,b_last,b_error,output reg [7:0] b_code,input wire b_ready,
    output wire req,input wire grant,output wire [31:0] lba,
    input wire valid,last,error,input wire [7:0] code,output wire ready
);
    reg [1:0] owner;
    reg last_was_b,discard_b;
    wire choose_b=b_enable && b_req && (!a_req || !last_was_b);
    assign req=owner==0 && (a_req || (b_enable && b_req));
    assign lba=choose_b ? b_lba : a_lba;
    assign a_grant=owner==0 && !choose_b && grant;
    assign b_grant=owner==0 && choose_b && grant;
    assign a_valid=owner==1 && valid;
    assign b_valid=owner==2 && valid && !discard_b && b_enable;
    assign a_last=a_valid && last;
    assign b_last=b_valid && last;
    assign a_error=owner==1 && error;
    assign b_error=owner==2 && error && !discard_b && b_enable;
    // A disabled/restarted audio reader cannot leave an accepted sector stuck.
    assign ready=owner==1 ? a_ready : owner==2 ? (discard_b || !b_enable || b_ready) : 1'b0;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin owner<=0;last_was_b<=1;discard_b<=0;a_code<=0;b_code<=0;end
        else begin
            if(req && grant)begin owner<=choose_b?2:1;last_was_b<=choose_b;discard_b<=0;end
            if(owner==2 && !b_enable)discard_b<=1;
            if(a_error)a_code<=code;
            if(b_error)b_code<=code;
            if(owner!=0 && (error || (valid && ready && last)))begin owner<=0;discard_b<=0;end
        end
    end
endmodule
