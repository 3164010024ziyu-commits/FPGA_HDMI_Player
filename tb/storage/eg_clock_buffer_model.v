// Simulation-only ideal global clock buffer. TD uses its built-in EG4 primitive.
module EG_LOGIC_BUFG(input wire i, output wire o);
    assign o=i;
endmodule
