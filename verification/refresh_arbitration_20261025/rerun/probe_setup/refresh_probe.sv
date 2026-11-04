`timescale 1ns / 1ps

// Bind to public ports of the real init/refresh module. This observer never
// drives a DUT signal and does not infer ACK from a different signal.
module refresh_observer (
    input wire clk,
    input wire request,
    input wire acknowledge,
    input wire rw_active
);
    initial $display("REFRESH_OBSERVER_BOUND scope=%m");
    always @(posedge clk) refresh_wait_tb.probe_bound = 1'b1;
    always @(request) refresh_wait_tb.log_event("REFRESH_REQUEST", request);
    always @(acknowledge) refresh_wait_tb.log_event("REFRESH_ACK", acknowledge);
    always @(rw_active) refresh_wait_tb.log_event("INTERNAL_RW_ACTIVE", rw_active);
    always @(refresh_wait_tb.observing) begin
        if (refresh_wait_tb.observing) begin
            refresh_wait_tb.log_event("REFRESH_REQUEST_INITIAL", request);
            refresh_wait_tb.log_event("REFRESH_ACK_INITIAL", acknowledge);
            refresh_wait_tb.log_event("INTERNAL_RW_ACTIVE_INITIAL", rw_active);
        end
    end
endmodule

module refresh_bind_top;
    bind sdr_init_ref refresh_observer refresh_port_observer (
        .clk(Sdr_clk), .request(Sdr_ref_req), .acknowledge(Sdr_ref_ack), .rw_active(Sdr_rw_vld)
    );
endmodule
