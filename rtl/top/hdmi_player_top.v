`include "../../include/global_def.v"

// Storage -> asynchronous write FIFO -> SDRAM double buffer -> asynchronous
// display FIFO -> HDMI. Source completion and SDRAM completion are distinct.
module hdmi_player_top #(
    parameter integer CLK_HZ = 50000000,
    parameter integer ENABLE_AUDIO = 0,
    parameter integer ENABLE_FADE = 0,
    parameter integer FADE_STEP = 1,
    parameter integer INIT_HALF_PERIOD = (CLK_HZ+799999)/800000,
    parameter integer READ_HALF_PERIOD = (CLK_HZ+49999999)/50000000,
    parameter integer MAX_WIDTH = 640,
    parameter integer MAX_HEIGHT = 480
)(
    input wire SYS_CLK,
    input wire Reset_n,
    input wire audio_enable,audio_mute,
    output wire audio_error,output wire [7:0] audio_error_code,

    // One request in the SYS_CLK domain; configuration is sampled on acceptance.
    input wire start,   //整个模块外部的开始信号
    input wire select_last,
    output wire [15:0] opened_file_index,
    input wire [15:0] file_index,   //要读取 SD 卡中的哪张图片
    input wire [`ADDR_WIDTH-1:0] frame_base_addr,
    // image adjustment keys: {CON-, CON+, BRT-, BRT+}, pressed = 0
    input wire [3:0] key_img,
    output wire load_ready,
    output wire load_busy,
    output wire load_done,
    output wire load_error,
    output wire [7:0] load_error_code,
    output wire card_initialized,
    output wire [3:0] debug_error_flags, // {load, refresh, read timeout, FIFO underflow}

    output wire sd_cs_n,
    output wire sd_sck,
    output wire sd_mosi,
    input wire sd_miso,

    
    output wire memory_frame_write_done,    //这张图片是否已经完整写入 SDRAM
    output wire LED,
    output wire display_ready,
    output wire display_underflow,
    output wire HDMI_CLK_P,
    output wire HDMI_D2_P,
    output wire HDMI_D1_P,
    output wire HDMI_D0_P
);
    reg [1:0] reset_release;
    always @(posedge SYS_CLK or negedge Reset_n) begin
        if (!Reset_n) reset_release <= 2'b00;
        else reset_release <= {reset_release[0],1'b1};
    end
    wire sys_reset_n = reset_release[1];    //同步复位

    
    wire memory_initialized;
    reg [1:0] memory_init_sync;
    always @(posedge SYS_CLK or negedge sys_reset_n) begin
        if (!sys_reset_n) memory_init_sync <= 2'b00;
        else memory_init_sync <= {memory_init_sync[0],memory_initialized};
    end
    assign LED = memory_initialized;    //LED = lock && Sdr_init_done
    //memory_init_sync[1] == 1代表 Memory 报告初始化完成

    reg frame_in_progress;  //当前已有一张图片任务正在执行
    reg frame_done_low_seen;    //已观察到本次任务对应的完成信号处于低电平
    reg frame_metadata_seen;    //本次任务已经产生过有效帧描述
    wire frame_write_ready, frame_buffer_error;
    wire storage_start;
    wire storage_done, storage_error;
    wire [7:0] storage_error_code;
    reg format_error;
    always @(posedge SYS_CLK or negedge sys_reset_n) begin
        if(!sys_reset_n) format_error <= 0;
        else if(storage_start) format_error <= 0;
        else if(frame_buffer_error) format_error <= 1;
    end
    assign load_done = storage_done && !format_error;
    assign load_error = storage_error || format_error;
    assign load_error_code = format_error ? 8'hE1 : storage_error_code;
    // Unsupported geometry cancels the source transaction rather than leaving
    // storage blocked on pixel_ready. Card initialization is then repeated.
    reg [1:0] storage_release;
    wire storage_reset_req = !sys_reset_n || frame_buffer_error;
    always @(posedge SYS_CLK or posedge storage_reset_req) begin
        if(storage_reset_req) storage_release <= 0;
        else storage_release <= {storage_release[0],1'b1};
    end
    wire storage_reset_n = storage_release[1];
    wire storage_ready; //ready = card_initialized && !busy;
    assign storage_start = start && load_ready;
    assign load_ready = sys_reset_n && memory_init_sync[1] && storage_ready && frame_write_ready && !frame_in_progress;
                        // 系统复位已经解除；
                        // Memory 报告初始化完成；
                        // SD 卡已经初始化；
                        // Storage 当前不忙。
                        // 初次空闲或本帧已完成下游写入

    reg [`ADDR_WIDTH-1:0] selected_frame_base;
    always @(posedge SYS_CLK or negedge sys_reset_n) begin
        if (!sys_reset_n) selected_frame_base <= 0;
        else if (storage_start) selected_frame_base <= frame_base_addr;
    end

    wire storage_pixel_valid;
    wire [23:0] pixel_rgb888;
    wire memory_pixel_ready;
    wire storage_pixel_ready = sys_reset_n && memory_init_sync[1] && memory_pixel_ready;
                                // 系统复位已经解除；
                                // Memory 报告初始化完成；
                                // Memory可以接收数据
    wire pixel_transfer = storage_pixel_valid && storage_pixel_ready;

    wire image_meta_valid;
    wire [15:0] image_width;
    wire [15:0] image_height;
    wire image_top_down;

    // Accept the first frame while idle. Later frames must observe their own
    // done level go low then high, rather than reusing the previous frame's 1.
    always @(posedge SYS_CLK or negedge sys_reset_n) begin
        if(!sys_reset_n) begin
            frame_in_progress <= 0;
            frame_done_low_seen <= 0;
            frame_metadata_seen <= 0;
        end
        else if(storage_start) begin
            frame_in_progress <= 1;
            frame_done_low_seen <= 0;
            frame_metadata_seen <= 0;
        end
        else if(frame_in_progress) begin
            if(image_meta_valid) frame_metadata_seen <= 1;
            if(!memory_frame_write_done) frame_done_low_seen <= 1;
            if((frame_done_low_seen && memory_frame_write_done && storage_ready) ||
                //已经观察到本次任务的完成信号为低,随后完成信号变为高,Storage 已经恢复空闲。
               (load_error && storage_ready && frame_write_ready))
                frame_in_progress <= 0;
        end
    end

    wire display_clk, display_reset_n, display_frame_sync, display_pixel_req;
    wire [23:0] display_rgb;
    wire display_valid;
    wire [5:0] display_fade_level;

    // The image path is connected here. Audio/OSD remain available in the
    // display component for a later integration; this system supplies video.
    wire [31:0] audio_sample;
    wire audio_valid,audio_ready;
    reg [1:0] audio_sink_sync;
    always @(posedge SYS_CLK or negedge sys_reset_n)begin
        if(!sys_reset_n)audio_sink_sync<=0;
        else audio_sink_sync<={audio_sink_sync[0],display_reset_n};
    end
    hdmi_tx_display #(.AUDIO_FS(48000),.HDMI_AUDIO_EN(ENABLE_AUDIO),.HDMI_SUBTITLE_EN(0),.IMAGE_FADE_EN(ENABLE_FADE)) u_display (
        .sys_clk(SYS_CLK), .sys_rst_n(sys_reset_n && memory_initialized),
        .fade_level(display_fade_level),.pix_rgb(display_rgb), .pix_valid(display_valid), .frame_ready(display_ready),
        .pix_underflow(display_underflow), .pix_clk(display_clk), .pix_reset_n(display_reset_n),
        .pix_req(display_pixel_req), .frame_sync(display_frame_sync),
        .audio_clk(SYS_CLK), .audio_sample(audio_sample), .audio_valid(audio_valid),
        .audio_ready(audio_ready), .audio_status(), .audio_pkt(), .key_in(7'h7f),
        .key_img(key_img),
        .osd_slot(1'b0), .osd_char_idx(4'd0), .osd_char_code(16'd0), .osd_char_we(1'b0),
        .osd_y(10'd0), .osd_fg(24'hffffff),
        .HDMI_CLK_P(HDMI_CLK_P), .HDMI_D2_P(HDMI_D2_P),
        .HDMI_D1_P(HDMI_D1_P), .HDMI_D0_P(HDMI_D0_P)
    );

    wire [2:0] memory_error_flags;
    assign debug_error_flags = {load_error,memory_error_flags};
    memory_top #(.ENABLE_FADE(ENABLE_FADE),.FADE_STEP(FADE_STEP)) u_memory (
        .display_fade_level(display_fade_level),
        .debug_error_flags(memory_error_flags),
        .SYS_CLK(SYS_CLK),
        .Reset_n(sys_reset_n),
        .pixel_valid(pixel_transfer),
        .pixel_data(pixel_rgb888),
        .pixel_ready(memory_pixel_ready),
        .frame_start(image_meta_valid),
        .frame_base_addr(selected_frame_base),
        .frame_width(image_width),
        .frame_height(image_height),
        .frame_top_down(image_top_down),
        .frame_end(load_done),
        .frame_abort(storage_error),
        .frame_write_ready(frame_write_ready),
        .frame_error(frame_buffer_error),
        .display_clk(display_clk),
        .display_reset_n(display_reset_n),
        .display_frame_sync(display_frame_sync),
        .display_pixel_req(display_pixel_req),
        .display_pixel_rgb(display_rgb),
        .display_pixel_valid(display_valid),
        .display_frame_ready(display_ready),
        .display_underflow(display_underflow),
        .frame_write_done_sync(memory_frame_write_done),
        .LED(memory_initialized)
    );

    storage_pipeline #(
        .ENABLE_AUDIO(ENABLE_AUDIO),
        .CLK_HZ(CLK_HZ),
        .INIT_HALF_PERIOD(INIT_HALF_PERIOD),
        .READ_HALF_PERIOD(READ_HALF_PERIOD),
        .MAX_WIDTH(MAX_WIDTH),
        .MAX_HEIGHT(MAX_HEIGHT)
    ) u_storage_pipeline (
        .clk(SYS_CLK),
        .rst_n(storage_reset_n),
        .audio_enable(audio_enable),.audio_mute(audio_mute),.audio_sink_active(audio_sink_sync[1]),
        .audio_ready(audio_ready),.audio_sample(audio_sample),.audio_valid(audio_valid),
        .audio_error(audio_error),.audio_error_code(audio_error_code),
        .sd_cs_n(sd_cs_n),
        .sd_sck(sd_sck),
        .sd_mosi(sd_mosi),
        .sd_miso(sd_miso),
        .start(storage_start),
        .file_index(file_index),.select_last(select_last),.opened_index(opened_file_index),
        .ready(storage_ready),
        .busy(load_busy),
        .card_initialized(card_initialized),
        .done(storage_done),
        .error(storage_error),
        .error_code(storage_error_code),
        .short_name(),
        .file_size(),
        .meta_valid(image_meta_valid),
        .width(image_width),
        .height(image_height),
        .top_down(image_top_down),
        .pixel_valid(storage_pixel_valid),
        .pixel_ready(storage_pixel_ready),
        .pixel_rgb888(pixel_rgb888),
        .pixel_rgb565(),
        .pixel_x(),
        .pixel_y(),
        // This design computes pixel addresses in memory from frame metadata.
        .pixel_addr(),
        .pixel_sof(),
        .pixel_eol(),
        .pixel_eof()
    );
endmodule
