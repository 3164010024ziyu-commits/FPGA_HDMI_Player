reg [7:0] boot_bytes[0:511],root_bytes[0:511],wav0[0:2047],wav1[0:2047],wav2[0:2047];
reg [7:0] bmp0[0:511],bmp1[0:511],bmp2[0:511];
reg [7:0] caption[0:511];
function [7:0] card_byte(input integer lba,off);
 integer c,b,entry;reg [31:0]link;
 begin
  card_byte=0;
  if(lba==0)card_byte=boot_bytes[off];
  else if(lba>=32 && lba<1056)begin
   b=((lba-32)%512)*512+off;entry=b/4;link=32'h0fffffff;
   if(entry>=20 && entry<563)link=entry+1;
   card_byte=link>>((b%4)*8);
  end else if(lba>=1056)begin
   c=2+(lba-1056)/128;b=((lba-1056)%128)*512+off;
   if(c==2 && b<512)card_byte=root_bytes[off];
   else if(c==6 && b<512)card_byte=bmp0[off];
   else if(c==10 && b<512)card_byte=bmp1[off];
   else if(c==11 && b<512)card_byte=bmp2[off];
   else if(c==12 && b<512)card_byte=caption[off];
   else if(c==7 && b<2048)card_byte=wav0[b];
   else if(c==8 && b<2048)card_byte=wav1[b];
   else if(c==9 && b<2048)card_byte=wav2[b];
   else if(c>=20 && c<=563)begin
    b=(c-20)*65536+b;card_byte=(b*13)^(b>>8)^(b>>16)^8'h5a;
   end
  end
 end
endfunction
initial begin
 $readmemh("boot.hex",boot_bytes);$readmemh("root.hex",root_bytes);
 $readmemh("wav0.hex",wav0);$readmemh("wav1.hex",wav1);$readmemh("wav2.hex",wav2);
 $readmemh("bmp0.hex",bmp0);$readmemh("bmp1.hex",bmp1);$readmemh("bmp2.hex",bmp2);
 $readmemh("caption.hex",caption);
end
