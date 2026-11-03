// Read-only FAT32 root-directory BMP enumeration and fragmented file streaming.
// Generic sector port: req handshake, then exactly 512 bytes ending in sec_last.
module fat32_bmp_reader #(
    parameter MAX_FILE_BYTES=16777216, parameter MAX_DIR_CLUSTERS=1024,
    parameter FILE_EXTENSION=24'h424d50, parameter MIN_FILE_BYTES=54,
    parameter ENABLE_AUX=0,parameter ENABLE_NAME_MATCH=0
)(
    input wire clk, input wire rst_n,
    input wire start, input wire [15:0] file_index,
    input wire select_last, output reg [15:0] opened_index,
    output reg busy, output reg done, output reg error, output reg [7:0] error_code,
    output reg file_open, output reg [31:0] file_size,
    output reg [87:0] short_name,
    output wire [7:0] data, output wire valid, output wire last, input wire ready,
    output wire req_valid, input wire req_ready, output reg [31:0] req_lba,
    input wire [7:0] sec_data, input wire sec_valid, input wire sec_last,
    output wire sec_ready, input wire sec_error,
    // Optional jobs share the image reader: 0=normal BMP, 1=CAPTION.TXT,
    // 2=FONT16.BIN byte range. Disabled instances retain the original behavior.
    input wire [1:0] aux_kind,
    input wire [31:0] aux_offset,
    input wire [15:0] aux_length,input wire [63:0] match_name
);
    localparam IDLE=0, REQUEST=1, RECEIVE=2, BOOT=3, BPB=4, GEOMETRY=5,
        DIR_LOAD=6, DIR_SCAN=7, DIR_NEXT=8, FAT_LOAD=9, FAT_NEXT=10,
        FILE_LOAD=11, FILE_STREAM=12, FILE_NEXT=13, FAILED=14, GEO_CHECK=15,
        DIR_CAPTURE=16, FAT_CAPTURE=17, MBR=18, CACHE_PRIME=19, SEEK_FILE=20,
        BPB_PREP=21;
    reg [4:0] state, return_state;
    reg [7:0] sector[0:511];
    // Keep fixed metadata fields separate. Only the sector payload uses the
    // synchronous block-RAM port; its first byte is primed before consumption.
    reg [7:0] boot[0:63];
    // Select the first FAT32 primary partition while receiving LBA0. Only its
    // LBA and size are retained; no dynamic 64-byte partition-table mux.
    reg mbr_found,take_partition;
    reg [31:0] mbr_base,mbr_size;
    reg [15:0] signature;
    reg [1:0] fat_capture_offset;
    reg [31:0] fat_value;
    // Snapshot one directory entry through one byte read port. Constant-offset
    // field decoding avoids replicating wide 512:1 muxes for every SFN byte.
    reg [7:0] dir_entry[0:31];
    reg [4:0] entry_offset;
    reg [8:0] rx_offset, out_offset, dir_offset;
    wire [5:0] mbr_offset=rx_offset-9'd446;
    reg [31:0] partition_lba, partition_size, total_sectors;
    reg [31:0] fat_base, data_base, fat_sectors, cluster_count;
    reg [31:0] data_sectors;
    reg [31:0] cluster, chain_steps, bytes_left;
    reg [7:0] sectors_per_cluster, cluster_sector;
    reg [3:0] cluster_shift;
    reg [15:0] wanted;
    reg [16:0] found;
    reg last_mode, last_found;
    reg [31:0] last_cluster,last_size;
    reg [87:0] last_name;
    reg [15:0] last_number;
    wire [87:0] entry_name={dir_entry[0],dir_entry[1],dir_entry[2],dir_entry[3],dir_entry[4],dir_entry[5],dir_entry[6],dir_entry[7],dir_entry[8],dir_entry[9],dir_entry[10]};
    reg chain_is_file;
    reg [1:0] job_kind;
    reg [31:0] job_offset,seek_left;
    reg [15:0] job_length;
    reg seeking,first_payload,font_cached,sector_cached;
    reg [31:0] font_cluster,font_size,cached_lba;
    wire aux_job=ENABLE_AUX!=0 && job_kind!=0;
    wire [16:0] cluster_bytes={1'b0,sectors_per_cluster,9'b0};
    reg probe_lba0; // A candidate volume at sector zero may fall back to its MBR.
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
    wire [31:0] bpb_total={boot[35],boot[34],boot[33],boot[32]};
    wire [31:0] bpb_fat={boot[39],boot[38],boot[37],boot[36]};
    wire [15:0] reserved_sectors={boot[15],boot[14]};
    wire [15:0] ext_flags={boot[41],boot[40]};
    // Only one or two FAT copies are accepted below. Use a shift/mux, not DSPs.
    wire [32:0] fat_span=(boot[16]==2) ? {bpb_fat,1'b0} : {1'b0,bpb_fat};
    // Geometry is stable after a complete boot sector. Separate its wide sums
    // from BPB validation so neither image nor WAV inherits a long carry chain.
    reg [63:0] overhead,volume_end;
    wire [31:0] entry_cluster={dir_entry[21],dir_entry[20],dir_entry[27],dir_entry[26]};
    wire [31:0] entry_size={dir_entry[31],dir_entry[30],dir_entry[29],dir_entry[28]};
    wire bmp_entry=({dir_entry[8]&8'hdf,dir_entry[9]&8'hdf,dir_entry[10]&8'hdf}==FILE_EXTENSION);
    wire requested_entry=aux_job ?
        (job_kind==1 ? entry_name=="CAPTION TXT" : entry_name=="FONT16  BIN") :
        (bmp_entry && (ENABLE_NAME_MATCH==0 || entry_name[87:24]==match_name));
    wire [31:0] fat_link=fat_value & 32'h0fffffff;
    reg [7:0] sector_byte;
    reg [8:0] sector_read_offset;
    wire sector_read_enable=state==CACHE_PRIME || state==DIR_CAPTURE ||
                            state==FAT_CAPTURE || state==FILE_STREAM;
    always @* begin
        sector_read_offset=out_offset;
        if(state==CACHE_PRIME) begin
            if(return_state==DIR_CAPTURE)
                sector_read_offset=dir_offset+{4'd0,entry_offset};
            else if(return_state==FAT_CAPTURE)
                sector_read_offset=fat_byte+{7'd0,fat_capture_offset};
        end else if(state==DIR_CAPTURE)
            sector_read_offset=dir_offset+{4'd0,entry_offset}+9'd1;
        else if(state==FAT_CAPTURE)
            sector_read_offset=fat_byte+{7'd0,fat_capture_offset}+9'd1;
        else if(state==FILE_STREAM && ready && bytes_left!=1 && out_offset!=511)
            sector_read_offset=out_offset+9'd1;
    end
    // No reset on the payload RAM/read register. A complete sector is received
    // before CACHE_PRIME, and valid stays low until the registered read is ready.
    // Look ahead only on a transfer, keeping data stable under backpressure and
    // preserving one byte per clock while the downstream consumer is ready.
    always @(posedge clk) begin
        if(rst_n && state==RECEIVE && sec_valid && !sec_error)
            sector[rx_offset]<=sec_data;
        if(sector_read_enable) sector_byte<=sector[sector_read_offset];
    end
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
    task open_image;
        input [31:0] first_cluster,size;
        input [87:0] name;
        input [15:0] number;
        begin
            if(size<(aux_job ? 1 : MIN_FILE_BYTES) ||
               size>(aux_job && job_kind==2 ? 32'h02200000 : MAX_FILE_BYTES) ||
               first_cluster<2 || first_cluster>cluster_count+1 ||
               (aux_job && (job_offset>=size || job_length==0)))
                fail(8'h37);
            else begin
                short_name<=name;file_size<=size;
                bytes_left<=aux_job ? ((size-job_offset)<job_length ? size-job_offset : {16'd0,job_length}) : size;
                file_open<=1;opened_index<=number;cluster<=first_cluster;
                cluster_sector<=0;chain_steps<=0;first_payload<=1;
                if(aux_job && job_kind==2)begin
                    font_cached<=1;font_cluster<=first_cluster;font_size<=size;
                end
                seeking<=aux_job && job_offset!=0;seek_left<=job_offset;
                state<=aux_job && job_offset!=0 ? SEEK_FILE : FILE_LOAD;
            end
        end
    endtask
    task finish_last;
        begin
            if(last_found)open_image(last_cluster,last_size,last_name,last_number);
            else fail(8'h36);
        end
    endtask
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE; return_state<=0; busy<=0; done<=0; error<=0; error_code<=0;
            last_mode<=0;last_found<=0;last_cluster<=0;last_size<=0;last_name<=0;last_number<=0;opened_index<=0;
            file_open<=0; file_size<=0; short_name<=0; req_lba<=0;
            rx_offset<=0; out_offset<=0; dir_offset<=0; entry_offset<=0; partition_lba<=0;
            partition_size<=0; total_sectors<=0; fat_base<=0; data_base<=0;
            fat_sectors<=0; cluster_count<=0; cluster<=0; data_sectors<=0;
            chain_steps<=0; bytes_left<=0; sectors_per_cluster<=0;
            cluster_sector<=0; cluster_shift<=0; wanted<=0; found<=0;
            chain_is_file<=0; probe_lba0<=0; fat_byte<=0;
            signature<=0; fat_capture_offset<=0; fat_value<=0;
            mbr_found<=0;take_partition<=0;mbr_base<=0;mbr_size<=0;
            job_kind<=0;job_offset<=0;job_length<=0;seek_left<=0;
            seeking<=0;first_payload<=0;font_cached<=0;font_cluster<=0;font_size<=0;
            sector_cached<=0;cached_lba<=0;
            overhead<=0;volume_end<=0;
        end else begin
            done<=0; file_open<=0;
            case(state)
                IDLE: if(start) begin
                    busy<=1; error<=0; error_code<=0; wanted<=file_index; found<=0;
                    last_mode<=0;if(select_last)last_mode<=1;last_found<=0;
                    job_kind<=ENABLE_AUX!=0 ? aux_kind : 0;
                    job_offset<=ENABLE_AUX!=0 && aux_kind!=0 ? aux_offset : 0;
                    job_length<=aux_length;first_payload<=1;
                    if(ENABLE_AUX!=0 && aux_kind==2 && font_cached)begin
                        // Volume geometry and font head remain valid until reset.
                        // Preserve a separate starting cluster; every range has
                        // its own traversal and never reuses the image position.
                        if(aux_offset>=font_size || aux_length==0)fail(8'h37);
                        else begin
                            short_name<="FONT16  BIN";file_size<=font_size;opened_index<=0;
                            bytes_left<=(font_size-aux_offset)<aux_length ? font_size-aux_offset : {16'd0,aux_length};
                            file_open<=1;cluster<=font_cluster;cluster_sector<=0;chain_steps<=0;
                            seeking<=aux_offset!=0;seek_left<=aux_offset;
                            state<=aux_offset!=0 ? SEEK_FILE : FILE_LOAD;
                        end
                    end else begin
                        partition_lba<=0; partition_size<=0;
                        probe_lba0<=1;read_sector(0,BOOT);
                    end
                end
                REQUEST: if(req_ready) begin
                    rx_offset<=0;state<=RECEIVE;sector_cached<=0;
                    if(return_state==BOOT)begin mbr_found<=0;take_partition<=0;mbr_base<=0;mbr_size<=0;end
                end
                RECEIVE: if(sec_error) fail(8'h30);
                    else if(sec_valid) begin
                        if(return_state==BOOT || return_state==BPB_PREP) begin
                            if(rx_offset<64) boot[rx_offset[5:0]]<=sec_data;
                            if(rx_offset==510) signature[7:0]<=sec_data;
                            if(rx_offset==511) signature[15:8]<=sec_data;
                        end
                        if(return_state==BOOT && rx_offset>=446 && rx_offset<510)begin
                            if(mbr_offset[3:0]==4)begin
                                take_partition<=!mbr_found && (sec_data==8'h0b || sec_data==8'h0c);
                                if(sec_data==8'h0b || sec_data==8'h0c)mbr_found<=1;
                            end
                            if(take_partition && mbr_offset[3:2]==2)mbr_base<={sec_data,mbr_base[31:8]};
                            if(take_partition && mbr_offset[3:2]==3)mbr_size<={sec_data,mbr_size[31:8]};
                        end
                        if(sec_last!=(rx_offset==511)) fail(8'h31);
                        else if(rx_offset==511)begin
                            state<=CACHE_PRIME;sector_cached<=1;cached_lba<=req_lba;
                        end
                        else rx_offset<=rx_offset+1'b1;
                    end
                CACHE_PRIME: state<=return_state;
                BOOT: if(signature!=16'haa55) fail(8'h32);
                    else if(le16(11)==512 && boot[13]!=0 && le16(17)==0 && le16(22)==0)
                        state<=BPB_PREP; // Candidate only: full BPB and geometry must pass.
                    else state<=MBR;
                MBR: begin
                        // Fall back at most once. The cache still contains LBA0.
                        probe_lba0<=0;
                        // First supported primary MBR partition; no GPT/extended partitions.
                        if(!mbr_found) fail(8'h33);
                        else begin
                            partition_lba<=mbr_base;
                            partition_size<=mbr_size;
                            if(mbr_base==0 ||
                               mbr_size==0 ||
                               ({32'd0,mbr_base}+
                                {32'd0,mbr_size})>64'h100000000)
                                fail(8'h33);
                            else read_sector(mbr_base,BPB_PREP);
                        end
                    end
                BPB_PREP:begin
                    overhead<={48'd0,reserved_sectors}+{31'd0,fat_span};
                    volume_end<={32'd0,partition_lba}+{32'd0,bpb_total};
                    state<=BPB;
                end
                BPB: if(signature!=16'haa55 || le16(11)!=512 || le16(17)!=0 ||
                       le16(19)!=0 || le16(22)!=0 || le16(42)!=0 ||
                       reserved_sectors==0 || bpb_fat==0 || boot[16]==0 || boot[16]>2 ||
                       boot[13]==0 || boot[13]>128 || ((boot[13] & (boot[13]-1'b1))!=0) ||
                       overhead>={32'd0,bpb_total} || volume_end>64'h100000000 ||
                       (partition_size!=0 && bpb_total>partition_size) ||
                       (ext_flags[7] && ext_flags[3:0]>=boot[16])) begin
                        if(probe_lba0 && mbr_found) state<=MBR;
                        else fail(8'h34);
                    end
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
                             (le32(44)&32'h0fffffff)>cluster_count+1) begin
                        if(probe_lba0 && mbr_found) state<=MBR;
                        else fail(8'h34);
                    end
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
                    if(dir_entry[0]==0) begin
                        if(last_mode)finish_last();else fail(8'h36);
                    end else if(dir_entry[0]!=8'he5 &&
                            (dir_entry[11]&8'h18)==0 &&
                            dir_entry[11]!=8'h0f && requested_entry) begin
                        if(last_mode)begin
                            if(found>=17'd65536)fail(8'h39);
                            else begin
                                last_found<=1;last_cluster<=entry_cluster;last_size<=entry_size;
                                last_name<=entry_name;last_number<=found[15:0];
                                found<=found+1'b1;state<=DIR_NEXT;
                            end
                        end else if(aux_job || found=={1'b0,wanted})
                            open_image(entry_cluster,entry_size,entry_name,wanted);
                        else begin found<=found+1'b1;state<=DIR_NEXT;end
                    end else state<=DIR_NEXT;
                end
                DIR_NEXT: if(dir_offset!=480) begin
                        dir_offset<=dir_offset+32;return_state<=DIR_CAPTURE;state<=CACHE_PRIME;
                    end
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
                        if(ENABLE_AUX!=0 && seeking && sector_cached && cached_lba==fat_base+(cluster>>7))begin
                            return_state<=FAT_CAPTURE;state<=CACHE_PRIME;
                        end else read_sector(fat_base+(cluster>>7),FAT_CAPTURE);
                    end
                FAT_CAPTURE: begin
                    fat_value<={sector_byte,fat_value[31:8]};
                    if(fat_capture_offset==3) state<=FAT_NEXT;
                    else fat_capture_offset<=fat_capture_offset+1'b1;
                end
                FAT_NEXT: begin
                    if(fat_link>=32'h0ffffff8)begin
                        if(!chain_is_file && last_mode)finish_last();
                        else fail(chain_is_file ? 8'h38 : 8'h36);
                    end
                    else if(fat_link<2 || fat_link>cluster_count+1 ||
                            fat_link>=32'h0ffffff0 || fat_link==cluster) fail(8'h35);
                    else if(chain_steps>=cluster_count-1 ||
                            (!chain_is_file && chain_steps>=MAX_DIR_CLUSTERS-1)) fail(8'h39);
                    else begin
                        cluster<=fat_link; cluster_sector<=0; chain_steps<=chain_steps+1'b1;
                        state<=chain_is_file ? (seeking ? SEEK_FILE : FILE_LOAD) : DIR_LOAD;
                    end
                end
                SEEK_FILE: if(seek_left>={15'd0,cluster_bytes})begin
                        seek_left<=seek_left-{15'd0,cluster_bytes};chain_is_file<=1;state<=FAT_LOAD;
                    end else begin
                        cluster_sector<=seek_left[15:9];seeking<=0;state<=FILE_LOAD;
                    end
                FILE_LOAD: if(cluster_lba>={32'd0,partition_lba}+total_sectors) fail(8'h35);
                    else begin
                        out_offset<=aux_job && first_payload ? job_offset[8:0] : 0;
                        first_payload<=0;read_sector(cluster_lba[31:0],FILE_STREAM);
                    end
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
