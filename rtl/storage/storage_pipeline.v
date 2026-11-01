// System-clock-domain storage subsystem. pixel_addr is a PIXEL index, not bytes.
// done permits a frame commit only AFTER the memory writer has drained too.
module storage_pipeline #(
    parameter CLK_HZ=50000000,
    parameter INIT_HALF_PERIOD=(CLK_HZ+799999)/800000,
    parameter READ_HALF_PERIOD=(CLK_HZ+49999999)/50000000,
    parameter MAX_WIDTH=1920, parameter MAX_HEIGHT=1080
)(
    input wire clk, input wire rst_n,
    output wire sd_cs_n, output wire sd_sck, output wire sd_mosi, input wire sd_miso,
    input wire start, input wire [15:0] file_index,
    input wire select_last, output wire [15:0] opened_index,
    output wire ready, output reg busy, output wire card_initialized,
    output reg done, output reg error, output reg [7:0] error_code,
    output wire [87:0] short_name, output wire [31:0] file_size,
    output wire meta_valid, output wire [15:0] width, height, output wire top_down,
    output wire pixel_valid, input wire pixel_ready,
    output wire [23:0] pixel_rgb888, output wire [15:0] pixel_rgb565,
    output wire [15:0] pixel_x, pixel_y, output wire [31:0] pixel_addr,
    output wire pixel_sof, pixel_eol, pixel_eof
);
    wire req_valid, req_ready, sec_valid, sec_ready, sec_last, sd_error;
    wire [7:0] sec_data, sd_code;
    wire [31:0] req_lba;
    wire fat_done, fat_error, file_open, file_valid, file_last, file_ready;
    wire [7:0] fat_code, file_data;
    wire bmp_done, bmp_error, bmp_ready;
    wire [7:0] bmp_code;
    reg file_finished, image_finished, parsing_started, parsing_failed;
    assign ready=card_initialized && !busy;
    wire launch=start && ready;
    assign file_ready=parsing_failed ? 1'b1 : bmp_ready;
    sd_spi_reader #(.CLK_HZ(CLK_HZ),.INIT_HALF_PERIOD(INIT_HALF_PERIOD),
        .READ_HALF_PERIOD(READ_HALF_PERIOD)) sd(
        .clk(clk),.rst_n(rst_n),.sd_cs_n(sd_cs_n),.sd_sck(sd_sck),
        .sd_mosi(sd_mosi),.sd_miso(sd_miso),.initialized(card_initialized),
        .high_capacity(),.req_valid(req_valid),.req_ready(req_ready),.req_lba(req_lba),
        .data(sec_data),.valid(sec_valid),.ready(sec_ready),.last(sec_last),
        .done(),.error(sd_error),.error_code(sd_code));
    fat32_bmp_reader fat(
        .clk(clk),.rst_n(rst_n),.start(launch),.file_index(file_index),
        .select_last(select_last),.opened_index(opened_index),
        .busy(),.done(fat_done),.error(fat_error),.error_code(fat_code),
        .file_open(file_open),.file_size(file_size),.short_name(short_name),
        .data(file_data),.valid(file_valid),.last(file_last),.ready(file_ready),
        .req_valid(req_valid),.req_ready(req_ready),.req_lba(req_lba),
        .sec_data(sec_data),.sec_valid(sec_valid),.sec_last(sec_last),
        .sec_ready(sec_ready),.sec_error(sd_error));
    bmp_stream_decoder #(.MAX_WIDTH(MAX_WIDTH),.MAX_HEIGHT(MAX_HEIGHT)) bmp(
        .clk(clk),.rst_n(rst_n),.start(file_open),.abort(busy && fat_error),
        .file_size(file_size),.in_data(file_data),
        .in_valid(file_valid && !parsing_failed),.in_last(file_last),.in_ready(bmp_ready),
        .busy(),.done(bmp_done),.error(bmp_error),.error_code(bmp_code),
        .meta_valid(meta_valid),.width(width),.height(height),.top_down(top_down),
        .pixel_valid(pixel_valid),.pixel_ready(pixel_ready),
        .pixel_rgb888(pixel_rgb888),.pixel_rgb565(pixel_rgb565),
        .pixel_x(pixel_x),.pixel_y(pixel_y),.pixel_addr(pixel_addr),
        .pixel_sof(pixel_sof),.pixel_eol(pixel_eol),.pixel_eof(pixel_eof));
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            busy<=0; done<=0; error<=0; error_code<=0;
            file_finished<=0; image_finished<=0; parsing_started<=0; parsing_failed<=0;
        end else begin
            done<=0;
            if(!card_initialized && sd_error) begin error<=1; error_code<=sd_code; end
            if(launch) begin
                busy<=1; error<=0; error_code<=0;
                file_finished<=0; image_finished<=0; parsing_started<=0; parsing_failed<=0;
            end else if(busy) begin
                if(file_open) parsing_started<=1;
                if(fat_done) file_finished<=1;
                if(bmp_done) image_finished<=1;
                if(parsing_started && bmp_error) begin
                    parsing_failed<=1; error<=1; error_code<=bmp_code;
                end
                if(fat_error) begin
                    error<=1; error_code<=(fat_code==8'h30) ? sd_code : fat_code; busy<=0;
                end else if((file_finished || fat_done) &&
                            (image_finished || bmp_done || parsing_failed)) begin
                    busy<=0;
                    if(!parsing_failed) done<=1;
                end
            end
        end
    end
endmodule
