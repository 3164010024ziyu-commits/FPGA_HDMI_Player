`timescale 1ns/1ps
// Independent fixture bytes, public handshake checks, no forced DUT signals.
module fat_sector_cache_tb;
    reg clk=0; always #10 clk=~clk;
    reg rst_n=0,start=0,select_last=0;
    reg [15:0] file_index=0;
    wire busy,done,error,file_open,valid,last,req_valid,sec_ready;
    wire [7:0] error_code,data;
    wire [31:0] file_size,req_lba;
    wire [87:0] short_name;
    wire [15:0] opened_index;
    reg ready=0,req_ready=0,sec_valid=0,sec_last=0,sec_error=0;
    reg [7:0] sec_data=0;
    fat32_bmp_reader #(.MIN_FILE_BYTES(1),.MAX_DIR_CLUSTERS(8)) dut(.*);
    reg [7:0] card[0:4607],image[0:1249];
    integer cycles=0,cases=0,seen=0,requests=0,active_lba=0,offset=0;
    integer expected_size=1250,sink_mode=0,stall_target=-1,stall_count=0;
    integer failure_mode=0,expected_index=0,last_transfer=-1;
    integer max_stream_gap=0,stalled_cycles=0,checked_bytes=0,reset_checks=0;
    reg pending=0,done_seen=0,was_stalled=0,checking=0;
    reg [8:0] held=0;
    reg [31:0] rng=32'h7f4a9c31;
    function integer slot(input integer lba);
        case(lba)
            0:slot=0;2048:slot=1;2080:slot=2;2680:slot=3;
            3280:slot=4;3281:slot=5;3283:slot=6;3287:slot=7;
            3284:slot=8;default:slot=-1;
        endcase
    endfunction
    always @(negedge clk) begin
        rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
        ready=1;
        if(sink_mode==1)ready=cycles[0];
        else if(sink_mode==2)ready=rng[0] && rng[3];
        else if(sink_mode==3 && seen==stall_target && stall_count<40)begin
            ready=0;stall_count=stall_count+1;
        end
        req_ready=!pending && (sink_mode!=2 || rng[2]);
        sec_valid=0;sec_last=0;sec_error=0;
        if(rst_n && pending && (sink_mode!=2 || rng[1]))begin
            if(failure_mode==1 && active_lba==3283 && offset==128)begin
                sec_error=1;pending=0;
            end else begin
                if(slot(active_lba)<0)$fatal(1,"unmapped LBA %0d",active_lba);
                sec_valid=1;sec_data=card[slot(active_lba)*512+offset];
                sec_last=offset==511 || (failure_mode==2 && active_lba==3283 && offset==19);
            end
        end
    end
    always @(posedge clk)begin
        cycles=cycles+1;
        if(cycles>2500000)$fatal(1,"cache regression watchdog");
        if(!rst_n)begin pending=0;offset=0;was_stalled=0;end
        else begin
            if(req_valid && req_ready)begin
                if(pending)$fatal(1,"overlapping sectors");
                pending=1;active_lba=req_lba;offset=0;requests=requests+1;
            end
            if(sec_valid && sec_ready)begin
                if(sec_last)pending=0;else offset=offset+1;
            end
            if(checking)begin
                if(file_open && (file_size!=expected_size || opened_index!=expected_index ||
                    short_name!==(expected_index==0 ? "FIRST   BMP":"SECOND  BMP")))
                    $fatal(1,"metadata changed case=%0d",cases);
                if(was_stalled && (!valid || {last,data}!==held))
                    $fatal(1,"stalled output changed byte=%0d",seen);
                was_stalled=valid && !ready;held={last,data};
                if(valid && !ready)stalled_cycles=stalled_cycles+1;
                if(valid && ready)begin
                    if(seen>=expected_size || data!==image[seen] || last!==(seen==expected_size-1))
                        $fatal(1,"byte mismatch case=%0d offset=%0d data=%h expected=%h last=%b",cases,seen,data,image[seen],last);
                    if(sink_mode==0 && seen%512!=0)begin
                        if(cycles-last_transfer>max_stream_gap)max_stream_gap=cycles-last_transfer;
                        if(cycles-last_transfer!=1)$fatal(1,"stream throughput gap=%0d",cycles-last_transfer);
                    end
                    last_transfer=cycles;seen=seen+1;checked_bytes=checked_bytes+1;
                end
                if(done)done_seen=1;
            end
        end
    end
    task load_fixture(input integer length,input integer invert);
        begin
            $readmemh("card.hex",card);$readmemh("image.hex",image);
            for(integer j=0;j<4;j=j+1)begin
                card[2048+28+j]=(length>>(j*8))&255;
                card[2560+28+j]=(length>>(j*8))&255;
            end
            if(invert)begin
                for(integer j=3072;j<4608;j=j+1)card[j]=card[j]^8'ha7;
                for(integer j=0;j<1250;j=j+1)image[j]=image[j]^8'ha7;
            end
        end
    endtask
    task launch(input integer length,input integer idx,input integer find_last);
        begin
            @(negedge clk);seen=0;done_seen=0;requests=0;was_stalled=0;
            last_transfer=-1;stall_count=0;expected_size=length;
            expected_index=find_last ? 1:idx;file_index=idx;select_last=find_last;checking=1;start=1;
            @(negedge clk);start=0;
        end
    endtask
    task finish_case(input integer expected_error);
        begin
            wait(done_seen || error);
            if(expected_error==0)begin
                if(error || seen!=expected_size)$fatal(1,"success failed size=%0d seen=%0d code=%h",expected_size,seen,error_code);
            end else if(!error || error_code!=expected_error)$fatal(1,"error expected=%h got=%h",expected_error,error_code);
            repeat(4)@(negedge clk);
            checking=0;cases=cases+1;
            $display("CACHE_CASE_PASS case=%0d size=%0d bytes=%0d mode=%0d stall=%0d index=%0d error=%h",cases,expected_size,seen,sink_mode,stall_target,expected_index,error_code);
        end
    endtask
    task normal_case(input integer length,input integer mode,input integer target,input integer idx,input integer find_last,input integer invert);
        begin
            load_fixture(length,invert);sink_mode=mode;stall_target=target;failure_mode=0;
            launch(length,idx,find_last);finish_case(0);
        end
    endtask
    task reset_dut;
        begin
            @(negedge clk);checking=0;rst_n=0;start=0;
            repeat(3)@(negedge clk);
            if(valid || req_valid || busy)$fatal(1,"reset did not clear control");
            rst_n=1;reset_checks=reset_checks+1;
            repeat(3)@(negedge clk);
        end
    endtask
    initial begin
        repeat(4)@(negedge clk);rst_n=1;
        normal_case(1,0,-1,0,0,0);
        normal_case(511,0,-1,0,0,0);
        normal_case(512,0,-1,0,0,0);
        normal_case(513,0,-1,0,0,0);
        normal_case(1023,0,-1,0,0,0);
        normal_case(1024,0,-1,0,0,0);
        normal_case(1250,0,-1,0,0,0);
        normal_case(1250,1,-1,0,0,0);
        normal_case(1250,2,-1,0,0,0);
        normal_case(1250,3,0,0,0,0);
        normal_case(1250,3,1,0,0,0);
        normal_case(1250,3,510,0,0,0);
        normal_case(1250,3,511,0,0,0);
        normal_case(1250,3,512,0,0,0);
        normal_case(1250,3,1023,0,0,0);
        normal_case(1250,3,1249,0,0,0);
        normal_case(1250,0,-1,1,0,0);
        normal_case(1250,2,-1,0,1,0);
        load_fixture(1250,0);sink_mode=0;failure_mode=1;launch(1250,0,0);finish_case('h30);
        load_fixture(1250,0);failure_mode=2;launch(1250,0,0);finish_case('h31);
        normal_case(1250,0,-1,0,0,1);
        // Reset during an in-flight sector, then overwrite with different data.
        load_fixture(1250,0);launch(1250,0,0);
        wait(pending && active_lba==3283 && offset==100);reset_dut();
        normal_case(1250,0,-1,0,0,1);
        // Reset while the last byte of a sector is held by backpressure.
        load_fixture(1250,0);sink_mode=3;stall_target=511;launch(1250,0,0);
        wait(valid && !ready && seen==511);reset_dut();
        normal_case(1250,2,-1,1,0,1);
        $display("FAT_SECTOR_CACHE_PASS cases=%0d bytes=%0d stall_cycles=%0d max_fast_stream_gap=%0d resets=%0d",cases,checked_bytes,stalled_cycles,max_stream_gap,reset_checks);
        $finish;
    end
endmodule
