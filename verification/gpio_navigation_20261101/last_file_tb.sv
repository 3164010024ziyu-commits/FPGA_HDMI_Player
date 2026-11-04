`timescale 1ns/1ps
module last_file_tb;
    reg clk=0; always #10 clk=~clk;
    reg rst_n=0,start=0;
    reg [15:0] file_index=0;
    reg select_last=0;wire [15:0] opened_index;
    wire busy,done,error,file_open,valid,last,req_valid,sec_ready;
    wire [7:0] error_code,data;
    wire [31:0] file_size,req_lba;
    wire [87:0] short_name;
    reg ready=0,req_ready=1,sec_valid=0,sec_last=0,sec_error=0;
    reg [7:0] sec_data;
    wire [1:0] aux_kind=0;wire [31:0] aux_offset=0;wire [15:0] aux_length=0;
 wire [63:0] match_name=64'd0;
    fat32_bmp_reader #(.MAX_DIR_CLUSTERS(8)) dut(.*);
    reg [7:0] card[0:4607],image[0:1249];
    integer map_index,read_offset=0,seen=0,cycles=0,cases=0,mode=0,requests=0;
    integer active_lba;
    reg pending=0,done_seen=0;
    reg [31:0] random_state=32'h976239ec;
    reg was_stalled=0;
    reg [8:0] held;
    function integer slot(input integer lba);
        if(mode==9 && lba==3405) slot=6;
        else if(mode==8 && lba==3286) slot=6;
        else if(mode==8 && lba==3294) slot=8;
        else case(lba)
            0: slot=0; 2048: slot=1; 2080: slot=2; 2680: slot=3;
            3280: slot=4; 3281: slot=5; 3283: slot=6; 3287: slot=7;
            3284: slot=8; default: slot=-1;
        endcase
    endfunction
    always @(negedge clk) begin
        random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
        ready=random_state[1] || random_state[3];
        req_ready=!pending && random_state[2];
        sec_valid=0; sec_last=0; sec_error=0;
        if(pending && random_state[0]) begin
            if(mode==6 && active_lba==3283) begin sec_error=1; pending=0; end
            else begin
                sec_valid=1;
                sec_last=(read_offset==511 || (mode==7 && read_offset==19));
                map_index=slot(active_lba);
                if(map_index<0) $fatal(1,"unexpected sector %0d",active_lba);
                sec_data=card[map_index*512+read_offset];
            end
        end
    end
    always @(posedge clk) if(rst_n) begin
        cycles=cycles+1;
        if(cycles>500000) $fatal(1,"FAT watchdog");
        if(req_valid && req_ready) begin
            pending=1; active_lba=req_lba; read_offset=0; requests=requests+1;
        end
        if(sec_valid && sec_ready) begin
            if(sec_last) pending=0;
            else read_offset=read_offset+1;
        end
        if(file_open && (file_size!=1250 || short_name!=(opened_index==0 ? "FIRST   BMP" : "SECOND  BMP")))
            $fatal(1,"file metadata");
        if(was_stalled && (!valid || {last,data}!==held)) $fatal(1,"FAT stalled stream changed");
        was_stalled=valid && !ready; held={last,data};
        if(valid && ready) begin
            if(data!==image[seen] || last!==(seen==1249)) $fatal(1,"FAT byte %0d",seen);
            seen=seen+1;
        end
        if(done) done_seen=1;
    end
    task run_case(input integer idx,err);
        begin
            cases=cases+1; $display("LAST_CASE n=%0d idx=%0d mode=%0d",cases,idx,mode); seen=0; done_seen=0; requests=0;
            @(negedge clk); file_index=idx<0 ? 0 : idx;select_last=idx<0;start=1;
            @(negedge clk); start=0;
            // The previous error is cleared on the start edge.
            wait(done_seen || error);
            if(err==0) begin
                if(error || seen!=1250) $fatal(1,"FAT success failed code=%h seen=%0d",error_code,seen);
            end else if(!error || error_code!=err) $fatal(1,"FAT error expected=%h actual=%h",err,error_code);
            repeat(5) @(negedge clk);
        end
    endtask
    task reload;
        begin $readmemh("tb/storage/vectors/card.hex",card); end
    endtask
    initial begin
        reload(); $readmemh("tb/storage/vectors/image.hex",image);
        repeat(4) @(negedge clk); rst_n=1;
        run_case(0,0); run_case(1,0); run_case(2,'h36);
        run_case(-1,0);if(opened_index!=1)$fatal(1,"last index from fragmented directory");
        run_case(0,0);if(opened_index!=0)$fatal(1,"last mode leaked into ordinary selection");
        // Directory end by FAT EOC without any zero first-byte entry.
        reload();
        for(integer q=2048;q<3072;q=q+32)if(card[q]==0)card[q]=8'he5;
        run_case(-1,0);if(opened_index!=1)$fatal(1,"last index at FAT EOC");
        reload();card[2048]=0;run_case(-1,'h36);
        reload();

        // The final 32-byte entry must be fully captured, then the next root
        // sector must replace it (no stale SFN/size/cluster bytes).
        reload();
        for(integer n=0;n<32;n=n+1) card[2048+480+n]=card[2048+n];
        card[2048]='he5;
        run_case(0,0); run_case(1,0);
        // Exercise each primary partition slot, including its final size byte.
        for(integer p=1;p<4;p=p+1) begin
            reload();
            for(integer n=0;n<16;n=n+1) begin
                card[446+p*16+n]=card[446+n]; card[446+n]=0;
            end
            run_case(0,0);
        end
        // FAT entry 127 occupies bytes 508..511. Its reserved high nibble
        // must be ignored and all four captured bytes must belong to this link.
        reload(); mode=9; card[2048+26]=127;
        card[1024+508]=9; card[1024+509]=0;
        card[1024+510]=0; card[1024+511]='hf0;
        run_case(0,0); mode=0;
        // FAT mirroring disabled, FAT #1 selected, FAT #0 poisoned.
        reload(); card[512+40]='h81; card[1024+20]=0; run_case(1,0);
        // FAT32 superfloppy with BPB at LBA 0, same absolute data placement.
        reload(); for(integer n=0;n<512;n=n+1) card[n]=card[512+n];
        card[14]='h20; card[15]='h08; // reserved=2080, so FAT remains at 2080
        card[32]='h40; card[33]='h1e; card[34]=1; card[35]=0; // total=73280
        run_case(1,0);
        // Two-sector clusters: cross both sector and fragmented cluster boundaries.
        reload(); mode=8; card[512+13]=2;
        card[512+32]='hb0; card[512+33]='h27; card[512+34]=2;
        card[458]='hb0; card[459]='h27; card[460]=2;
        run_case(1,0); mode=0;
        // One FAT copy. Move its base to 2680 by reserving 632 sectors;
        // the data region remains at 3280 and has the same valid FAT32 geometry.
        reload(); card[512+16]=1; card[512+14]='h78; card[512+15]=2;
        run_case(1,0);
        card[512+40]='h81; run_case(0,'h34); // FAT #1 cannot exist with one copy
        reload(); card[512+13]=3; run_case(0,'h34);
        reload(); card[512+12]=0; run_case(0,'h34);
        reload(); card[1024+20]='hff; card[1024+21]='hff; card[1024+22]='hff; card[1024+23]='h0f;
        run_case(0,'h38);
        reload(); card[1024+20]='hf7; card[1024+21]='hff; card[1024+22]='hff; card[1024+23]='h0f;
        run_case(0,'h35);
        reload(); card[1024+8]=2; run_case(1,'h35); // self loop in root chain
        reload(); mode=6; run_case(0,'h30); mode=0;
        reload(); mode=7; run_case(0,'h31); mode=0;
        reload(); card[510]=0; run_case(0,'h32);
        reload(); card[450]='h07; run_case(0,'h33);
        reload(); run_case(1,0);
        $display("PASS fat32_bmp_reader: %0d cases, fragmented files/root, stalls, corruption",cases);
        $finish;
    end
endmodule
