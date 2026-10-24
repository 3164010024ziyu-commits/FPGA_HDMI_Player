`timescale 1ns/1ps
module bmp_stream_decoder_tb;
    reg clk=0; always #10 clk=~clk;
    reg rst_n=0,start=0,abort=0;
    reg [31:0] file_size;
    reg [7:0] in_data;
    reg in_valid=0,in_last=0;
    wire in_ready,busy,done,error,meta_valid,top_down,pixel_valid;
    wire [7:0] error_code;
    wire [15:0] width,height,pixel_x,pixel_y,rgb565;
    wire [23:0] rgb;
    wire [31:0] addr;
    wire sof,eol,eof;
    reg pixel_ready=0;
    bmp_stream_decoder #(.MAX_WIDTH(1920),.MAX_HEIGHT(1080)) dut(
        .clk(clk),.rst_n(rst_n),.start(start),.abort(abort),.file_size(file_size),
        .in_data(in_data),.in_valid(in_valid),.in_last(in_last),.in_ready(in_ready),
        .busy(busy),.done(done),.error(error),.error_code(error_code),
        .meta_valid(meta_valid),.width(width),.height(height),.top_down(top_down),
        .pixel_valid(pixel_valid),.pixel_ready(pixel_ready),.pixel_rgb888(rgb),
        .pixel_rgb565(rgb565),.pixel_x(pixel_x),.pixel_y(pixel_y),.pixel_addr(addr),
        .pixel_sof(sof),.pixel_eol(eol),.pixel_eof(eof));
    byte unsigned image[0:1300000];
    integer w,h,depth,off,total,stride,seen,cycles=0,cases=0;
    integer row,col,k,b,expected_y;
    reg td,done_seen=0,check_pixels=0,was_stalled=0;
    reg [90:0] held;
    reg [23:0] expected_rgb;
    reg [31:0] random_state=32'h746381fe;
    wire [90:0] payload={rgb,addr,pixel_x,pixel_y,sof,eol,eof};
    always @(negedge clk) begin
        random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
        pixel_ready=random_state[0] || random_state[2];
    end
    always @(posedge clk) if(rst_n) begin
        cycles=cycles+1;
        if(cycles>6000000) $fatal(1,"BMP watchdog");
        if(done) done_seen=1;
        if(was_stalled && (!pixel_valid || payload!==held)) $fatal(1,"unstable stalled pixel");
        was_stalled=pixel_valid && !pixel_ready;
        held=payload;
        if(pixel_valid && pixel_ready && check_pixels) begin
            expected_y=td ? seen/w : h-1-seen/w;
            expected_rgb={8'(8'h80+seen/w+seen%w),8'(seen%w),8'(8'h30+seen/w)};
            if(rgb!==expected_rgb || pixel_x!==16'(seen%w) || pixel_y!==16'(expected_y) ||
               addr!==32'(expected_y*w+seen%w) || sof!==(seen==0) ||
               eol!==(seen%w==w-1) || eof!==(seen==w*h-1))
                $fatal(1,"BMP pixel %0d rgb=%h expected=%h xy=%0d,%0d",seen,rgb,expected_rgb,pixel_x,pixel_y);
            if(rgb565!=={rgb[23:19],rgb[15:10],rgb[7:3]}) $fatal(1,"RGB565");
            seen=seen+1;
        end
    end
    task put16(input integer a,input integer v);
        begin image[a]=v; image[a+1]=v>>8; end
    endtask
    task put32(input integer a,input integer v);
        begin for(integer n=0;n<4;n=n+1) image[a+n]=v>>(n*8); end
    endtask
    task build(input integer wi,hi,di,oi,input bit top,input integer tail);
        begin
            w=wi; h=hi; depth=di; off=oi; td=top;
            stride=((w*(depth/8)+3)/4)*4; total=off+stride*h+tail;
            for(k=0;k<total;k=k+1) image[k]=0;
            image[0]="B"; image[1]="M"; put32(2,total); put32(10,off);
            put32(14,40); put32(18,w); put32(22,top ? -h : h);
            put16(26,1); put16(28,depth); put32(34,stride*h);
            for(row=0;row<h;row=row+1) for(col=0;col<w;col=col+1) begin
                b=off+row*stride+col*(depth/8);
                image[b]=8'h30+row; image[b+1]=col; image[b+2]=8'h80+row+col;
                if(depth==32) image[b+3]=8'hee;
            end
        end
    endtask
    task run_case(input integer send_bytes,input integer size_arg,input integer expected_error);
        begin
            seen=0; done_seen=0; check_pixels=(expected_error==0); cases=cases+1;
            @(negedge clk); file_size=size_arg; start=1;
            @(negedge clk); start=0;
            for(integer n=0;n<send_bytes;n=n+1) begin
                repeat(random_state[5:4]==0 ? 2 : 0) @(negedge clk);
                in_data=image[n]; in_valid=1; in_last=(n==send_bytes-1);
                @(posedge clk);
                while(!in_ready && !error) @(posedge clk);
                @(negedge clk); in_valid=0; in_last=0;
                if(error) break;
            end
            wait(done_seen || error);
            if(expected_error==0) begin
                if(error || seen!=w*h) $fatal(1,"BMP success case failed code=%h pixels=%0d",error_code,seen);
            end else if(!error || error_code!=expected_error)
                $fatal(1,"BMP error expected=%h actual=%h",expected_error,error_code);
            repeat(4) @(negedge clk);
        end
    endtask
    initial begin
        repeat(4) @(negedge clk); rst_n=1;
        for(integer a=1;a<=8;a=a+1) begin
            build(a,3,24,54,0,0); run_case(total,total,0);
            build(a,3,24,70,1,5); run_case(total,total,0);
            build(a,2,32,1024,0,0); run_case(total,total,0);
            build(a,2,32,54,1,0); run_case(total,total,0);
        end
        build(5,3,24,54,0,0); image[0]=0; run_case(total,total,'h20);
        build(5,3,24,54,0,0); put16(28,16); run_case(total,total,'h21);
        build(5,3,24,54,0,0); put32(30,1); run_case(total,total,'h21);
        build(5,3,24,54,0,0); put32(18,0); run_case(total,total,'h22);
        build(5,3,24,54,0,0); put32(18,1921); run_case(total,total,'h22);
        build(5,3,24,54,0,0); put32(22,'h80000000); run_case(total,total,'h22);
        build(5,3,24,54,0,0); run_case(total,total-1,'h23);
        build(5,3,24,54,0,0); run_case(total-3,total,'h24);
        build(5,3,24,54,0,0); run_case(30,total,'h24);
        build(5,3,24,54,0,0); put32(10,53); run_case(total,total,'h21);
        build(5,3,24,54,0,0); put16(26,2); run_case(total,total,'h21);
        build(5,3,24,54,0,0); put32(14,124); run_case(total,total,'h21);
        build(5,3,24,54,0,0); put32(2,0); run_case(total,total,0);
        build(7,3,32,138,1,3); put32(14,124); run_case(total,total,0);
        build(5,3,24,54,0,0); run_case(total,total,0); // recovery after errors
        build(640,480,24,54,0,0); run_case(total,total,0);
        build(640,480,32,54,1,0); run_case(total,total,0);
        $display("PASS bmp_stream_decoder: %0d cases, randomized stalls and bubbles",cases);
        $finish;
    end
endmodule
