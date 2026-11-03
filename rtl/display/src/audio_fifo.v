// -----------------------------------------------------------------------------
// Audio sample CDC buffer.
//
// A single-sample toggle mailbox safely crosses the (slow) audio clock into the
// pixel clock domain.  Received samples are pushed into a small synchronous
// FIFO in the pixel domain, which gives ~16 samples (0.33 ms at 48 kHz) of
// slack for the HDMI packet scheduler.  Keeping all multi-bit pointers in one
// clock domain avoids hand-rolled gray-pointer CDC and TD optimizer issues.
// -----------------------------------------------------------------------------
module audio_fifo #(
    parameter integer DATA_WIDTH = 32,
    parameter integer AWIDTH = 4        // synchronous FIFO depth = 2^AWIDTH
) (
    input  wire            wr_clk,
    input  wire            wr_rst,
    input  wire            wr_en,
    input  wire [DATA_WIDTH-1:0] wr_data,

    output wire            full,
    output wire            overflow,

    input  wire            rd_clk,
    input  wire            rd_rst,
    input  wire            rd_en,
    
    output wire [DATA_WIDTH-1:0] rd_data,
    output wire            empty
);

    localparam integer DEPTH = (1 << AWIDTH);

    // ---------------------------------------------------- write-side mailbox
    reg [DATA_WIDTH-1:0] mailbox;
    reg        wr_tog;
    reg        rd_tog;              // declared before the write-side sync uses it
    reg [2:0]  rd_tog_sync;         // rd_tog -> wr_clk
    reg [2:0]  wr_tog_sync;         // wr_tog -> rd_clk

    wire mailbox_free = (wr_tog == rd_tog_sync[2]);
    wire mailbox_wr   = wr_en && mailbox_free;

    always @(posedge wr_clk or posedge wr_rst) begin
        if (wr_rst) begin
            mailbox <= 32'd0;
            wr_tog  <= 1'b0;
        end else begin
            mailbox <= mailbox_wr ? wr_data : mailbox;
            wr_tog  <= wr_tog ^ mailbox_wr;
        end
    end

    always @(posedge wr_clk or posedge wr_rst) begin
        if (wr_rst) rd_tog_sync <= 3'b000;
        else        rd_tog_sync <= {rd_tog_sync[1:0], rd_tog};
    end

    assign full     = !mailbox_free;
    assign overflow = wr_en && full;

    // ----------------------------------------------------- read-side mailbox
    always @(posedge rd_clk or posedge rd_rst) begin
        if (rd_rst) wr_tog_sync <= 3'b000;
        else        wr_tog_sync <= {wr_tog_sync[1:0], wr_tog};
    end

    wire new_sample = (wr_tog_sync[2] != rd_tog);

    // ------------------------------------- synchronous FIFO (pixel domain)
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    reg [AWIDTH:0] wptr, rptr;

    wire [AWIDTH:0] wptr_next = wptr + {{AWIDTH{1'b0}}, new_sample};
    wire [AWIDTH:0] rptr_next = rptr + {{AWIDTH{1'b0}}, (rd_en && !empty)};

    assign empty   = (wptr == rptr);
    assign rd_data = mem[rptr[AWIDTH-1:0]];

    always @(posedge rd_clk or posedge rd_rst) begin
        if (rd_rst) begin
            wptr    <= {(AWIDTH+1){1'b0}};
            rptr    <= {(AWIDTH+1){1'b0}};
            rd_tog  <= 1'b0;
        end else begin
            wptr   <= wptr_next;
            rptr   <= rptr_next;
            rd_tog <= new_sample ? wr_tog_sync[2] : rd_tog;
            if (new_sample)
                mem[wptr[AWIDTH-1:0]] <= mailbox;
        end
    end

endmodule
