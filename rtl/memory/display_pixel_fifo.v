// 100 MHz producer -> pixel-clock consumer. The two-entry output queue
// accounts for the registered read latency of async_fifo and allows one
// pixel to be consumed on every active pixel clock.
module display_pixel_fifo #(
    parameter integer ADDR_WIDTH=11
)(
    input wire mem_clk,
    input wire pix_clk,
    input wire Reset_n,
    input wire blank_flush,
    input wire frame_valid_mem,
    input wire wr_en,
    input wire [23:0] wr_data,
    output wire full,
    output wire read_urgent,
    input wire pix_req,
    output wire [23:0] pix_rgb,
    output wire pix_valid,
    output wire frame_ready,
    output reg underflow
);
    wire fifo_reset_n = Reset_n && !blank_flush;
    wire empty, rd_valid;
    wire [23:0] rd_data;
    wire [ADDR_WIDTH:0] wr_used;
    // Register the low-watermark comparison before arbitration. A one-cycle
    // delayed hint is safe: full still gates every write independently.
    reg [1:0] mem_release;
    always @(posedge mem_clk or negedge fifo_reset_n) begin
        if(!fifo_reset_n) mem_release <= 0;
        else mem_release <= {mem_release[0],1'b1};
    end
    reg urgent_reg;
    always @(posedge mem_clk or negedge mem_release[1]) begin
        if(!mem_release[1]) urgent_reg <= 1;
        else urgent_reg <= wr_used <= (1 << (ADDR_WIDTH-1));
    end
    assign read_urgent = urgent_reg;
    reg [1:0] pix_release;
    always @(posedge pix_clk or negedge fifo_reset_n) begin
        if(!fifo_reset_n) pix_release <= 0;
        else pix_release <= {pix_release[0],1'b1};
    end
    wire pix_reset_n = pix_release[1];
    reg [1:0] ready_sync;
    always @(posedge pix_clk or negedge Reset_n) begin
        if(!Reset_n) ready_sync <= 0;
        else ready_sync <= {ready_sync[0],frame_valid_mem};
    end
    assign frame_ready = ready_sync[1];
    reg [23:0] first, second;
    reg [1:0] count;
    reg pending;
    wire consume = pix_req && frame_ready && count != 0;
    wire [2:0] reserved = {1'b0,count} + pending;
    wire rd_en = pix_reset_n && !empty && (reserved < 2 || consume);
    assign pix_rgb = first;
    assign pix_valid = pix_reset_n && frame_ready && count != 0 && !underflow;

    async_fifo #(.DATA_WIDTH(24),.ADDR_WIDTH(ADDR_WIDTH)) u_fifo (
        .wr_clk(mem_clk), .rd_clk(pix_clk), .Reset_n(fifo_reset_n),
        .wr_en(wr_en), .wr_data(wr_data), .full(full), .wr_used(wr_used),
        .rd_en(rd_en), .rd_data(rd_data), .rd_valid(rd_valid), .empty(empty)
    );
    always @(posedge pix_clk or negedge pix_reset_n) begin
        if(!pix_reset_n) begin
            first <= 0; second <= 0; count <= 0; pending <= 0; underflow <= 0;
        end else begin
            pending <= rd_en;
            if(pix_req && frame_ready && count == 0) underflow <= 1;
            case({rd_valid,consume})
                2'b10: begin
                    if(count == 0) first <= rd_data;
                    else second <= rd_data;
                    count <= count + 1'b1;
                end
                2'b01: begin first <= second; count <= count - 1'b1; end
                2'b11: begin
                    if(count == 1) first <= rd_data;
                    else begin first <= second; second <= rd_data; end
                end
                default: begin end
            endcase
        end
    end
endmodule
