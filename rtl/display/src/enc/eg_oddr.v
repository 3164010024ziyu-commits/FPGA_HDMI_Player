// Anlogic EG4 DDR output wrapper.
// d0 is launched on the rising edge and d1 on the falling edge (see the
// EG_LOGIC_ODDR template in the TD installation).  Define SIM_ODDR to use the
// behavioural model with iverilog.
module eg_oddr (
    output wire q,
    input  wire clk,
    input  wire d1,
    input  wire d0,
    input  wire rst
);
`ifdef SIM_ODDR
    // Matches EG_LOGIC_ODDR from td/sim_release/eg4/eg_logic_io.v:
    // both inputs are captured on the rising edge, the falling-edge value is
    // pipelined and selected while the clock is low.
    reg comp0, comp1, true_r;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            comp0  <= 1'b0;
            true_r <= 1'b0;
        end else begin
            comp0  <= d1;
            true_r <= d0;
        end
    end
    always @(negedge clk or posedge rst) begin
        if (rst) comp1 <= 1'b0;
        else     comp1 <= comp0;
    end
    assign q = clk ? true_r : comp1;
`else
    EG_LOGIC_ODDR u_oddr (
        .q  (q),
        .clk(clk),
        .d1 (d1),
        .d0 (d0),
        .rst(rst)
    );
`endif
endmodule
