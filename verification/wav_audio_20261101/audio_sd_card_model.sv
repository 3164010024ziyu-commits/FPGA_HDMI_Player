`timescale 1ns/1ps
// Behavioral SPI card, independent of the RTL byte engine. No vendor IP.
module audio_sd_card_model(
    input wire rst_n, input wire cs_n, input wire sck, input wire mosi,
    output reg miso=1,
    input wire high_capacity, input wire corrupt_crc, input wire suppress_token,
    input wire bad_token, input wire bad_cmd8, input wire suppress_response,
    output integer reads, output integer commands
);
    reg [7:0] card[0:13311];
    reg [7:0] queue[0:2047],cmd[0:5];
    integer head=0,tail=0,bit_count=0,cmd_count=0,acmd_count=0;
    reg [7:0] rx=0,tx=8'hff,received;
    reg idle=1,app=0;
    reg [31:0] arg,lba;
    reg [15:0] crc;
    integer index;
    function integer slot(input integer address);
        case(address)
            0:slot=0;
            2048:slot=1;
            2080:slot=2;
            2680:slot=3;
            3280:slot=4;
            3283:slot=5;
            3284:slot=6;
            3287:slot=7;
            3288:slot=8;
            3289:slot=9;
            3291:slot=10;
            3293:slot=11;
            3295:slot=12;
            3297:slot=13;
            3299:slot=14;
            3301:slot=15;
            3303:slot=16;
            3305:slot=17;
            3307:slot=18;
            3309:slot=19;
            3311:slot=20;
            3313:slot=21;
            3315:slot=22;
            3317:slot=23;
            3319:slot=24;
            3321:slot=25;
            default:slot=-1;
        endcase
    endfunction
    function [7:0] read_byte(input integer address,offset);
        integer s;
        begin
            s=slot(address);
            read_byte=(s<0) ? (address^offset) : card[s*512+offset];
        end
    endfunction
    function [15:0] update_crc(input [15:0] old,input [7:0] value);
        reg [15:0] c;
        begin
            c=old ^ {value,8'd0};
            for(integer n=0;n<8;n=n+1) c=c[15] ? (c<<1)^16'h1021 : c<<1;
            update_crc=c;
        end
    endfunction
    function [7:0] command_crc(input [39:0] value);
        reg [7:0] c;
        begin
            c=0;
            for(integer n=39;n>=0;n=n-1) begin
                c=c<<1;
                if(value[n]^c[7]) c=c^8'h09;
            end
            command_crc={c[6:0],1'b1};
        end
    endfunction
    task push(input [7:0] value);
        begin queue[tail%2048]=value; tail=tail+1; end
    endtask
    task execute;
        begin
            commands=commands+1;
            arg={cmd[1],cmd[2],cmd[3],cmd[4]};
            if(cmd[5]!==command_crc({cmd[0],cmd[1],cmd[2],cmd[3],cmd[4]}))
                $fatal(1,"SD command CRC7 cmd=%h crc=%h",cmd[0],cmd[5]);
            if(!suppress_response) case(cmd[0]&8'h3f)
                0: begin idle=1; acmd_count=0; push(1); end
                8: begin
                    push(1); push(0); push(0); push(1); push(bad_cmd8 ? 8'hab : 8'haa);
                end
                55: begin app=1; push(idle ? 1 : 0); end
                41: begin
                    if(!app || arg!=32'h40000000) $fatal(1,"ACMD41 sequence/argument");
                    app=0;
                    if(acmd_count<2) begin push(1); acmd_count=acmd_count+1; end
                    else begin idle=0; push(0); end
                end
                58: begin
                    push(idle ? 1 : 0); push(high_capacity ? 8'hc0 : 8'h80);
                    push(8'hff); push(8'h80); push(0);
                end
                16: begin if(arg!=512) $fatal(1,"CMD16 length"); push(0); end
                17: begin
                    if(idle) $fatal(1,"read before init");
                    if(!high_capacity && arg[8:0]!=0) $fatal(1,"SDSC unaligned address");
                    lba=high_capacity ? arg : arg>>9; reads=reads+1;
                    push(0); push(8'hff); push(8'hff);
                    if(!suppress_token) begin
                        push(bad_token ? 8'h01 : 8'hfe); crc=0;
                        for(integer n=0;n<512;n=n+1) begin
                            push(read_byte(lba,n)); crc=update_crc(crc,read_byte(lba,n));
                        end
                        push(crc[15:8]); push(crc[7:0] ^ (corrupt_crc ? 8'h01 : 8'h00));
                    end
                end
                default: $fatal(1,"unsupported SD command %h",cmd[0]);
            endcase
        end
    endtask
    initial begin
        $readmemh("tb/storage/vectors/card.hex",card); reads=0; commands=0;
    end
    always @(negedge rst_n) begin idle=1; app=0; acmd_count=0; reads=0; commands=0; end
    always @(posedge cs_n or negedge rst_n) begin
        head=0; tail=0; bit_count=0; cmd_count=0; rx=0; tx=8'hff; miso=1;
    end
    always @(posedge sck) if(!cs_n && rst_n) begin
        rx={rx[6:0],mosi};
        if(bit_count==7) begin
            received=rx; bit_count=0;
            if(cmd_count==0) begin
                if(received[7:6]==2'b01) begin cmd[0]=received; cmd_count=1; end
            end else begin
                cmd[cmd_count]=received;
                if(cmd_count==5) begin execute(); cmd_count=0; end
                else cmd_count=cmd_count+1;
            end
        end else bit_count=bit_count+1;
    end
    always @(negedge sck) if(!cs_n && rst_n) begin
        if(bit_count==0) begin
            if(head<tail) begin tx=queue[head%2048]; head=head+1; end
            else tx=8'hff;
            miso=tx[7];
        end else miso=tx[7-bit_count];
    end
endmodule
