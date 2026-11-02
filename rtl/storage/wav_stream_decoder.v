// RIFF/WAVE PCM: 48 kHz, signed 16-bit, stereo. Unknown chunks and their odd
// padding are skipped. File/chunk bounds are checked before exposing PCM.
module wav_stream_decoder (
    input wire clk,rst_n,start,input wire [31:0] file_size,
    input wire [7:0] data,input wire valid,last,output wire ready,
    output reg [31:0] sample,output reg sample_valid,input wire sample_ready,
    output reg format_valid,done,error,output reg [7:0] error_code
);
    localparam IDLE=0,RIFF=1,CHUNK=2,FMT=3,SKIP=4,PCM=5,DRAIN=6,FAILED=7;
    reg [2:0] state;
    reg [4:0] index;
    reg [31:0] offset,size_latched,riff_size,riff_end,chunk_id,chunk_size,remaining;
    reg [7:0] fmt[0:15];
    reg fmt_seen,end_seen;
    reg [1:0] pcm_byte;
    reg [23:0] pcm_low;
    wire [31:0] size_now={data,chunk_size[23:0]};
    wire [32:0] end_now={1'b0,offset}+33'd1+{1'b0,size_now}+size_now[0];
    wire transfer=valid && ready;
    assign ready=state!=IDLE && state!=FAILED && !sample_valid && !(state==DRAIN && end_seen);
    task fail;
        input [7:0] code;
        begin error<=1;error_code<=code;state<=FAILED;sample_valid<=0;end
    endtask
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;index<=0;offset<=0;size_latched<=0;riff_size<=0;riff_end<=0;
            chunk_id<=0;chunk_size<=0;remaining<=0;fmt_seen<=0;end_seen<=0;
            pcm_byte<=0;pcm_low<=0;sample<=0;sample_valid<=0;format_valid<=0;done<=0;error<=0;error_code<=0;
        end else begin
            done<=0;format_valid<=0;
            if(sample_valid && sample_ready)sample_valid<=0;
            if(start)begin
                state<=RIFF;index<=0;offset<=0;size_latched<=file_size;
                riff_size<=0;chunk_id<=0;chunk_size<=0;fmt_seen<=0;end_seen<=0;
                pcm_byte<=0;sample_valid<=0;error<=0;error_code<=0;
            end else if(state==DRAIN && end_seen && !sample_valid)begin state<=IDLE;done<=1;end
            else if(transfer)begin
                offset<=offset+1'b1;
                if(last)end_seen<=1;
                case(state)
                    RIFF:begin
                        index<=index+1'b1;
                        case(index)
                            0:if(data!="R")fail(8'h80);
                            1:if(data!="I")fail(8'h80);
                            2,3:if(data!="F")fail(8'h80);
                            4:riff_size[7:0]<=data;
                            5:riff_size[15:8]<=data;
                            6:riff_size[23:16]<=data;
                            7:riff_size[31:24]<=data;
                            8:if(data!="W")fail(8'h80);
                            9:if(data!="A")fail(8'h80);
                            10:if(data!="V")fail(8'h80);
                            11:begin
                                if(data!="E" || riff_size<4 || {1'b0,riff_size}+33'd8>{1'b0,size_latched})fail(8'h80);
                                else begin riff_end<=riff_size+8;index<=0;state<=CHUNK;end
                            end
                        endcase
                    end
                    CHUNK:begin
                        if(index<4)chunk_id<={chunk_id[23:0],data};
                        else case(index)
                            4:chunk_size[7:0]<=data;
                            5:chunk_size[15:8]<=data;
                            6:chunk_size[23:16]<=data;
                        endcase
                        index<=index+1'b1;
                        if(index==7)begin
                            index<=0;remaining<=size_now+size_now[0];
                            if(end_now>{1'b0,riff_end} || end_now>{1'b0,size_latched})fail(8'h82);
                            else if(chunk_id==32'h666d7420)begin
                                if(fmt_seen || size_now<16)fail(8'h81);
                                else state<=FMT;
                            end else if(chunk_id==32'h64617461)begin
                                if(!fmt_seen || size_now==0 || size_now[1:0]!=0)fail(8'h82);
                                else begin state<=PCM;pcm_byte<=0;remaining<=size_now;format_valid<=1;end
                            end else state<=size_now==0 ? CHUNK : SKIP;
                        end
                    end
                    FMT:begin
                        fmt[index]<=data;index<=index+1'b1;remaining<=remaining-1'b1;
                        if(index==15)begin
                            if({fmt[1],fmt[0]}!=1 || {fmt[3],fmt[2]}!=2 ||
                               {fmt[7],fmt[6],fmt[5],fmt[4]}!=48000 ||
                               {fmt[11],fmt[10],fmt[9],fmt[8]}!=192000 ||
                               {fmt[13],fmt[12]}!=4 || {data,fmt[14]}!=16)fail(8'h81);
                            else begin fmt_seen<=1;index<=0;state<=remaining==1 ? CHUNK : SKIP;end
                        end
                    end
                    SKIP:begin
                        remaining<=remaining-1'b1;
                        if(remaining==1)begin state<=CHUNK;index<=0;end
                    end
                    PCM:begin
                        remaining<=remaining-1'b1;pcm_byte<=pcm_byte+1'b1;
                        case(pcm_byte)
                            0:pcm_low[7:0]<=data;
                            1:pcm_low[15:8]<=data;
                            2:pcm_low[23:16]<=data;
                            3:begin sample<={pcm_low[15:0],data,pcm_low[23:16]};sample_valid<=1;end
                        endcase
                        if(remaining==1)state<=DRAIN;
                    end
                    DRAIN:begin end
                    default:begin end
                endcase
                // last must match the actual directory file size. It is legal
                // at the final data byte or while draining post-data metadata.
                if(last!=(offset==size_latched-1))fail(8'h82);
                else if(last && state!=DRAIN && !(state==PCM && remaining==1))fail(8'h82);
            end
        end
    end
endmodule
