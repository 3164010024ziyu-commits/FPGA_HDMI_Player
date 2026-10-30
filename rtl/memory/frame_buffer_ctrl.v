// 双帧缓存管理
module frame_buffer_ctrl #(
    parameter integer DISPLAY_WIDTH=640,
    parameter integer DISPLAY_HEIGHT=480
)(
    input wire sys_clk,
    input wire sys_rst_n,
    input wire initialized,
    input wire frame_start,
    input wire frame_end,
    input wire frame_abort,
    input wire [20:0] frame_base_addr,
    input wire [15:0] frame_width,
    input wire [15:0] frame_height,
    input wire desc_ready,
    output wire desc_valid,
    output wire [20:0] desc_base,
    output wire pixel_accept,
    output wire frame_write_ready,
    output reg frame_error,

    input wire mem_clk,
    input wire mem_rst_n,
    input wire dst_valid,
    input wire [20:0] dst_base,
    input wire [15:0] dst_width,
    input wire [15:0] dst_height,
    input wire writer_done,
    input wire write_owned,
    input wire read_active,
    input wire blank_flush,
    output wire writer_reset_n,
    output wire write_block,
    output reg front_valid,
    output reg [20:0] front_base,
    output reg [15:0] front_width,
    output reg [15:0] front_height
);
    localparam integer SLOT_WORDS = DISPLAY_WIDTH * DISPLAY_HEIGHT;
    reg pool_set;
    reg [20:0] pool_base;
    reg source_active;
    reg abort_toggle, abort_d;
    reg abort_ack;
    reg [1:0] abort_ack_sync;
    // Bank changes are held while unavailable. Delay availability one more
    // SYS_CLK stage so the two-stage synchronized bank is stable first.
    reg [2:0] ready_sync;
    reg [1:0] bank_sync;
    reg available_mem;
    reg back_bank;
    reg writing, pending_frame;
    reg [20:0] pending_base;
    reg [15:0] pending_width,pending_height;
    reg [1:0] abort_sync;
    reg [3:0] clear_count;

    wire abort_pending_sys = abort_toggle != abort_ack_sync[1];
    wire abort_pending_mem = abort_sync[1] != abort_ack;
    wire [20:0] selected_pool = pool_set ? pool_base : frame_base_addr;
    wire [22:0] pool_end = {2'b0,selected_pool} + 2*SLOT_WORDS;
    wire geometry_ok = frame_width != 0 && frame_height != 0 &&
                       frame_width <= DISPLAY_WIDTH && frame_height <= DISPLAY_HEIGHT &&
                       frame_width[1:0] == 0;
    wire base_ok = selected_pool[1:0] == 0 && pool_end <= 23'd2097152 &&
                   (!pool_set || frame_base_addr == pool_base);
    assign frame_write_ready = sys_rst_n && initialized && ready_sync[2] &&
                               desc_ready && !abort_pending_sys && !source_active;
    assign desc_valid = frame_start && frame_write_ready && geometry_ok && base_ok;
    assign desc_base = selected_pool + (bank_sync[1] ? SLOT_WORDS : 0);
    assign pixel_accept = source_active && !frame_abort && !abort_pending_sys;
    assign writer_reset_n = mem_rst_n && clear_count == 0;
    assign write_block = abort_pending_mem || clear_count != 0;

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if(!sys_rst_n) begin
            pool_set <= 0; pool_base <= 0; source_active <= 0;
            abort_toggle <= 0; abort_d <= 0; abort_ack_sync <= 0;
            ready_sync <= 0; bank_sync <= 0; frame_error <= 0;
        end else begin
            abort_ack_sync <= {abort_ack_sync[0],abort_ack};
            ready_sync <= {ready_sync[1:0],available_mem};
            bank_sync <= {bank_sync[0],back_bank};
            abort_d <= frame_abort;
            frame_error <= 0;
            if(desc_valid) begin
                source_active <= 1;
                pool_base <= selected_pool;
                pool_set <= 1;
            end
            if(frame_end) source_active <= 0;
            if((frame_start && !desc_valid) || (frame_abort && !abort_d)) begin
                source_active <= 0;
                if(!abort_pending_sys) abort_toggle <= ~abort_toggle;
                if(frame_start && !desc_valid) frame_error <= 1;
            end
        end
    end

    always @(posedge mem_clk or negedge mem_rst_n) begin
        if(!mem_rst_n) begin
            abort_sync <= 0; abort_ack <= 0; clear_count <= 0;
            available_mem <= 0;
            back_bank <= 0; writing <= 0; pending_frame <= 0;
            pending_base <= 0; pending_width <= 0; pending_height <= 0;
            front_valid <= 0; front_base <= 0; front_width <= 0; front_height <= 0;
        end else begin
            // Register the writing -> pending handoff; a combinational
            // decode of two changing state bits must not cross domains.
            available_mem <= !writing && !pending_frame && !abort_pending_mem && clear_count == 0;
            abort_sync <= {abort_sync[0],abort_toggle};
            if(clear_count != 0) begin
                clear_count <= clear_count - 1'b1;
                if(clear_count == 1) abort_ack <= abort_sync[1];
            end else if(abort_pending_mem) begin
                // Let an accepted write group and its physical drain finish.
                // The front slot remains valid while the failed back slot is discarded.
                if(!write_owned) begin
                    clear_count <= 8;
                    writing <= 0;
                    pending_frame <= 0;
                end
            end else begin
                if(dst_valid) begin
                    writing <= 1;
                    pending_base <= dst_base;
                    pending_width <= dst_width;
                    pending_height <= dst_height;
                end else if(writing && writer_done) begin
                    writing <= 0;
                    pending_frame <= 1;
                end
                if(pending_frame && blank_flush && !read_active) begin
                    front_base <= pending_base;
                    front_width <= pending_width;
                    front_height <= pending_height;
                    front_valid <= 1;
                    pending_frame <= 0;
                    back_bank <= ~back_bank;
                end
            end
        end
    end
endmodule
