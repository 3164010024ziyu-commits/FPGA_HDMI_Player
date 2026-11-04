// Fetch four pixels per transaction, draining returned pixels concurrently.
// Images are top-left aligned; unused columns/lines are black. Widths and
// base addresses must be multiples of four, matching the existing SDRAM IP.
module sdram_read_ctrl #(
    parameter integer DISPLAY_WIDTH=640,
    parameter integer DISPLAY_HEIGHT=480,
    parameter integer READ_TIMEOUT=256
)(
    input wire Clk,
    input wire Reset_n,
    input wire blank_flush,
    input wire front_valid,
    input wire [20:0] front_base,
    input wire [15:0] front_width,
    input wire [15:0] front_height,
    output wire read_request,
    input wire read_grant,
    output wire read_active,
    output wire raster_active,
    output wire App_rd_en,
    output wire [20:0] App_rd_addr,
    input wire Sdr_rd_en,
    input wire [31:0] Sdr_rd_dout,
    input wire fifo_full,
    output wire fifo_wr_en,
    output wire [23:0] fifo_wr_data,
    output reg read_error
);
    localparam WAIT_FRAME=3'd0, PREPARE=3'd1, REQUEST=3'd2,
               ISSUE=3'd3, RECEIVE=3'd4, EMIT=3'd5;
    reg [2:0] state;
    reg blank_d;
    reg [15:0] x,y;
    reg [20:0] base;
    reg [15:0] width,height;
    reg [1:0] issue_count, emit_count;
    reg [2:0] received;
    reg [15:0] timeout_count;
    reg cancel_group;
    reg [23:0] pixels [0:3];
    wire response = Sdr_rd_en && read_active;
    wire [2:0] received_next = received + response;
    wire [31:0] row_offset = y * width;

    // Present the next read while preparing it. Otherwise the arbiter can
    // grant a write in this one-cycle request hole even below low watermark.
    // Geometry stays fixed while a four-word group is issued and drained.
    // Register its lookahead before finish_emit so the add/compare path ends
    // here instead of continuing through arbitration into the write FSM.
    reg next_group_data;
    always @(posedge Clk or negedge Reset_n) begin
        if(!Reset_n) next_group_data <= 0;
        else next_group_data <= x == DISPLAY_WIDTH-4 ? y + 16'd1 < height :
                                x + 16'd4 < width && y < height;
    end
    wire finish_emit = state == EMIT && emit_count == 3 && !fifo_full;
    assign read_request = (state == REQUEST ||
                           (state == PREPARE && x < width && y < height && !fifo_full) ||
                           (finish_emit && next_group_data)) &&
                          !blank_flush && front_valid;
    assign read_active = state == ISSUE || state == RECEIVE;
    assign raster_active = state != WAIT_FRAME;
    assign App_rd_en = state == ISSUE;
    assign App_rd_addr = base + row_offset[20:0] + x + issue_count;
    // Forward buffered return words while the remaining response is arriving.
    // The accepted group always has four local slots, so FIFO backpressure
    // cannot discard a response. Reuse the group only after its fourth emit.
    assign fifo_wr_en = (state == ISSUE || state == RECEIVE || state == EMIT) &&
                        received > {1'b0,emit_count} && !fifo_full &&
                        !blank_flush && !cancel_group;
    assign fifo_wr_data = pixels[emit_count];

    always @(posedge Clk or negedge Reset_n) begin
        if(!Reset_n) begin
            state <= WAIT_FRAME;
            blank_d <= 0;
            x <= 0; y <= 0; base <= 0; width <= 0; height <= 0;
            issue_count <= 0; emit_count <= 0; received <= 0;
            timeout_count <= 0; cancel_group <= 0; read_error <= 0;
        end else begin
            blank_d <= blank_flush;
            if(blank_flush) begin
                read_error <= 0;
                if(read_active) cancel_group <= 1;
            end
            if(response && received < 4) begin
                pixels[received] <= Sdr_rd_dout[23:0];
                received <= received_next;
            end
            if(fifo_wr_en && emit_count != 3)
                emit_count <= emit_count + 1'b1;
            if(read_active) begin
                timeout_count <= timeout_count + 1'b1;
                if(timeout_count == READ_TIMEOUT-1) begin
                    read_error <= 1;
                    state <= WAIT_FRAME;
                end
            end
            case(state)
                WAIT_FRAME: begin
                    // Restart only after the entire flush line. All old
                    // responses have then had time to drain before reuse.
                    if(blank_d && !blank_flush && front_valid) begin
                        base <= front_base; width <= front_width; height <= front_height;
                        x <= 0; y <= 0; state <= PREPARE;
                    end
                end
                PREPARE: begin
                    received <= 0; issue_count <= 0; emit_count <= 0;
                    timeout_count <= 0; cancel_group <= 0;
                    if(blank_flush) state <= WAIT_FRAME;
                    else if(x >= width || y >= height) begin
                        pixels[0] <= 0; pixels[1] <= 0;
                        pixels[2] <= 0; pixels[3] <= 0;
                        received <= 4;
                        state <= EMIT;
                    end else if(!fifo_full) state <= read_grant ? ISSUE : REQUEST;
                end
                REQUEST: begin
                    if(blank_flush) state <= WAIT_FRAME;
                    else if(read_grant) state <= ISSUE;
                end
                ISSUE: begin
                    // A flush never truncates an accepted four-beat request.
                    if(issue_count == 3) state <= RECEIVE;
                    else issue_count <= issue_count + 1'b1;
                end
                RECEIVE: begin
                    if(received_next == 4) begin
                        state <= (blank_flush || cancel_group) ? WAIT_FRAME : EMIT;
                    end
                end
                EMIT: begin
                    if(blank_flush) state <= WAIT_FRAME;
                    else if(fifo_wr_en) begin
                        if(emit_count == 3) begin
                            // Prepare counters while the last buffered pixel is sent.
                            // The next request still consists of exactly four beats.
                            received <= 0; issue_count <= 0; emit_count <= 0;
                            timeout_count <= 0; cancel_group <= 0;
                            if(x == DISPLAY_WIDTH-4) begin
                                x <= 0;
                                y <= y + 1'b1;
                                state <= y == DISPLAY_HEIGHT-1 ? WAIT_FRAME :
                                         (read_grant ? ISSUE : PREPARE);
                            end else begin
                                x <= x + 4;
                                state <= read_grant ? ISSUE : PREPARE;
                            end
                        end
                    end
                end
                default: state <= WAIT_FRAME;
            endcase
            // A missing response invalidates this raster until the next flush.
            if(read_active && timeout_count == READ_TIMEOUT-1) begin
                read_error <= 1;
                state <= WAIT_FRAME;
            end
        end
    end
endmodule
