// Read-only SD v2 SPI host: CMD0/8/55/41/58/[16], CMD17, CRC7/CRC16.
// Supports SDHC/SDXC block addressing and SD v2 SDSC byte addressing.
// A sector is published only after its CRC16 passes. No writes are implemented.
module sd_spi_reader #(
    parameter CLK_HZ=50000000,
    parameter INIT_HALF_PERIOD=(CLK_HZ+799999)/800000,
    parameter READ_HALF_PERIOD=(CLK_HZ+49999999)/50000000,
    parameter POWERUP_CYCLES=CLK_HZ/1000,
    parameter INIT_RETRIES=5000, parameter TOKEN_TIMEOUT_BYTES=400000
)(
    input wire clk, input wire rst_n,
    output reg sd_cs_n, output wire sd_sck, output wire sd_mosi,
    input wire sd_miso,
    output reg initialized, output reg high_capacity,
    input wire req_valid, output wire req_ready, input wire [31:0] req_lba,
    output wire [7:0] data, output wire valid, input wire ready,
    output wire last, output reg done,
    output reg error, output reg [7:0] error_code
);
    localparam POWER=0, CLOCKS=1, CLOCK_NEXT=2, INIT_CMD=3,
        INIT_RESULT=4, EXT=5, EXT_NEXT=6, EXT_CHECK=7, IDLE=8,
        READ_RESULT=9, TOKEN=10, TOKEN_CHECK=11, PAYLOAD=12,
        PAYLOAD_NEXT=13, CRC_HI=14, CRC_HI_NEXT=15, CRC_LO=16,
        CRC_CHECK=17, RELEASE=18, DRAIN=19, FATAL=20,
        CMD_GAP=21, CMD_SEND=22, CMD_NEXT=23, RESP=24,
        RESP_CHECK=25, WAIT_BYTE=26;
    reg [5:0] state, byte_return, command_return, release_return;
    reg [3:0] init_step;
    reg [31:0] timer, attempts;
    reg [3:0] clock_count;
    reg [47:0] packet;
    reg [2:0] command_index, ext_index;
    reg [7:0] response;
    reg [31:0] ext_response;
    reg [9:0] offset;
    reg [8:0] out_offset;
    reg [15:0] crc16;
    reg [7:0] crc_hi;
    reg [7:0] sector [0:511];
    reg byte_start;
    reg [7:0] byte_tx;
    wire [7:0] byte_rx;
    wire byte_busy, byte_done;
    wire [15:0] half_period=initialized ? READ_HALF_PERIOD : INIT_HALF_PERIOD;
    spi_byte_master spi(.clk(clk),.rst_n(rst_n),.start(byte_start),
        .tx_data(byte_tx),.half_period(half_period),.miso(sd_miso),
        .sck(sd_sck),.mosi(sd_mosi),.busy(byte_busy),.done(byte_done),.rx_data(byte_rx));
    assign req_ready=initialized && state==IDLE;
    assign valid=(state==DRAIN);
    assign data=sector[out_offset];
    assign last=valid && out_offset==511;
    function [6:0] crc7;
        input [39:0] bits;
        reg [6:0] c; integer i;
        begin
            c=0;
            for (i=39;i>=0;i=i-1)
                if (bits[i]^c[6]) c={c[5:0],1'b0}^7'h09;
                else c={c[5:0],1'b0};
            crc7=c;
        end
    endfunction
    function [15:0] crc16_byte;
        input [15:0] old_crc; input [7:0] b;
        reg [15:0] c; integer i;
        begin
            c=old_crc;
            for(i=7;i>=0;i=i-1)
                if(c[15]^b[i]) c={c[14:0],1'b0}^16'h1021;
                else c={c[14:0],1'b0};
            crc16_byte=c;
        end
    endfunction
    task transfer;
        input [7:0] tx; input [5:0] next_state;
        begin byte_tx<=tx; byte_start<=1; byte_return<=next_state; state<=WAIT_BYTE; end
    endtask
    task command;
        input [5:0] cmd; input [31:0] arg; input [5:0] next_state;
        reg [39:0] body;
        begin
            body={2'b01,cmd,arg}; packet<={body,crc7(body),1'b1};
            command_index<=0; command_return<=next_state;
            timer<=0; sd_cs_n<=0; state<=CMD_GAP;
        end
    endtask
    task fail;
        input [7:0] code;
        begin
            error<=1; error_code<=code; sd_cs_n<=1;
            release_return<=initialized ? IDLE : FATAL; state<=RELEASE;
        end
    endtask
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            sd_cs_n<=1; initialized<=0; high_capacity<=0;
            state<=POWER; timer<=0; attempts<=0; init_step<=0;
            byte_start<=0; byte_tx<=8'hff; byte_return<=0;
            command_return<=0; release_return<=0; packet<=0;
            command_index<=0; ext_index<=0; response<=0; ext_response<=0;
            clock_count<=0; offset<=0; out_offset<=0; crc16<=0; crc_hi<=0;
            done<=0; error<=0; error_code<=0;
        end else begin
            byte_start<=0; done<=0; error<=0;
            case(state)
                POWER: if(timer>=POWERUP_CYCLES-1) begin timer<=0; state<=CLOCKS; end
                       else timer<=timer+1'b1;
                CLOCKS: transfer(8'hff,CLOCK_NEXT);
                CLOCK_NEXT: if(clock_count==9) state<=INIT_CMD;
                            else begin clock_count<=clock_count+1'b1; state<=CLOCKS; end
                INIT_CMD: case(init_step)
                    0: command(0,0,INIT_RESULT);
                    1: command(8,32'h1aa,INIT_RESULT);
                    2: command(55,0,INIT_RESULT);
                    3: command(41,32'h40000000,INIT_RESULT);
                    4: command(58,0,INIT_RESULT);
                    5: command(16,512,INIT_RESULT);
                    default: fail(8'h01);
                endcase
                INIT_RESULT: case(init_step)
                    0: if(response==1) begin init_step<=1; state<=INIT_CMD; end
                       else fail(8'h01);
                    1: if(response==1) begin ext_index<=0; ext_response<=0; state<=EXT; end
                       else fail(8'h02); // legacy SD v1/MMC deliberately unsupported
                    2: if(response==1 || response==0) begin init_step<=3; state<=INIT_CMD; end
                       else fail(8'h03);
                    3: if(response==0) begin init_step<=4; state<=INIT_CMD; end
                       else if(response==1 && attempts<INIT_RETRIES-1) begin
                           attempts<=attempts+1'b1; init_step<=2; state<=INIT_CMD;
                       end else fail(8'h03);
                    4: if(response==0) begin ext_index<=0; ext_response<=0; state<=EXT; end
                       else fail(8'h04);
                    5: if(response==0) begin
                           initialized<=1; sd_cs_n<=1; release_return<=IDLE; state<=RELEASE;
                       end else fail(8'h05);
                endcase
                EXT: transfer(8'hff,EXT_NEXT);
                EXT_NEXT: begin
                    ext_response<={ext_response[23:0],byte_rx};
                    if(ext_index==3) state<=EXT_CHECK;
                    else begin ext_index<=ext_index+1'b1; state<=EXT; end
                end
                EXT_CHECK: if(init_step==1) begin
                    if(ext_response==32'h1aa) begin init_step<=2; state<=INIT_CMD; end
                    else fail(8'h02);
                end else if(!ext_response[31] || (ext_response & 32'h00ff8000)==0) fail(8'h04);
                else begin
                    high_capacity<=ext_response[30];
                    if(ext_response[30]) begin
                        initialized<=1; sd_cs_n<=1; release_return<=IDLE; state<=RELEASE;
                    end else begin init_step<=5; state<=INIT_CMD; end
                end
                IDLE: if(req_valid) begin
                    error_code<=0;
                    if(!high_capacity && req_lba>32'h007fffff) fail(8'h0a);
                    else command(17,high_capacity ? req_lba : req_lba<<9,READ_RESULT);
                end
                READ_RESULT: if(response!=0) fail(8'h06);
                             else begin timer<=0; state<=TOKEN; end
                TOKEN: transfer(8'hff,TOKEN_CHECK);
                TOKEN_CHECK: if(byte_rx==8'hfe) begin offset<=0; crc16<=0; state<=PAYLOAD; end
                    else if(byte_rx!=8'hff) fail(8'h07);
                    else if(timer>=TOKEN_TIMEOUT_BYTES-1) fail(8'h08);
                    else begin timer<=timer+1'b1; state<=TOKEN; end
                PAYLOAD: transfer(8'hff,PAYLOAD_NEXT);
                PAYLOAD_NEXT: begin
                    sector[offset[8:0]]<=byte_rx; crc16<=crc16_byte(crc16,byte_rx);
                    if(offset==511) state<=CRC_HI;
                    else begin offset<=offset+1'b1; state<=PAYLOAD; end
                end
                CRC_HI: transfer(8'hff,CRC_HI_NEXT);
                CRC_HI_NEXT: begin crc_hi<=byte_rx; state<=CRC_LO; end
                CRC_LO: transfer(8'hff,CRC_CHECK);
                CRC_CHECK: if({crc_hi,byte_rx}!=crc16) fail(8'h09);
                    else begin
                        sd_cs_n<=1; out_offset<=0; release_return<=DRAIN; state<=RELEASE;
                    end
                RELEASE: transfer(8'hff,release_return);
                DRAIN: if(ready) begin
                    if(out_offset==511) begin done<=1; state<=IDLE; end
                    else out_offset<=out_offset+1'b1;
                end
                CMD_GAP: transfer(8'hff,CMD_SEND);
                CMD_SEND: transfer(packet[47:40],CMD_NEXT);
                CMD_NEXT: begin
                    packet<={packet[39:0],8'hff};
                    if(command_index==5) state<=RESP;
                    else begin command_index<=command_index+1'b1; state<=CMD_SEND; end
                end
                RESP: transfer(8'hff,RESP_CHECK);
                RESP_CHECK: if(!byte_rx[7]) begin response<=byte_rx; state<=command_return; end
                    else if(timer==15) fail(8'h0b);
                    else begin timer<=timer+1'b1; state<=RESP; end
                WAIT_BYTE: if(byte_done) state<=byte_return;
                default: begin end
            endcase
        end
    end
endmodule
