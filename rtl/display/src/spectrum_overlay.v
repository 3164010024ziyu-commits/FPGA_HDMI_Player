// 288x116 translucent spectrum panel at (304,328), within 640x480.
// Snapshot/update at vertical blank only. No pixel/DE/coordinate latency.
module spectrum_overlay(
    input wire clk,rst_n,enable,frame_sync,de,
    input wire [9:0] x,y,
    input wire [23:0] rgb_in,
    input wire [111:0] levels,
    output reg [23:0] rgb_out
);
    reg frame_previous,visible;
    reg [6:0] height[0:15];
    integer i;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin frame_previous<=0;visible<=0;for(i=0;i<16;i=i+1)height[i]<=0;end
        else begin
            frame_previous<=frame_sync;
            if(frame_sync && !frame_previous)begin
                visible<=enable;
                for(i=0;i<16;i=i+1)begin
                    if(!enable)height[i]<=0;
                    else if(levels[7*i+:7]>=height[i])height[i]<=levels[7*i+:7];
                    else if(height[i]-levels[7*i+:7]>2)height[i]<=height[i]-2;
                    else height[i]<=levels[7*i+:7];
                end
            end
        end
    end
    function [34:0] glyph;
        input [7:0] ch;
        begin
            case(ch)
                "S":glyph=35'b01111_10000_10000_01110_00001_00001_11110;
                "P":glyph=35'b11110_10001_10001_11110_10000_10000_10000;
                "E":glyph=35'b11111_10000_10000_11110_10000_10000_11111;
                "C":glyph=35'b01111_10000_10000_10000_10000_10000_01111;
                "T":glyph=35'b11111_00100_00100_00100_00100_00100_00100;
                "R":glyph=35'b11110_10001_10001_11110_10100_10010_10001;
                "U":glyph=35'b10001_10001_10001_10001_10001_10001_01110;
                "M":glyph=35'b10001_11011_10101_10101_10001_10001_10001;
                "0":glyph=35'b01110_10001_10011_10101_11001_10001_01110;
                "1":glyph=35'b00100_01100_00100_00100_00100_00100_01110;
                "2":glyph=35'b01110_10001_00001_00010_00100_01000_11111;
                "4":glyph=35'b00010_00110_01010_10010_11111_00010_00010;
                "k":glyph=35'b10000_10000_10010_10100_11000_10100_10010;
                default:glyph=0;
            endcase
        end
    endfunction
    integer col,row,letter,glyph_x,bar,bar_y;
    reg [7:0] ch;
    reg [34:0] pixels;
    reg text_on;
    always @*begin
        rgb_out=rgb_in;col=0;row=0;letter=0;glyph_x=0;bar=0;bar_y=0;ch=0;pixels=0;text_on=0;
        if(visible && de && x>=304 && x<592 && y>=328 && y<444)begin
            rgb_out={1'b0,rgb_in[23:17],1'b0,rgb_in[15:9],1'b0,rgb_in[7:1]};
            if(x==304 || x==591 || y==328 || y==443)rgb_out=24'h526878;
            // Faint horizontal grid and frequency baseline.
            if(x>=320 && x<576 && (y==352 || y==376 || y==400 || y==424))rgb_out=24'h283b48;
            if(x>=320 && x<576 && y>=352 && y<424)begin
                bar=(x-320)>>4;bar_y=424-y;
                if(((x-320)&15)<11 && height[bar]!=0 && bar_y<=height[bar])begin
                    if(y<372)rgb_out=24'hff665c;
                    else if(y<396)rgb_out=24'hf3ce54;
                    else rgb_out=24'h38e6a0;
                end
            end
            if(y>=334 && y<341 && x>=316 && x<364)begin
                col=x-316;row=y-334;letter=col/6;glyph_x=col%6;
                case(letter)
                    0:ch="S";1:ch="P";2:ch="E";3:ch="C";
                    4:ch="T";5:ch="R";6:ch="U";7:ch="M";default:ch=0;
                endcase
            end else if(y>=432 && y<439)begin
                row=y-432;
                if(x>=316 && x<334)begin col=x-316;letter=col/6;glyph_x=col%6;ch=letter==0 ? "1" : "0";end
                else if(x>=412 && x<424)begin col=x-412;letter=col/6;glyph_x=col%6;ch=letter==0 ? "1" : "k";end
                else if(x>=506 && x<524)begin col=x-506;letter=col/6;glyph_x=col%6;ch=letter==0 ? "1" : letter==1 ? "0" : "k";end
                else if(x>=560 && x<578)begin col=x-560;letter=col/6;glyph_x=col%6;ch=letter==0 ? "2" : letter==1 ? "4" : "k";end
            end
            pixels=glyph(ch);
            if(ch!=0 && glyph_x<5)text_on=pixels[(6-row)*5+4-glyph_x];
            if(text_on)rgb_out=24'he5f0fa;
        end
    end
endmodule
