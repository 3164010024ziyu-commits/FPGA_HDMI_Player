// Image-paired WAV reader. Two 2048-frame PCM banks use the same total payload
// capacity as the former 4096-frame background-audio FIFO. Prepare the next
// bank after BMP input completes; keep playing the old bank until video fades.
module wav_image_player #(
 parameter CLK_HZ=50000000,BUFFER_AWIDTH=11,PREFILL_FRAMES=1024
)(
 input wire clk,rst_n,select_track,play_start,pause,
 input wire [63:0] track_name,
 input wire card_initialized,sink_active,sink_ready,
 output reg track_ready,output reg playing,
 output reg [31:0] audio_sample,output reg audio_valid,
 output reg [2:0] audio_tag,output reg audio_epoch,
 output wire error,output wire [7:0] error_code,
 output wire req_valid,output wire [31:0] req_lba,input wire req_ready,
 input wire [7:0] sec_data,input wire sec_valid,sec_last,sec_error,
 input wire [7:0] sec_error_code,output wire sec_ready,output wire reader_enabled
);
 localparam WAIT=0,RELEASE=1,START=2,READ=3,FAULT=4;
 reg [2:0]state;
 reg reader_hold,fill_bank,play_bank,active_valid,epoch;
 // Dedicated one-hot reset registers: decoding clear AND a changing bank bit
 // could glitch-reset the active FIFO when selecting the other bank.
 reg [1:0]clear_banks;
 reg prepared_fault,file_finished,pcm_finished,underflow,backpressure;
 reg [7:0]fault_code;reg [63:0]name;
 wire file_reset_n=rst_n && !reader_hold && !prepared_fault;
 assign reader_enabled=file_reset_n;
 wire fat_done,fat_error,file_open,file_valid,file_last,file_ready;
 wire [7:0]fat_code,file_data;wire [31:0]file_size;
 fat32_bmp_reader #(.FILE_EXTENSION(24'h574156),.MIN_FILE_BYTES(12),
  .MAX_FILE_BYTES(536870912),.ENABLE_NAME_MATCH(1)) fat(
  .clk(clk),.rst_n(file_reset_n),.start(state==START),.file_index(16'd0),
  .match_name(name),.select_last(1'b0),.opened_index(),.busy(),.done(fat_done),.error(fat_error),.error_code(fat_code),
  .file_open(file_open),.file_size(file_size),.short_name(),.data(file_data),.valid(file_valid),.last(file_last),.ready(file_ready),
  .req_valid(req_valid),.req_ready(req_ready),.req_lba(req_lba),.sec_data(sec_data),.sec_valid(sec_valid),.sec_last(sec_last),.sec_ready(sec_ready),.sec_error(sec_error),
  .aux_kind(2'd0),.aux_offset(32'd0),.aux_length(16'd0));
 reg [7:0]pipe_data;reg pipe_valid,pipe_last;
 wire decoder_ready,pcm_done,pcm_error,format_valid,pcm_valid,pcm_ready,pcm_first;
 wire [7:0]pcm_code;wire [31:0]pcm_sample;
 assign file_ready=!pipe_valid || decoder_ready;
 always @(posedge clk or negedge file_reset_n)begin
  if(!file_reset_n)begin pipe_data<=0;pipe_valid<=0;pipe_last<=0;end
  else if(file_ready)begin pipe_valid<=file_valid;pipe_data<=file_data;pipe_last<=file_last;end
 end
 wav_stream_decoder decoder(.clk(clk),.rst_n(file_reset_n),.start(file_open),.file_size(file_size),
  .data(pipe_data),.valid(pipe_valid),.last(pipe_last),.ready(decoder_ready),
  .sample(pcm_sample),.sample_valid(pcm_valid),.sample_ready(pcm_ready),.sample_first(pcm_first),
  .format_valid(format_valid),.done(pcm_done),.error(pcm_error),.error_code(pcm_code));
 wire [31:0]sample0,sample1;wire first0,first1,valid0,valid1,ready0,ready1;
 wire [BUFFER_AWIDTH+1:0]level0,level1;
 wire [BUFFER_AWIDTH+1:0]fill_level=fill_bank ? level1:level0;
 wire buffered_valid=play_bank ? valid1:valid0;
 wire [31:0]buffered_sample=play_bank ? sample1:sample0;
 wire buffered_first=play_bank ? first1:first0;
 wire pop;
 assign pcm_ready=fill_bank ? ready1:ready0;
 pcm_sample_fifo #(.AW(BUFFER_AWIDTH),.WIDTH(33)) bank0(
  .clk(clk),.rst_n(rst_n && !clear_banks[0]),
  .in_data({pcm_first,pcm_sample}),.in_valid(pcm_valid && file_reset_n && !fill_bank),.in_ready(ready0),
  .out_data({first0,sample0}),.out_valid(valid0),.out_ready(pop && !play_bank),.level(level0));
 pcm_sample_fifo #(.AW(BUFFER_AWIDTH),.WIDTH(33)) bank1(
  .clk(clk),.rst_n(rst_n && !clear_banks[1]),
  .in_data({pcm_first,pcm_sample}),.in_valid(pcm_valid && file_reset_n && fill_bank),.in_ready(ready1),
  .out_data({first1,sample1}),.out_valid(valid1),.out_ready(pop && play_bank),.level(level1));
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=WAIT;reader_hold<=1;clear_banks<=0;fill_bank<=1;play_bank<=0;active_valid<=0;epoch<=0;
   prepared_fault<=0;fault_code<=0;name<=0;track_ready<=0;file_finished<=0;pcm_finished<=0;playing<=0;
  end else begin
   playing<=active_valid && sink_active;
   clear_banks<=0;
   if(select_track)begin
    name<=track_name;fill_bank<=!play_bank;clear_banks<=play_bank ? 2'b01:2'b10;reader_hold<=1;
    state<=RELEASE;prepared_fault<=0;fault_code<=0;track_ready<=0;file_finished<=0;pcm_finished<=0;
   end else begin
    if(!prepared_fault && !reader_hold && (fill_level>=PREFILL_FRAMES || (pcm_finished && fill_level!=0)))track_ready<=1;
    case(state)
     RELEASE:if(card_initialized)begin reader_hold<=0;state<=START;end
     START:begin state<=READ;file_finished<=0;pcm_finished<=0;end
     READ:begin
      if(fat_done)file_finished<=1;if(pcm_done)pcm_finished<=1;
      if(fat_error || pcm_error)begin
       prepared_fault<=1;reader_hold<=1;state<=FAULT;track_ready<=1;
       fault_code<=fat_error ? (fat_code==8'h30 ? sec_error_code : fat_code==8'h36 ? 8'hB6 : fat_code) : 8'hB7;
       if(fill_bank==play_bank)active_valid<=0;
      end else if((file_finished || fat_done) && (pcm_finished || pcm_done))state<=START;
     end
     default:begin end
    endcase
   end
   if(play_start && track_ready)begin play_bank<=fill_bank;active_valid<=!prepared_fault;epoch<=!epoch;end
  end
 end
 localparam ACC_BITS=$clog2(CLK_HZ+48000);
 reg [ACC_BITS-1:0]phase;
 wire tick=sink_active && phase>=CLK_HZ-48000;
 assign pop=tick && sink_ready && active_valid && !pause && buffered_valid && !play_start;
 assign error=prepared_fault || underflow || backpressure;
 assign error_code=prepared_fault ? fault_code : underflow ? 8'hB8 : backpressure ? 8'hB9 : 8'd0;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin phase<=0;audio_valid<=0;audio_sample<=0;audio_tag<=0;audio_epoch<=0;underflow<=0;backpressure<=0;end
  else begin
   audio_valid<=0;
   if(select_track)begin underflow<=0;backpressure<=0;end
   if(!sink_active)phase<=0;
   else if(tick)begin
    phase<=phase+48000-CLK_HZ;
    if(sink_ready)begin
     audio_valid<=1;audio_epoch<=epoch;audio_sample<=pop ? buffered_sample : 32'd0;
     audio_tag<={active_valid,pop,pop && buffered_first};
     if(active_valid && !pause && !buffered_valid && !play_start)underflow<=1;
    end else if(active_valid)backpressure<=1;
   end else phase<=phase+48000;
  end
 end
endmodule
