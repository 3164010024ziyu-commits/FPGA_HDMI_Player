reg [7:0] boot_bytes[0:511],root_bytes[0:511],image_bytes[0:511];
integer broken_image=0;
function[7:0] card_byte(input integer lba,off);
 integer c,b,cp;begin
 card_byte=0;
 if(lba==0)card_byte=boot_bytes[off];
 else if(lba>=1056)begin
 c=2+(lba-1056)/128;
 if(c==2)card_byte=root_bytes[off];
 else if(c==3)card_byte=off==0 ? "Z":0;
 else if(c==4)card_byte=off==0 ? "A":0;
 else if(c==5)card_byte=off==0 ? "B":0;
 else if(c>=6 && c<=8)begin card_byte=image_bytes[off];if(broken_image && c==6 && off==0)card_byte=0;end
 else if(c==10)begin b=((lba-1056)%128)*512+off;card_byte=(b*13)^(b>>8)^8'h5a;end
 end
 end
endfunction
initial begin $readmemh("boot.hex",boot_bytes);$readmemh("root.hex",root_bytes);$readmemh("image.hex",image_bytes);end
