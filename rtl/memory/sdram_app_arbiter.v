// Reserve the SDRAM application port for a complete four-word transaction.
// Refresh has priority. Urgent display reads take priority over writes;
// otherwise reads and writes alternate when both are waiting.
module sdram_app_arbiter #(
    parameter integer QUIET_CYCLES = 4
)(
    input wire Clk,
    input wire Reset_n,
    input wire initialized,
    input wire refresh_pending,
    input wire refresh_active,
    input wire sdram_busy,
    input wire write_request,
    input wire write_active,
    input wire read_request,
    input wire read_urgent,
    input wire read_active,
    input wire read_return,
    output wire write_grant,
    output wire read_grant,
    output wire write_owned
);
    localparam IDLE=2'd0, WRITE=2'd1, READ=2'd2;
    reg [1:0] owner;
    reg last_was_read;
    reg [7:0] quiet_count;
    // A drained read may hand off on the same edge that releases ownership.
    // All physical busy/return checks still apply; no accepted group is cut.
    wire read_drained = owner == READ && !write_active && !read_active &&
                        !read_return && !sdram_busy && !refresh_active &&
                        quiet_count == QUIET_CYCLES-1;
    wire available = (owner == IDLE || read_drained) && initialized &&
                     !refresh_pending && !refresh_active && !sdram_busy;
    // While the active raster is below low watermark, reserve the port for
    // its next group even during the reader's brief prepare/emit intervals.
    assign write_grant = available && write_request && !read_urgent &&
                         (!read_request || last_was_read);
    assign read_grant = available && read_request && (read_urgent || !write_request || !last_was_read);
    assign write_owned = owner == WRITE;

    always @(posedge Clk or negedge Reset_n) begin
        if(!Reset_n) begin
            owner <= IDLE;
            last_was_read <= 0;
            quiet_count <= 0;
        end else begin
            case(owner)
                IDLE: begin
                    quiet_count <= 0;
                    if(write_grant) begin owner <= WRITE; last_was_read <= 0; end
                    else if(read_grant) begin owner <= READ; last_was_read <= 1; end
                end
                WRITE, READ: begin
                    if(write_active || read_active || read_return || sdram_busy || refresh_active)
                        quiet_count <= 0;
                    else if(quiet_count == QUIET_CYCLES-1) begin
                        if(read_grant) begin owner <= READ; last_was_read <= 1; end
                        else if(write_grant) begin owner <= WRITE; last_was_read <= 0; end
                        else owner <= IDLE;
                        quiet_count <= 0;
                    end else quiet_count <= quiet_count + 1'b1;
                end
                default: owner <= IDLE;
            endcase
        end
    end
endmodule
