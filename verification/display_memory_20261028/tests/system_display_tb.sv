`timescale 1ns/1ps
module system_display_tb;
    reg clk=0,rst_n=0,start=0;
    always #10 clk=~clk;
    wire ready,busy,done,error,initialized,mem_done,led,display_ready,underflow;
    wire [7:0] error_code;
    wire cs,sck,mosi,miso,hclk,hd0,hd1,hd2;
    integer reads,commands;
    hdmi_player_top #(.INIT_HALF_PERIOD(3),.READ_HALF_PERIOD(2)) dut(
        .SYS_CLK(clk),.Reset_n(rst_n),.key_img(4'hf),.start(start),.file_index(16'd0),.frame_base_addr(21'd256),
        .load_ready(ready),.load_busy(busy),.load_done(done),.load_error(error),.load_error_code(error_code),.card_initialized(initialized),
        .sd_cs_n(cs),.sd_sck(sck),.sd_mosi(mosi),.sd_miso(miso),.memory_frame_write_done(mem_done),.LED(led),
        .display_ready(display_ready),.display_underflow(underflow),.HDMI_CLK_P(hclk),.HDMI_D0_P(hd0),.HDMI_D1_P(hd1),.HDMI_D2_P(hd2)
    );
    sd_spi_card_model card(.rst_n(dut.storage_reset_n),.cs_n(cs),.sck(sck),.mosi(mosi),.miso(miso),
        .high_capacity(1'b1),.corrupt_crc(1'b0),.suppress_token(1'b0),.bad_token(1'b0),.bad_cmd8(1'b0),.suppress_response(1'b0),
        .reads(reads),.commands(commands));
    integer pixels=0,frames=0,source_pixels=0,tag0=1,tag1=2;
    reg expected_error=0;
    reg [23:0] expected;
    integer x,y,tag;
    always @(posedge clk)begin
        if(dut.pixel_transfer)source_pixels=source_pixels+1;
        if(error && !expected_error)$fatal(1,"system load error=%h",error_code);
    end
    always @(posedge dut.display_clk)begin
        if(dut.display_reset_n && dut.u_display.VGA_DE && display_ready)begin
            x=dut.u_display.VGA_X;y=dut.u_display.VGA_Y;
            if(underflow || !dut.display_valid)$fatal(1,"system display underrun xy=%0d,%0d",x,y);
            tag=dut.u_memory.front_base==256?tag0:tag1;
            expected=(x<dut.u_memory.front_width && y<dut.u_memory.front_height)?
                (tag*24'h10000+y*dut.u_memory.front_width+x):0;
            if(dut.u_display.VGA_D!==expected)$fatal(1,"system pixel mismatch xy=%0d,%0d got=%h expected=%h",x,y,dut.u_display.VGA_D,expected);
            if($isunknown({hclk,hd0,hd1,hd2}))$fatal(1,"unknown HDMI output");
            pixels=pixels+1;
            if(x==639 && y==479)begin frames=frames+1;$display("SYSTEM_FRAME_RESULT frame=%0d pixels=%0d",frames,pixels);end
        end
    end
    task fixture(input integer w,h,t);
        integer off,n,row_bytes;
        off=6*512;row_bytes=((w*3+3)/4)*4;
        card.card[off+18]=w;card.card[off+19]=0;card.card[off+20]=0;card.card[off+21]=0;
        card.card[off+22]=(-h)&255;card.card[off+23]=8'hff;card.card[off+24]=8'hff;card.card[off+25]=8'hff;
        for(n=0;n<w*h;n=n+1)begin
            card.card[off+54+(n/w)*row_bytes+(n%w)*3]=n&255;
            card.card[off+55+(n/w)*row_bytes+(n%w)*3]=0;
            card.card[off+56+(n/w)*row_bytes+(n%w)*3]=t;
        end
    endtask
    task launch;
        wait(ready);@(negedge clk);start=1;@(negedge clk);start=0;
    endtask
    initial begin
        #2;fixture(8,4,1);#100;rst_n=1;
        launch();wait(ready);wait(frames>=1);
        fixture(16,8,2);launch();wait(ready);wait(frames>=2);
        // A non-four-aligned image must report E1, reinitialize storage,
        // preserve the front image, and permit a fresh successful request.
        expected_error=1;fixture(7,4,7);launch();
        wait(error);if(error_code!==8'hE1)$fatal(1,"expected E1 got=%h",error_code);
        wait(ready);
        fixture(4,2,3);tag0=3;launch();
        wait(!error);expected_error=0;wait(ready);wait(frames>=3);
        wait(dut.u_memory.front_base==256 && dut.u_display.VGA_Y==1 && dut.u_display.VGA_X==4);
        @(posedge dut.display_clk);
        if(source_pixels!=32+128+8)$fatal(1,"unexpected accepted source count=%0d",source_pixels);
        $display("SYSTEM_DISPLAY_PASS source_pixels=%0d display_pixels=%0d frames=%0d spi_reads=%0d malformed_width_recovered=1 real_storage_hdmi=1",source_pixels,pixels,frames,reads);
        $finish;
    end
    initial begin #110000000;$fatal(1,"system timeout ready=%b error=%b frames=%0d",ready,error,frames);end
endmodule
