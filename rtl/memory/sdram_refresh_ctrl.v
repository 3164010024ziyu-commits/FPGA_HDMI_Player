// Application-side AUTO REFRESH arbitration. All inputs use Clk.
// The vendor's periodic request generator must be disabled for this instance.
module sdram_refresh_ctrl #(
    parameter integer INTERVAL_CYCLES = 1875,
    parameter integer QUIET_CYCLES = 4,
    parameter integer TIMEOUT_CYCLES = 1024
)(
    input wire Clk,
    input wire Reset_n,
    input wire Sdr_init_done,
    input wire Sdr_init_ref_vld,
    input wire Sdr_busy,
    input wire App_wr_en,
    input wire App_rd_en,
    input wire manual_refresh_req,
    output wire refresh_pending,
    output reg App_ref_req,
    output reg refresh_error
);
    localparam IDLE = 2'd0, DRAIN = 2'd1, WAIT_START = 2'd2, WAIT_END = 2'd3;
    reg [1:0] state;
    reg [31:0] interval_count;  //0到INTERVAL_CYCLES计数器
    reg [31:0] quiet_count;
    reg [31:0] wait_count;
    reg manual_d;
    wire due = (interval_count == INTERVAL_CYCLES - 1);
    wire manual_edge = manual_refresh_req && !manual_d;
    assign refresh_pending = (state != IDLE) || refresh_error;

    always @(posedge Clk or negedge Reset_n) begin
        if (!Reset_n) begin
            state <= IDLE;
            interval_count <= 0;
            quiet_count <= 0;
            wait_count <= 0;
            manual_d <= 1'b0;
            App_ref_req <= 1'b0;
            refresh_error <= 1'b0;
        end else if (!Sdr_init_done) begin
            state <= IDLE;
            interval_count <= 0;
            quiet_count <= 0;
            wait_count <= 0;
            manual_d <= 1'b0;
            App_ref_req <= 1'b0;
            refresh_error <= 1'b0;
        end else begin
            manual_d <= manual_refresh_req;
            App_ref_req <= 1'b0;
            if (due)
                interval_count <= 0;
            else
                interval_count <= interval_count + 1'b1;

            if (state == IDLE)
                wait_count <= 0;
            else if (wait_count < TIMEOUT_CYCLES)
                wait_count <= wait_count + 1'b1;
            if (state != IDLE && wait_count == TIMEOUT_CYCLES - 1)
                refresh_error <= 1'b1;
            // A second periodic deadline while still pending is a missed service.
            if (state != IDLE && due)
                refresh_error <= 1'b1;

            case (state)
                IDLE: begin
                    quiet_count <= 0;
                    if ((due || manual_edge) && !refresh_error) begin
                        // A manual service also refreshes the device. Restart
                        // the interval so an adjacent periodic tick is not
                        // mistaken for a second missed service deadline.
                        interval_count <= 0;
                        state <= DRAIN;
                    end
                end
                DRAIN: begin
                    if (App_wr_en || App_rd_en || Sdr_busy || Sdr_init_ref_vld)
                        quiet_count <= 0;
                    else if (quiet_count == QUIET_CYCLES - 1) begin
                        quiet_count <= 0;
                        App_ref_req <= 1'b1;
                        state <= WAIT_START;
                    end else
                        quiet_count <= quiet_count + 1'b1;
                end
                WAIT_START: if (Sdr_init_ref_vld) state <= WAIT_END;
                WAIT_END: if (!Sdr_init_ref_vld && !Sdr_busy) state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end
endmodule
