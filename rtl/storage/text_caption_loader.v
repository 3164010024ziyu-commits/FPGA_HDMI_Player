// Load a UTF-8 caption and its glyphs through the existing image FAT reader.
// FONT16.BIN is indexed by Unicode scalar value: 32 bytes, big-endian rows.
module text_caption_loader #(parameter PAIRED_TEXT=0)(
    input wire clk,rst_n,start,cache_ready,
    output reg done,
    output reg job_start,output reg [1:0] job_kind,
    output reg [31:0] job_offset,output reg [15:0] job_length,
    input wire file_done,file_error,input wire [7:0] file_code,
    input wire [7:0] data,input wire valid,output wire ready,
    output reg glyph_we,output reg [9:0] glyph_addr,output reg [15:0] glyph_data,
    output reg commit,output reg [6:0] length,output reg has_text,
    output reg [7:0] status
);
    localparam IDLE=0,WAIT_CACHE=1,TEXT_START=2,TEXT_READ=3,
               POINT_WAIT=4,FONT_START=5,FONT_READ=6,PUBLISH=7,FINISH=8,JOB_WAIT=9,PROBE_START=10,PROBE_READ=11;
    reg [3:0] state;
    reg [20:0] points[0:63];
    reg point_we;reg [5:0] point_waddr,glyph_index;
    reg [20:0] point_wdata,point_rdata;
    always @(posedge clk)begin
        if(point_we)points[point_waddr]<=point_wdata;
        point_rdata<=points[glyph_index];
    end
    reg byte_full,text_finished;
    reg [7:0] queued,high_byte;
    reg [1:0] continuation;
    reg [20:0] accumulator,minimum;
    reg first_character,skip_lf;
    reg [5:0] font_bytes;
    wire [20:0] combined={accumulator[14:0],queued[5:0]};
    assign ready=state==TEXT_READ ? !byte_full : state==FONT_READ;

    task store_point;
        input [20:0] value;
        reg [20:0] normalized;
        begin
            normalized=(value==9 || value==10 || value==13) ? 21'd32 : value;
            first_character<=0;skip_lf<=value==13;
            if(!(first_character && value==21'hfeff) && !(skip_lf && value==10) &&
               !(value<32 && value!=9 && value!=10 && value!=13) && length<64)begin
                point_we<=1;point_waddr<=length[5:0];point_wdata<=normalized;length<=length+1'b1;
            end
        end
    endtask
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;done<=0;job_start<=0;job_kind<=0;job_offset<=0;job_length<=0;
            glyph_we<=0;glyph_addr<=0;glyph_data<=0;commit<=0;length<=0;has_text<=0;status<=0;
            point_we<=0;point_waddr<=0;point_wdata<=0;glyph_index<=0;
            byte_full<=0;text_finished<=0;queued<=0;high_byte<=0;
            continuation<=0;accumulator<=0;minimum<=0;first_character<=1;skip_lf<=0;font_bytes<=0;
        end else begin
            done<=0;job_start<=0;glyph_we<=0;point_we<=0;commit<=0;
            case(state)
                IDLE:if(start)begin
                    state<=WAIT_CACHE;length<=0;has_text<=0;status<=0;glyph_index<=0;
                    byte_full<=0;text_finished<=0;continuation<=0;first_character<=1;skip_lf<=0;
                end
                WAIT_CACHE:if(cache_ready)state<=PAIRED_TEXT!=0 ? PROBE_START : TEXT_START;
                PROBE_START:begin job_kind<=3;job_offset<=0;job_length<=0;job_start<=1;state<=JOB_WAIT;end
                PROBE_READ:begin
                    if(file_done)state<=TEXT_START;
                    if(file_error)begin status<=file_code;state<=PUBLISH;end
                end
                TEXT_START:begin job_kind<=1;job_offset<=0;job_length<=512;job_start<=1;state<=JOB_WAIT;end
                // The FAT reader consumes registered job_start on this edge.
                // Its sticky previous error is cleared by that same edge;
                // sample completion/error only from the following cycle.
                JOB_WAIT:state<=job_kind==3 ? PROBE_READ : job_kind==1 ? TEXT_READ : FONT_READ;
                TEXT_READ:begin
                    if(valid && ready)begin queued<=data;byte_full<=1;end
                    if(file_done)text_finished<=1;
                    if(byte_full)begin
                        byte_full<=0;
                        if(length==64)continuation<=0;
                        else if(continuation!=0)begin
                            if(queued[7:6]!=2'b10)begin
                                // Reprocess this byte after replacing the unfinished sequence.
                                store_point(21'hfffd);continuation<=0;byte_full<=1;status<=8'h91;
                            end else if(continuation==1)begin
                                continuation<=0;
                                if(combined<minimum || combined>21'h10ffff ||
                                   (combined>=21'hd800 && combined<=21'hdfff))begin
                                    store_point(21'hfffd);status<=8'h91;
                                end else store_point(combined);
                            end else begin accumulator<=combined;continuation<=continuation-1'b1;end
                        end else if(queued<8'h80)store_point({13'd0,queued});
                        else if(queued>=8'hc2 && queued<=8'hdf)begin
                            continuation<=1;accumulator<={16'd0,queued[4:0]};minimum<=128;
                        end else if(queued>=8'he0 && queued<=8'hef)begin
                            continuation<=2;accumulator<={17'd0,queued[3:0]};minimum<=2048;
                        end else if(queued>=8'hf0 && queued<=8'hf4)begin
                            continuation<=3;accumulator<={18'd0,queued[2:0]};minimum<=65536;
                        end else begin store_point(21'hfffd);status<=8'h91;end
                    end else if(text_finished)begin
                        if(continuation!=0 && length<64)begin
                            store_point(21'hfffd);continuation<=0;status<=8'h91;
                        end else begin
                            glyph_index<=0;state<=length==0 ? PUBLISH : POINT_WAIT;
                        end
                    end
                    if(file_error)begin status<=file_code==8'h36 ? 8'h90 : file_code;has_text<=0;state<=PUBLISH;end
                end
                POINT_WAIT:state<=FONT_START;
                FONT_START:begin
                    job_kind<=2;job_offset<={6'd0,point_rdata,5'd0};job_length<=32;
                    job_start<=1;font_bytes<=0;state<=JOB_WAIT;
                end
                FONT_READ:begin
                    if(valid)begin
                        if(!font_bytes[0])high_byte<=data;
                        else begin
                            glyph_we<=1;glyph_addr<={glyph_index,font_bytes[4:1]};glyph_data<={high_byte,data};
                        end
                        font_bytes<=font_bytes+1'b1;
                    end
                    if(file_done)begin
                        if(font_bytes!=32)begin has_text<=0;status<=8'h93;state<=PUBLISH;end
                        else if({1'b0,glyph_index}+7'd1==length)begin has_text<=1;state<=PUBLISH;end
                        else begin glyph_index<=glyph_index+1'b1;state<=POINT_WAIT;end
                    end
                    if(file_error)begin has_text<=0;status<=file_code==8'h36 ? 8'h92 : file_code;state<=PUBLISH;end
                end
                PUBLISH:if(cache_ready)begin commit<=1;state<=FINISH;end
                FINISH:begin done<=1;state<=IDLE;end
                default:state<=IDLE;
            endcase
        end
    end
endmodule
