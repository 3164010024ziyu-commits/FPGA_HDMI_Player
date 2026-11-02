// SYS_CLK timer. Count full viewing time only after load/transition completion.
module slideshow_ctrl #(
    parameter integer INTERVAL_CYCLES=250000000
)(
    input wire clk, reset_n, toggle_press, manual_press,
    input wire can_advance, image_loaded,
    output reg enabled,
    output reg next_press
);
    localparam integer BITS=INTERVAL_CYCLES>1?$clog2(INTERVAL_CYCLES):1;
    reg [BITS-1:0] count;
    reg waiting_for_busy, initial_request;
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin enabled<=0;next_press<=0;count<=0;waiting_for_busy<=0;initial_request<=0;end
        else begin
            next_press<=0;
            if(toggle_press) begin
                enabled<=!enabled;count<=0;waiting_for_busy<=0;
                initial_request<=!enabled && !image_loaded;
            end else if(!enabled || manual_press || !can_advance) begin
                count<=0;waiting_for_busy<=0;
                if(!enabled || manual_press)initial_request<=0;
            end else if(!waiting_for_busy) begin
                // Only the first startup request bypasses the interval.
                // Failed initial loads retry after five seconds, not in a loop.
                if((initial_request && !image_loaded) || count==INTERVAL_CYCLES-1) begin
                    next_press<=1;count<=0;waiting_for_busy<=1;initial_request<=0;
                end else count<=count+1'b1;
            end
        end
    end
endmodule
