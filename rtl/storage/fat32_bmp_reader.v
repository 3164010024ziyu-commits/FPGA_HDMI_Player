// Read-only FAT32 root-directory BMP enumeration and fragmented file streaming.
// Generic sector port: req handshake, then exactly 512 bytes ending in sec_last.
module fat32_bmp_reader #(
    parameter MAX_FILE_BYTES=16777216, parameter MAX_DIR_CLUSTERS=1024
)(
    input wire clk, input wire rst_n,
    input wire start, input wire [15:0] file_index,
    output reg busy, output reg done, output reg error, output reg [7:0] error_code,
    output reg file_open, output reg [31:0] file_size,
    output reg [87:0] short_name,
    output wire [7:0] data, output wire valid, output wire last, input wire ready,
    output wire req_valid, input wire req_ready, output reg [31:0] req_lba,
    input wire [7:0] sec_data, input wire sec_valid, input wire sec_last,
    output wire sec_ready, input wire sec_error
);
    localparam IDLE=0, REQUEST=1, RECEIVE=2, BOOT=3, BPB=4, GEOMETRY=5,
        DIR_LOAD=6, DIR_SCAN=7, DIR_NEXT=8, FAT_LOAD=9, FAT_NEXT=10,
        FILE_LOAD=11, FILE_STREAM=12, FILE_NEXT=13, FAILED=14, GEO_CHECK=15,
        DIR_CAPTURE=16, FAT_CAPTURE=17;
    reg [4:0] state, return_state;
    reg [7:0] sector[0:511];
    // Keep small fixed metadata fields separately so the large sector array
    // has a single shared asynchronous read port and can infer logic RAM.
    reg [7:0] boot[0:63], mbr[0:63];
    reg [15:0] signature;
    reg [1:0] fat_capture_offset;
    reg [31:0] fat_value;
    // Snapshot one directory entry through one byte read port. Constant-offset
    // field decoding avoids replicating wide 512:1 muxes for every SFN byte.
    reg [7:0] dir_entry[0:31];
    reg [4:0] entry_offset;
    reg [8:0] rx_offset, out_offset, dir_offset;
    reg [31:0] partition_lba, partition_size, total_sectors;
    reg [31:0] fat_base, data_base, fat_sectors, cluster_count;
    reg [31:0] data_sectors;
    reg [31:0] cluster, chain_steps, bytes_left;
    reg [7:0] sectors_per_cluster, cluster_sector;
    reg [3:0] cluster_shift;
    reg [15:0] wanted, found;
    reg chain_is_file;
    reg [8:0] fat_byte;
    integer j;
    function [15:0] le16;
        input [8:0] a;
        begin le16={boot[a+9'd1],boot[a]}; end
    endfunction
    function [31:0] le32;
        input [8:0] a;
        begin le32={boot[a+9'd3],boot[a+9'd2],boot[a+9'd1],boot[a]}; end
    endfunction
    function [31:0] mbr32;
        input [5:0] a;
        begin mbr32={mbr[a+6'd3],mbr[a+6'd2],mbr[a+6'd1],mbr[a]}; end
    endfunction
    wire [31:0] bpb_total={boot[35],boot[34],boot[33],boot[32]};
    wire [31:0] bpb_fat={boot[39],boot[38],boot[37],boot[36]};
    wire [15:0] reserved_sectors={boot[15],boot[14]};
    wire [15:0] ext_flags={boot[41],boot[40]};
    // Only one or two FAT copies are accepted below. Use a shift/mux, not DSPs.
    wire [32:0] fat_span=(boot[16]==2) ? {bpb_fat,1'b0} : {1'b0,bpb_fat};
    wire [63:0] overhead={48'd0,reserved_sectors}+{31'd0,fat_span};
    wire [63:0] volume_end={32'd0,partition_lba}+{32'd0,bpb_total};
    wire [31:0] entry_cluster={dir_entry[21],dir_entry[20],dir_entry[27],dir_entry[26]};
    wire [31:0] entry_size={dir_entry[31],dir_entry[30],dir_entry[29],dir_entry[28]};
    wire bmp_entry=(dir_entry[8]==8'h42 || dir_entry[8]==8'h62) &&
                   (dir_entry[9]==8'h4d || dir_entry[9]==8'h6d) &&
                   (dir_entry[10]==8'h50 || dir_entry[10]==8'h70);
    wire [2:0] chosen_partition=
        (mbr[4]==8'h0b || mbr[4]==8'h0c) ? 3'd1 :
        (mbr[20]==8'h0b || mbr[20]==8'h0c) ? 3'd2 :
        (mbr[36]==8'h0b || mbr[36]==8'h0c) ? 3'd3 :
        (mbr[52]==8'h0b || mbr[52]==8'h0c) ? 3'd4 : 3'd0;
    wire [31:0] fat_link=fat_value & 32'h0fffffff;
    wire [8:0] sector_read_offset=(state==DIR_CAPTURE) ? dir_offset+{4'd0,entry_offset} :
                                 (state==FAT_CAPTURE) ? fat_byte+{7'd0,fat_capture_offset} : out_offset;
    wire [7:0] sector_byte=sector[sector_read_offset];
    wire [63:0] cluster_lba={32'd0,data_base}+
                             (({32'd0,cluster}-64'd2)<<cluster_shift)+cluster_sector;
    assign req_valid=(state==REQUEST);
    assign sec_ready=(state==RECEIVE);
    assign valid=(state==FILE_STREAM);
    assign data=sector_byte;
    assign last=valid && bytes_left==1;
    task read_sector;
        input [31:0] lba; input [4:0] destination;
        begin req_lba<=lba; return_state<=destination; state<=REQUEST; end
    endtask
    task fail;
        input [7:0] code;
        begin error<=1; error_code<=code; state<=FAILED; end
    endtask
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE; return_state<=0; busy<=0; done<=0; error<=0; error_code<=0;
            file_open<=0; file_size<=0; short_name<=0; req_lba<=0;
            rx_offset<=0; out_offset<=0; dir_offset<=0; entry_offset<=0; partition_lba<=0;
            partition_size<=0; total_sectors<=0; fat_base<=0; data_base<=0;
            fat_sectors<=0; cluster_count<=0; cluster<=0; data_sectors<=0;
            chain_steps<=0; bytes_left<=0; sectors_per_cluster<=0;
            cluster_sector<=0; cluster_shift<=0; wanted<=0; found<=0;
            chain_is_file<=0; fat_byte<=0;
            signature<=0; fat_capture_offset<=0; fat_value<=0;
        end else begin
            done<=0; file_open<=0;
            case(state)
                IDLE: if(start) begin
                    busy<=1; error<=0; error_code<=0; wanted<=file_index; found<=0;
                    partition_lba<=0; partition_size<=0;
                    read_sector(0,BOOT);
                end
                REQUEST: if(req_ready) begin rx_offset<=0; state<=RECEIVE; end
                RECEIVE: if(sec_error) fail(8'h30);
                    else if(sec_valid) begin
                        sector[rx_offset]<=sec_data;
                        if(return_state==BOOT || return_state==BPB) begin
                            if(rx_offset<64) boot[rx_offset[5:0]]<=sec_data;
                            if(rx_offset==510) signature[7:0]<=sec_data;
                            if(rx_offset==511) signature[15:8]<=sec_data;
                        end
                        if(return_state==BOOT && rx_offset>=446 && rx_offset<510)
                            mbr[rx_offset-446]<=sec_data;
                        if(sec_last!=(rx_offset==511)) fail(8'h31);
                        else if(rx_offset==511) state<=return_state;
                        else rx_offset<=rx_offset+1'b1;
                    end
                BOOT: if(signature!=16'haa55) fail(8'h32);
                    else if(le16(11)==512 && boot[13]!=0 && le16(17)==0 && le16(22)==0)
                        state<=BPB; // superfloppy
                    else begin
                        // First supported primary MBR partition; no GPT/extended partitions.
                        if(chosen_partition==0) fail(8'h33);
                        else begin
                            partition_lba<=mbr32((chosen_partition-1)*16+8);
                            partition_size<=mbr32((chosen_partition-1)*16+12);
                            if(mbr32((chosen_partition-1)*16+8)==0 ||
                               mbr32((chosen_partition-1)*16+12)==0 ||
                               ({32'd0,mbr32((chosen_partition-1)*16+8)}+
                                {32'd0,mbr32((chosen_partition-1)*16+12)})>64'h100000000)
                                fail(8'h33);
                            else read_sector(mbr32((chosen_partition-1)*16+8),BPB);
                        end
                    end
                BPB: if(signature!=16'haa55 || le16(11)!=512 || le16(17)!=0 ||
                       le16(19)!=0 || le16(22)!=0 || le16(42)!=0 ||
                       reserved_sectors==0 || bpb_fat==0 || boot[16]==0 || boot[16]>2 ||
                       boot[13]==0 || boot[13]>128 || ((boot[13] & (boot[13]-1'b1))!=0) ||
                       overhead>={32'd0,bpb_total} || volume_end>64'h100000000 ||
                       (partition_size!=0 && bpb_total>partition_size) ||
                       (ext_flags[7] && ext_flags[3:0]>=boot[16])) fail(8'h34);
                    else begin
                        sectors_per_cluster<=boot[13];
                        for(j=0;j<8;j=j+1) if(boot[13]==(1<<j)) cluster_shift<=j;
                        data_sectors<=bpb_total-overhead[31:0];
                        total_sectors<=bpb_total; fat_sectors<=bpb_fat;
                        fat_base<=partition_lba+reserved_sectors+
                                  ((ext_flags[7] && ext_flags[0]) ? bpb_fat : 0);
                        data_base<=partition_lba+overhead[31:0];
                        state<=GEOMETRY;
                    end
                GEOMETRY: begin
                    cluster_count<=data_sectors>>cluster_shift;
                    state<=GEO_CHECK;
                end
                GEO_CHECK: if(cluster_count<65525 || cluster_count>32'h0ffffff5 ||
                             ({32'd0,fat_sectors}<<7)<({32'd0,cluster_count}+64'd2) ||
                             (le32(44)&32'h0fffffff)<2 ||
                             (le32(44)&32'h0fffffff)>cluster_count+1) fail(8'h34);
                    else begin
                        cluster<=le32(44)&32'h0fffffff; cluster_sector<=0;
                        chain_steps<=0; state<=DIR_LOAD;
                    end
                DIR_LOAD: if(cluster_lba>={32'd0,partition_lba}+total_sectors) fail(8'h35);
                          else read_sector(cluster_lba[31:0],DIR_CAPTURE);
                DIR_CAPTURE: begin
                    dir_entry[entry_offset]<=sector_byte;
                    if(entry_offset==31) begin entry_offset<=0; state<=DIR_SCAN; end
                    else entry_offset<=entry_offset+1'b1;
                end
                DIR_SCAN: begin
                    if(dir_entry[0]==0) fail(8'h36); // no such BMP index
                    else if(dir_entry[0]!=8'he5 &&
                            (dir_entry[11]&8'h18)==0 &&
                            dir_entry[11]!=8'h0f && bmp_entry) begin
                        if(found==wanted) begin
                            if(entry_size<54 || entry_size>MAX_FILE_BYTES ||
                               entry_cluster<2 || entry_cluster>cluster_count+1) fail(8'h37);
                            else begin
                                for(j=0;j<11;j=j+1) short_name[87-j*8-:8]<=dir_entry[j];
                                file_size<=entry_size; bytes_left<=entry_size; file_open<=1;
                                cluster<=entry_cluster; cluster_sector<=0; chain_steps<=0;
                                state<=FILE_LOAD;
                            end
                        end else begin found<=found+1'b1; state<=DIR_NEXT; end
                    end else state<=DIR_NEXT;
                end
                DIR_NEXT: if(dir_offset!=480) begin dir_offset<=dir_offset+32; state<=DIR_CAPTURE; end
                    else begin
                        dir_offset<=0;
                        if(cluster_sector+1<sectors_per_cluster) begin
                            cluster_sector<=cluster_sector+1'b1; state<=DIR_LOAD;
                        end else begin chain_is_file<=0; state<=FAT_LOAD; end
                    end
                FAT_LOAD: if((cluster>>7)>=fat_sectors) fail(8'h35);
                    else begin
                        fat_byte<={cluster[6:0],2'b00};
                        fat_capture_offset<=0;
                        read_sector(fat_base+(cluster>>7),FAT_CAPTURE);
                    end
                FAT_CAPTURE: begin
                    fat_value<={sector_byte,fat_value[31:8]};
                    if(fat_capture_offset==3) state<=FAT_NEXT;
                    else fat_capture_offset<=fat_capture_offset+1'b1;
                end
                FAT_NEXT: begin
                    if(fat_link>=32'h0ffffff8) fail(chain_is_file ? 8'h38 : 8'h36);
                    else if(fat_link<2 || fat_link>cluster_count+1 ||
                            fat_link>=32'h0ffffff0 || fat_link==cluster) fail(8'h35);
                    else if(chain_steps>=cluster_count-1 ||
                            (!chain_is_file && chain_steps>=MAX_DIR_CLUSTERS-1)) fail(8'h39);
                    else begin
                        cluster<=fat_link; cluster_sector<=0; chain_steps<=chain_steps+1'b1;
                        state<=chain_is_file ? FILE_LOAD : DIR_LOAD;
                    end
                end
                FILE_LOAD: if(cluster_lba>={32'd0,partition_lba}+total_sectors) fail(8'h35);
                    else begin out_offset<=0; read_sector(cluster_lba[31:0],FILE_STREAM); end
                FILE_STREAM: if(ready) begin
                    bytes_left<=bytes_left-1'b1;
                    if(bytes_left==1) begin done<=1; busy<=0; state<=IDLE; end
                    else if(out_offset==511) state<=FILE_NEXT;
                    else out_offset<=out_offset+1'b1;
                end
                FILE_NEXT: if(cluster_sector+1<sectors_per_cluster) begin
                    cluster_sector<=cluster_sector+1'b1; state<=FILE_LOAD;
                end else begin chain_is_file<=1; state<=FAT_LOAD; end
                FAILED: begin busy<=0; state<=IDLE; end
                default: begin end
            endcase
            // Directory offsets are reset before every newly loaded directory sector.
            if(state==DIR_LOAD) dir_offset<=0;
        end
    end
endmodule
