// Independent FAT/WAV context sharing sectors with the image reader. A 4096
// frame BRAM FIFO separates burst SD reads from the exact 48 kHz HDMI cadence.
module wav_audio_player #(
    parameter CLK_HZ=50000000,BUFFER_AWIDTH=12,PREFILL_FRAMES=1024,MAX_WAV_FILES=256
)(
    input wire clk,rst_n,enable,mute,card_initialized,sink_active,sink_ready,
    output reg [31:0] audio_sample,output reg audio_valid,
    output reg [2:0] audio_tag, // {enabled, real file sample, loop first}; aligned with audio_sample
    output reg playing, // registered status only; never changes audio flow
    output wire error,output wire [7:0] error_code,
    output wire req_valid,output wire [31:0] req_lba,input wire req_ready,
    input wire [7:0] sec_data,input wire sec_valid,sec_last,sec_error,
    input wire [7:0] sec_error_code,output wire sec_ready,output wire reader_enabled
);
    localparam WAIT=0,START=1,ACTIVE=2,RETRY=3,FAULT=4;
    reg [2:0] state;
    reg attempt_reset,fault,selected,file_finished,pcm_finished;
    reg primed;
    reg [7:0] fault_code;
    reg [15:0] file_index;
    wire file_reset_n=rst_n && enable && !attempt_reset && !fault;
    assign reader_enabled=file_reset_n;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)playing<=0;
        else playing<=enable && primed && !fault && sink_active;
    end
    wire fat_done,fat_error,file_open,file_valid,file_last,file_ready;
    wire [7:0] fat_code,file_data;
    wire [31:0] file_size;
    wire pcm_done,pcm_error,format_valid;
    wire [7:0] pcm_code;
    wire [31:0] pcm_sample;
    wire pcm_valid,pcm_ready,pcm_first;
    fat32_bmp_reader #(.FILE_EXTENSION(24'h574156),.MIN_FILE_BYTES(12),.MAX_FILE_BYTES(536870912)) fat(
        .clk(clk),.rst_n(file_reset_n),.start(state==START),.file_index(file_index),
        .select_last(1'b0),.opened_index(),.busy(),.done(fat_done),.error(fat_error),.error_code(fat_code),
        .file_open(file_open),.file_size(file_size),.short_name(),.data(file_data),.valid(file_valid),
        .last(file_last),.ready(file_ready),.req_valid(req_valid),.req_ready(req_ready),.req_lba(req_lba),
        .sec_data(sec_data),.sec_valid(sec_valid),.sec_last(sec_last),.sec_ready(sec_ready),.sec_error(sec_error));
    // One-byte elastic register breaks the sector-RAM mux to RIFF bounds-check
    // path without changing the valid/ready contract or dropping stalled bytes.
    reg [7:0] pipe_data;
    reg pipe_valid,pipe_last;
    wire decoder_ready;
    assign file_ready=!pipe_valid || decoder_ready;
    always @(posedge clk or negedge file_reset_n)begin
        if(!file_reset_n)begin pipe_data<=0;pipe_valid<=0;pipe_last<=0;end
        else if(file_ready)begin
            pipe_valid<=file_valid;
            if(file_valid)begin pipe_data<=file_data;pipe_last<=file_last;end
        end
    end
    wav_stream_decoder decoder(
        .clk(clk),.rst_n(file_reset_n),.start(file_open),.file_size(file_size),
        .data(pipe_data),.valid(pipe_valid),.last(pipe_last),.ready(decoder_ready),
        .sample(pcm_sample),.sample_valid(pcm_valid),.sample_ready(pcm_ready),
        .sample_first(pcm_first),.format_valid(format_valid),.done(pcm_done),.error(pcm_error),.error_code(pcm_code));
    wire fifo_reset_n=rst_n && enable && !fault;
    wire [31:0] buffered_sample;wire buffered_first;
    wire buffered_valid,pop;
    wire [BUFFER_AWIDTH+1:0] level;
    pcm_sample_fifo #(.AW(BUFFER_AWIDTH),.WIDTH(33)) buffer(
        .clk(clk),.rst_n(fifo_reset_n),.in_data({pcm_first,pcm_sample}),.in_valid(pcm_valid && file_reset_n),
        .in_ready(pcm_ready),.out_data({buffered_first,buffered_sample}),.out_valid(buffered_valid),.out_ready(pop),.level(level));
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=WAIT;attempt_reset<=1;fault<=0;fault_code<=0;selected<=0;file_index<=0;
            file_finished<=0;pcm_finished<=0;
        end else if(!enable)begin
            state<=WAIT;attempt_reset<=1;fault<=0;fault_code<=0;selected<=0;file_index<=0;
            file_finished<=0;pcm_finished<=0;
        end else case(state)
            WAIT:if(card_initialized)begin attempt_reset<=0;state<=START;end
            START:begin state<=ACTIVE;file_finished<=0;pcm_finished<=0;end
            RETRY:begin attempt_reset<=0;state<=START;end
            ACTIVE:begin
                if(format_valid)selected<=1;
                if(fat_done)file_finished<=1;
                if(pcm_done)pcm_finished<=1;
                if(fat_error || pcm_error)begin
                    attempt_reset<=1;
                    if(!selected && (pcm_error || (fat_error && fat_code==8'h37)) && file_index<MAX_WAV_FILES-1)begin
                        file_index<=file_index+1'b1;state<=RETRY;
                    end else begin
                        fault<=1;state<=FAULT;
                        fault_code<=fat_error ? (fat_code==8'h30 ? sec_error_code : fat_code==8'h36 ? 8'hB6 : fat_code) : 8'hB7;
                    end
                end else if((file_finished || fat_done) && (pcm_finished || pcm_done))state<=START;
            end
            default:begin end
        endcase
    end
    // Keep sending correctly paced digital silence when stopped, muted, waiting
    // for startup prefill or recovering from a late card. No burst playback.
    localparam ACC_BITS=$clog2(CLK_HZ+48000);
    reg [ACC_BITS-1:0] phase;
    reg underflow,backpressure;
    wire tick=sink_active && phase>=CLK_HZ-48000;
    assign pop=tick && sink_ready && fifo_reset_n && primed && buffered_valid;
    assign error=fault || underflow || backpressure;
    assign error_code=fault ? fault_code : underflow ? 8'hB8 : backpressure ? 8'hB9 : 8'd0;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin phase<=0;primed<=0;audio_valid<=0;audio_sample<=0;audio_tag<=0;underflow<=0;backpressure<=0;end
        else begin
            audio_valid<=0;
            if(!enable)begin underflow<=0;backpressure<=0;end
            if(!fifo_reset_n)primed<=0;
            else if(level>=PREFILL_FRAMES)primed<=1;
            if(!sink_active)phase<=0;
            else if(tick)begin
                phase<=phase+48000-CLK_HZ;
                if(sink_ready)begin
                    audio_valid<=1;
                    audio_sample<=pop && !mute ? buffered_sample : 32'd0;
                    audio_tag<={enable && !fault,pop,pop && buffered_first};
                    if(fifo_reset_n && primed && !buffered_valid)begin underflow<=1;primed<=0;end
                end else if(enable)backpressure<=1;
            end else phase<=phase+48000;
        end
    end
endmodule
