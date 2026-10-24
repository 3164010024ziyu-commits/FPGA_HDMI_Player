// Windows BMP: BI_RGB, 24/32 bpp, signed height, DWORD row padding.
// Input begins at file offset zero. in_last marks the actual directory file EOF.
module bmp_stream_decoder #(
    parameter MAX_WIDTH=1920, parameter MAX_HEIGHT=1080
)(
    input wire clk, input wire rst_n,
    input wire start, input wire abort, input wire [31:0] file_size,
    input wire [7:0] in_data, input wire in_valid,
    input wire in_last, output wire in_ready,
    output reg busy, output reg done,
    output reg error, output reg [7:0] error_code,
    output reg meta_valid, output reg [15:0] width, height,
    output reg top_down,
    output reg pixel_valid, input wire pixel_ready,
    output reg [23:0] pixel_rgb888, output wire [15:0] pixel_rgb565,
    output reg [15:0] pixel_x, pixel_y,
    output reg [31:0] pixel_addr,
    output reg pixel_sof, pixel_eol, pixel_eof
);
    localparam IDLE=0, HEADER=1, CHECK=2, SKIP=3, PIXELS=4,
               PAD=5, TRAIL=6, FINISH=7, FAILED=8,
               SIZE_MUL=9, SIZE_ADD=10, SIZE_CHECK=11;
    function integer dimension_bits;
        input integer maximum;
        integer n;
        begin
            n=(maximum>65535) ? 65535 : maximum;
            dimension_bits=0;
            while(n>0) begin dimension_bits=dimension_bits+1; n=n>>1; end
            if(dimension_bits==0) dimension_bits=1;
        end
    endfunction
    localparam W_BITS=dimension_bits(MAX_WIDTH), H_BITS=dimension_bits(MAX_HEIGHT);
    reg [3:0] state;
    reg [7:0] hdr [0:53];
    reg [31:0] pos, size_latched, row_base;
    reg [15:0] x, y, rows;
    reg [1:0] component, padding, pad_left;
    reg [7:0] blue, green, red;
    reg is32, first_pixel;
    wire [31:0] off_bits={hdr[13],hdr[12],hdr[11],hdr[10]};
    wire [31:0] dib_size={hdr[17],hdr[16],hdr[15],hdr[14]};
    wire [31:0] w={hdr[21],hdr[20],hdr[19],hdr[18]};
    wire [31:0] h_raw={hdr[25],hdr[24],hdr[23],hdr[22]};
    wire [31:0] h=h_raw[31] ? (~h_raw+1'b1) : h_raw;
    wire [15:0] planes={hdr[27],hdr[26]};
    wire [15:0] bpp={hdr[29],hdr[28]};
    wire [31:0] compression={hdr[33],hdr[32],hdr[31],hdr[30]};
    wire [31:0] declared_size={hdr[5],hdr[4],hdr[3],hdr[2]};
    // Header dimensions are bounds-checked before the staged size calculation.
    // Narrow the arithmetic to the configured maximum, not arbitrary file bits.
    wire [W_BITS-1:0] math_w=width[W_BITS-1:0];
    wire [H_BITS-1:0] math_h=height[H_BITS-1:0];
    wire [H_BITS-1:0] last_row=math_h-1'b1;
    wire [W_BITS+1:0] row_bytes=is32 ? {math_w,2'b00} :
                                     {1'b0,math_w,1'b0}+{{2{1'b0}},math_w};
    wire [W_BITS+1:0] stride=(row_bytes+3)&~3;
    reg [W_BITS+H_BITS+1:0] payload_bytes;
    reg [63:0] required_size;
    assign in_ready=busy && (state==HEADER || state==SKIP || state==PIXELS ||
                            state==PAD || state==TRAIL) && (!pixel_valid || pixel_ready);
    assign pixel_rgb565={pixel_rgb888[23:19],pixel_rgb888[15:10],pixel_rgb888[7:3]};
    task fail;
        input [7:0] code;
        begin error<=1; error_code<=code; state<=FAILED; pixel_valid<=0; end
    endtask
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; busy<=0; done<=0; error<=0; error_code<=0;
            meta_valid<=0; width<=0; height<=0; top_down<=0;
            pixel_valid<=0; pixel_rgb888<=0; pixel_x<=0; pixel_y<=0;
            pixel_addr<=0; pixel_sof<=0; pixel_eol<=0; pixel_eof<=0;
            pos<=0; size_latched<=0; row_base<=0; x<=0; y<=0;
            rows<=0; component<=0; padding<=0; pad_left<=0;
            blue<=0; green<=0; red<=0; is32<=0; first_pixel<=1;
            payload_bytes<=0; required_size<=0;
        end else begin
            done<=0; meta_valid<=0;
            if (pixel_valid && pixel_ready) pixel_valid<=0;
            if (abort) begin busy<=0; state<=IDLE; pixel_valid<=0; end
            else if (start && !busy) begin
                busy<=1; state<=HEADER; pos<=0; size_latched<=file_size;
                error<=0; error_code<=0; pixel_valid<=0; first_pixel<=1;
            end else case (state)
                HEADER: if (in_valid && in_ready) begin
                    hdr[pos[5:0]]<=in_data; pos<=pos+1'b1;
                    if (in_last) fail(8'h24);
                    else if (pos==53) state<=CHECK;
                end
                CHECK: begin
                    if (hdr[0]!=8'h42 || hdr[1]!=8'h4d) fail(8'h20);
                    else if (dib_size<40 || {32'd0,off_bits}<({32'd0,dib_size}+64'd14) ||
                             planes!=1 || compression!=0 || (bpp!=24 && bpp!=32)) fail(8'h21);
                    else if (w==0 || w>MAX_WIDTH || w>65535 || h==0 || h>MAX_HEIGHT || h>65535 ||
                             w[31] || h_raw==32'h80000000) fail(8'h22);
                    else begin
                        width<=w[15:0]; height<=h[15:0]; top_down<=h_raw[31];
                        is32<=(bpp==32); state<=SIZE_MUL;
                    end
                end
                SIZE_MUL: begin
                    payload_bytes<=stride*math_h;
                    row_base<=top_down ? 0 : math_w*last_row;
                    padding<=stride-row_bytes;
                    state<=SIZE_ADD;
                end
                SIZE_ADD: begin
                    required_size<={32'd0,off_bits}+payload_bytes;
                    state<=SIZE_CHECK;
                end
                SIZE_CHECK: begin
                    if (required_size>{32'd0,size_latched} || declared_size>size_latched ||
                        (declared_size!=0 && {32'd0,declared_size}<required_size)) fail(8'h23);
                    else begin
                        rows<=0; x<=0; y<=top_down ? 0 : height-1'b1;
                        component<=0; meta_valid<=1;
                        state<=(off_bits==54) ? PIXELS : SKIP;
                    end
                end
                SKIP: if (in_valid && in_ready) begin
                    pos<=pos+1'b1;
                    if (in_last) fail(8'h24);
                    else if (pos+1'b1==off_bits) state<=PIXELS;
                end
                PIXELS: if (in_valid && in_ready) begin
                    pos<=pos+1'b1;
                    if (component==0) blue<=in_data;
                    if (component==1) green<=in_data;
                    if (component==2) red<=in_data;
                    if ((!is32 && component==2) || (is32 && component==3)) begin
                        pixel_rgb888<={is32 ? red : in_data,green,blue};
                        pixel_x<=x; pixel_y<=y; pixel_addr<=row_base+x;
                        pixel_sof<=first_pixel; first_pixel<=0;
                        pixel_eol<=(x==width-1'b1);
                        pixel_eof<=(x==width-1'b1 && rows==height-1'b1);
                        pixel_valid<=1; component<=0;
                        if (x==width-1'b1) begin
                            x<=0; rows<=rows+1'b1;
                            y<=top_down ? y+1'b1 : y-1'b1;
                            row_base<=top_down ? row_base+width : row_base-width;
                            pad_left<=padding;
                            if (padding!=0) state<=PAD;
                            else if (rows==height-1'b1) state<=TRAIL;
                        end else x<=x+1'b1;
                        if (in_last) begin
                            if (x==width-1'b1 && rows==height-1'b1 && padding==0)
                                state<=FINISH;
                            else fail(8'h24);
                        end
                    end else begin
                        component<=component+1'b1;
                        if (in_last) fail(8'h24);
                    end
                end
                PAD: if (in_valid && in_ready) begin
                    pos<=pos+1'b1; pad_left<=pad_left-1'b1;
                    if (pad_left==1) state<=(rows==height) ? TRAIL : PIXELS;
                    if (in_last) begin
                        if (pad_left==1 && rows==height) state<=FINISH;
                        else fail(8'h24);
                    end
                end
                TRAIL: if (in_valid && in_ready) begin
                    pos<=pos+1'b1;
                    if (in_last) state<=FINISH;
                end
                FINISH: if (!pixel_valid || pixel_ready) begin
                    done<=1; busy<=0; state<=IDLE;
                end
                FAILED: begin busy<=0; state<=IDLE; end
                default: begin end
            endcase
        end
    end
endmodule
