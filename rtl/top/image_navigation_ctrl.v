// SYS_CLK-domain file selection. Commit an index only after successful load
// completion and downstream readiness; a missing next file keeps the front frame.
module image_navigation_ctrl (
    input wire clk, reset_n,
    input wire reload_press, previous_press, next_press,
    input wire load_ready, load_done, load_error,
    input wire [7:0] load_error_code,
    input wire [15:0] opened_index,
    output wire start,
    output reg select_last,
    output reg [15:0] file_index,
    output reg [15:0] current_index,
    output wire request_pending,
    output wire report_load_error
);
    localparam NONE=2'd0, RELOAD=2'd1, PREVIOUS=2'd2, NEXT=2'd3;
    reg [1:0] pending_command, active_command;
    reg launch_pending, in_flight, busy_seen, done_seen, failed;
    reg image_loaded, last_known, boundary_held, boundary_seen;
    reg [15:0] last_index;
    wire boundary_miss = image_loaded && active_command==NEXT &&
                         load_error_code==8'h36;
    assign report_load_error = load_error && !(boundary_miss || boundary_held);
    assign start = launch_pending && load_ready && !in_flight;
    assign request_pending = pending_command!=NONE || launch_pending;

    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            pending_command<=NONE; active_command<=NONE;
            launch_pending<=0; in_flight<=0; busy_seen<=0;
            done_seen<=0; failed<=0; image_loaded<=0;
            current_index<=0; file_index<=0; select_last<=0;
            last_known<=0; last_index<=0; boundary_held<=0; boundary_seen<=0;
        end else begin
            if(!load_error) boundary_held<=0;
            if(!in_flight && !launch_pending && pending_command!=NONE) begin
                pending_command<=NONE;
                select_last<=0;
                if(pending_command==PREVIOUS && current_index==0) begin
                    file_index<=last_known ? last_index : 16'd0;
                    select_last<=!last_known;
                    active_command<=PREVIOUS;launch_pending<=1;
                end else if(!image_loaded || pending_command==RELOAD) begin
                    file_index<=current_index;
                    active_command<=RELOAD; launch_pending<=1;
                end else if(pending_command==PREVIOUS && current_index!=0) begin
                    file_index<=current_index-16'd1;
                    active_command<=PREVIOUS; launch_pending<=1;
                end else if(pending_command==NEXT) begin
                    if(current_index==16'hffff || (last_known && current_index==last_index)) begin
                        file_index<=0;active_command<=RELOAD;
                    end else begin file_index<=current_index+16'd1;active_command<=NEXT;end
                    launch_pending<=1;
                end
            end
            if(start) begin
                launch_pending<=0; in_flight<=1; busy_seen<=0;
                done_seen<=0; failed<=0; boundary_seen<=0;
            end
            if(in_flight) begin
                if(!load_ready) busy_seen<=1;
                if(load_done) done_seen<=1;
                if(busy_seen && load_error) begin
                    failed<=1;
                    if(boundary_miss) begin
                        last_known<=1;last_index<=current_index;boundary_held<=1;boundary_seen<=1;
                    end
                end
                if(busy_seen && load_ready) begin
                    in_flight<=0;
                    if(!failed && !load_error && (done_seen || load_done)) begin
                        current_index<=select_last ? opened_index : file_index;image_loaded<=1;
                        if(select_last)begin last_known<=1;last_index<=opened_index;end
                    end else if(boundary_seen || boundary_miss) begin
                        // Index N did not exist: the existing front frame stays
                        // visible until index zero has loaded successfully.
                        file_index<=0;select_last<=0;active_command<=RELOAD;launch_pending<=1;
                    end
                end
            end
            // Last press wins in the single pending slot; events on the launch
            // edge remain queued for the next completed transaction.
            if(reload_press) pending_command<=RELOAD;
            else if(previous_press && !next_press) pending_command<=PREVIOUS;
            else if(next_press && !previous_press) pending_command<=NEXT;
        end
    end
endmodule
