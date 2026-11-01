`timescale 1ns/1ps
module fat32_mbr_regression_tb;
    reg clk=0; always #10 clk=~clk;
    reg rst_n=0,start=0;
    reg [15:0] file_index=0;
    wire select_last=1'b0;wire [15:0] opened_index;
    wire busy,done,error,file_open,valid,last,req_valid,sec_ready;
    wire [7:0] error_code,data;
    wire [31:0] file_size,req_lba;
    wire [87:0] short_name;
    reg ready=0,req_ready=1,sec_valid=0,sec_last=0,sec_error=0;
    reg [7:0] sec_data;
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
        if(cycles>600000) $fatal(1,"FAT watchdog");
        if(req_valid && req_ready) begin
            pending=1; active_lba=req_lba; read_offset=0; requests=requests+1;
        end
        if(sec_valid && sec_ready) begin
            if(sec_last) pending=0;
            else read_offset=read_offset+1;
        end
        if(file_open && (file_size!=1250 || short_name!=(file_index==0 ? "FIRST   BMP" : "SECOND  BMP")))
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
            cases=cases+1; seen=0; done_seen=0; requests=0;
            @(negedge clk); file_index=idx; start=1;
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
    task move_partition(input integer p);
        begin
            if(p!=0) for(integer n=0;n<16;n=n+1) begin
                card[446+p*16+n]=card[446+n];card[446+n]=0;
            end
        end
    endtask
    task partial_collision;
        begin card[11]=0;card[12]=2;card[13]=1;end
    endtask
    task geometry_collision;
        begin
            for(integer n=0;n<64;n=n+1) card[n]=card[512+n];
            card[32]=0;card[33]=0;card[34]=1;card[35]=0;
        end
    endtask
    task superfloppy;
        begin
            reload();
            for(integer n=0;n<512;n=n+1) card[n]=card[512+n];
            card[14]='h20;card[15]='h08;
            card[32]='h40;card[33]='h1e;card[34]=1;card[35]=0;
        end
    endtask
    task checked_case(input [8*64-1:0] label,input integer expected_error,expected_requests);
        begin
            run_case(0,expected_error);
            if(requests!=expected_requests) $fatal(1,"MBR_REGRESSION_FAIL case=%0s requests=%0d expected=%0d",label,requests,expected_requests);
            $display("MBR_REGRESSION_CASE_PASS case=%0d name=%0s requests=%0d bytes=%0d error=%h",cases,label,requests,seen,error_code);
        end
    endtask
    initial begin
        reload();$readmemh("tb/storage/vectors/image.hex",image);
        repeat(4) @(negedge clk);rst_n=1;
        checked_case("normal_mbr",0,8);
        for(integer p=0;p<4;p=p+1) begin
            reload();move_partition(p);partial_collision();
            checked_case("partial_bpb_collision_each_mbr_slot",0,8);
        end
        for(integer p=0;p<4;p=p+1) begin
            reload();move_partition(p);geometry_collision();
            checked_case("geometry_collision_each_mbr_slot",0,8);
        end
        // Valid FAT32 at LBA0 must still win over accidental partition bytes.
        superfloppy();card[450]='h0c;card[454]=0;card[455]='h10;
        card[456]=0;card[457]=0;card[458]=0;card[459]=4;
        checked_case("valid_superfloppy_with_fake_mbr",0,7);
        superfloppy();card[13]=3;
        checked_case("bad_superfloppy_bpb_no_fallback",'h34,1);
        superfloppy();card[32]=0;card[33]=0;card[34]=1;card[35]=0;
        checked_case("bad_superfloppy_geometry_no_fallback",'h34,1);
        reload();partial_collision();card[512+13]=3;
        checked_case("bad_partition_bpb_after_fallback_stops",'h34,2);
        reload();partial_collision();card[512+32]=0;card[512+33]=0;card[512+34]=1;card[512+35]=0;
        checked_case("bad_partition_geometry_after_fallback_stops",'h34,2);
        reload();partial_collision();for(integer n=0;n<4;n=n+1) card[454+n]=0;
        checked_case("invalid_partition_start_rejected",'h33,1);
        reload();partial_collision();card[454]=0;card[455]='hff;card[456]='hff;card[457]='hff;
        checked_case("overflow_partition_end_rejected",'h33,1);
        reload();card[450]='h07;
        checked_case("unsupported_partition_rejected",'h33,1);
        reload();checked_case("normal_mbr_recovers_after_errors",0,8);
        $display("MBR_REGRESSION_PASS cases=%0d",cases);
        $finish;
    end
endmodule
