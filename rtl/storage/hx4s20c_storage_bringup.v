// Standalone read-only board test; consumes pixels, does not drive HDMI/SDRAM.
// Hold KEY1 (A2) after programming, then release to read root BMP index zero.
module hx4s20c_storage_bringup #(
    parameter CLK_HZ=50000000,
    parameter READ_HALF_PERIOD=2
)(
    input wire clk, input wire reset_key_n,
    output wire sd_cs_n, output wire sd_sck, output wire sd_mosi,
    input wire sd_miso,
    output wire [3:0] led
);
    wire sys_clk;
    EG_LOGIC_BUFG clock_buffer(.i(clk),.o(sys_clk));
    reg [2:0] reset_release;
    always @(posedge sys_clk or negedge reset_key_n) begin
        if(!reset_key_n) reset_release<=0;
        else reset_release<={reset_release[1:0],1'b1};
    end
    wire rst_n=reset_release[2];
    wire ready,busy,initialized,done,error,meta_valid,pixel_valid;
    wire [7:0] pipeline_error_code;
    wire [15:0] width,height;
    wire [23:0] rgb;
    reg started,meta_seen,passed,count_error;
    (* keep = "true" *) reg [31:0] pixel_count;
    (* keep = "true" *) reg [31:0] rgb_sum;
    (* keep = "true" *) reg [31:0] load_cycles;
    (* keep = "true" *) reg [7:0] debug_error_code;
    reg [31:0] expected_pixels;
    wire launch=ready && !started;
    assign led={error || count_error,passed,busy,initialized};
    storage_pipeline #(.CLK_HZ(CLK_HZ),.READ_HALF_PERIOD(READ_HALF_PERIOD),
        .MAX_WIDTH(640),.MAX_HEIGHT(480)) storage(
        .clk(sys_clk),.rst_n(rst_n),.sd_cs_n(sd_cs_n),.sd_sck(sd_sck),
        .sd_mosi(sd_mosi),.sd_miso(sd_miso),.start(launch),.file_index(16'd0),
        .ready(ready),.busy(busy),.card_initialized(initialized),.done(done),
        .error(error),.error_code(pipeline_error_code),.short_name(),.file_size(),
        .meta_valid(meta_valid),.width(width),.height(height),.top_down(),
        .pixel_valid(pixel_valid),.pixel_ready(1'b1),.pixel_rgb888(rgb),
        .pixel_rgb565(),.pixel_x(),.pixel_y(),.pixel_addr(),
        .pixel_sof(),.pixel_eol(),.pixel_eof());
    always @(posedge sys_clk or negedge rst_n) begin
        if(!rst_n) begin
            started<=0; meta_seen<=0; passed<=0; count_error<=0;
            pixel_count<=0; rgb_sum<=0; load_cycles<=0;
            expected_pixels<=0; debug_error_code<=0;
        end else begin
            if(launch) started<=1;
            if(busy) load_cycles<=load_cycles+1'b1;
            if(meta_valid) begin meta_seen<=1; expected_pixels<=width*height; end
            if(pixel_valid) begin
                pixel_count<=pixel_count+1'b1;
                rgb_sum<=rgb_sum+{8'd0,rgb};
            end
            if(error) debug_error_code<=pipeline_error_code;
            if(done) begin
                if(meta_seen && pixel_count==expected_pixels) passed<=1;
                else begin count_error<=1; debug_error_code<=8'hf0; end
            end
        end
    end
endmodule
