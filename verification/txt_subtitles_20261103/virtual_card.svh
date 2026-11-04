// Independent FAT32 superfloppy: 64 KiB clusters, deliberately fragmented font.
// No DUT state or memory is used to produce sectors or expected glyph bytes.
reg [7:0] boot_bytes[0:511],root_bytes[0:511],caption_bytes[0:511],image_bytes[0:511];
reg [7:0] wav_bytes[0:10239];
integer missing_text=0,missing_font=0,bad_link=0;
function [31:0] chain(input integer cluster_id);
 integer k;
 begin
  chain=32'h0fffffff;
  if(cluster_id==0)chain=32'h0ffffff8;
  else if(cluster_id>=10 && (cluster_id-10)%3==0)begin
   k=(cluster_id-10)/3;
   if(k<543)chain=cluster_id+3;
   if(bad_link && k==0)chain=32'h0fffffff;
  end
 end
endfunction
function [7:0] payload(input integer byte_offset);
 payload=(byte_offset*13)^(byte_offset>>8)^(byte_offset>>16)^8'h5a;
endfunction
function [7:0] card_byte(input integer lba,off);
 integer c,k,b,entry;reg [31:0]v;
 begin
  card_byte=0;
  if(lba==0)card_byte=boot_bytes[off];
  else if(lba>=32 && lba<1056)begin
   b=((lba-32)%512)*512+off;entry=b/4;v=chain(entry);card_byte=v>>((b%4)*8);
  end else if(lba>=1056)begin
   c=2+(lba-1056)/128;
   if(c==2 && (lba-1056)%128==0)begin
    card_byte=root_bytes[off];
    if(missing_text && off==0)card_byte='he5;
    if(missing_font && off==32)card_byte='he5;
   end else if(c==5)card_byte=caption_bytes[off];
   else if(c==6)card_byte=image_bytes[off];
   else if(c==7)card_byte=wav_bytes[((lba-1056)%128)*512+off];
   else if(c>=10 && (c-10)%3==0)begin
    k=(c-10)/3;b=k*65536+((lba-1056)%128)*512+off;
    card_byte=payload(b);
   end
  end
 end
endfunction
initial begin
 $readmemh("virtual_boot.hex",boot_bytes);$readmemh("virtual_root.hex",root_bytes);$readmemh("virtual_caption.hex",caption_bytes);$readmemh("virtual_image.hex",image_bytes);
 $readmemh("virtual_wav.hex",wav_bytes);
end
