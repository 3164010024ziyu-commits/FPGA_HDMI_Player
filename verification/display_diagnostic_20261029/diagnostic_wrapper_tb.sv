`timescale 1ns/1ps
module diagnostic_wrapper_tb;
    reg clk=0,rst_n=1,key_n=1;
    always #10 clk=~clk;
    wire [3:0] led;
    wire cs,sck,mosi,hclk,d0,d1,d2;
    hdmi_player_board_top #(.ENABLE_FADE(0),.DIAGNOSTIC_LEDS(1),.POWERUP_CYCLES(8),.DEBOUNCE_CYCLES(4)) dut(
        .SYS_CLK(clk),.Reset_n(rst_n),.KEY_LOAD_N(key_n),.KEY_SPECTRUM_N(1'b1),.KEY_AUTO_N(1'b1),.KEY_PREV_N(1'b1),.SW_AUDIO_N(1'b1),.SW_MUTE_N(1'b1),.KEY_NEXT_N(1'b1),.key_in(7'h7f),.key_img(4'hf),.LED(led),
        .sd_cs_n(cs),.sd_sck(sck),.sd_mosi(mosi),.sd_miso(1'b1),
        .HDMI_CLK_P(hclk),.HDMI_D0_P(d0),.HDMI_D1_P(d1),.HDMI_D2_P(d2));
    task cycles(input integer n);repeat(n)@(negedge clk);endtask
    task press;key_n=0;cycles(10);key_n=1;cycles(10);endtask
    initial begin
        wait(dut.board_reset_n);cycles(4);
        dut.u_player.memory_drive=1;cycles(4);
        if(led!==4'b0001)$fatal(1,"diag ready");
        dut.u_player.diag_drive=4'b0001;cycles(1);dut.u_player.diag_drive=0;cycles(8);
        if(led!==4'b0011)$fatal(1,"FIFO event missing or wrong LED");
        dut.u_player.diag_drive=4'b0010;cycles(1);dut.u_player.diag_drive=0;cycles(8);
        if(led!==4'b0111)$fatal(1,"timeout event missing or wrong LED");
        dut.u_player.diag_drive=4'b0100;cycles(1);dut.u_player.diag_drive=0;cycles(8);
        if(led!==4'b1111)$fatal(1,"refresh event missing or wrong LED");
        rst_n=0;#1;if(led!==0)$fatal(1,"diag reset");
        cycles(3);rst_n=1;wait(dut.board_reset_n);cycles(5);
        if(led!==4'b0001)$fatal(1,"diag flags did not clear");
        dut.u_player.diag_drive=4'b1000;cycles(1);dut.u_player.diag_drive=0;cycles(8);
        if(led!==4'b1001)$fatal(1,"load error event missing or wrong LED");
        $display("DIAGNOSTIC_LED_PASS fifo=LED2 timeout=LED3 load_refresh=LED4 sticky=1 reset=1");$finish;
    end
    initial begin #20000;$fatal(1,"wrapper timeout");end
endmodule

module hdmi_player_top #(parameter CLK_HZ=50000000,parameter ENABLE_AUDIO=0,parameter ENABLE_FADE=0,parameter ENABLE_SPECTRUM=0,parameter SPECTRUM_DB_CYCLES=262144,parameter FADE_STEP=1)(
    input audio_enable,audio_mute,output audio_error,output [7:0] audio_error_code,
input select_last,output [15:0] opened_file_index,
    input spectrum_key_n,input [6:0] key_in, input [3:0] key_img,
    input SYS_CLK,Reset_n,start,input [15:0] file_index,input [20:0] frame_base_addr,
    output load_ready,load_busy,load_done,load_error,output [7:0] load_error_code,
    output [3:0] debug_error_flags,
    output card_initialized,sd_cs_n,sd_sck,sd_mosi,input sd_miso,
    output memory_frame_write_done,LED,display_ready,display_underflow,
    output HDMI_CLK_P,HDMI_D2_P,HDMI_D1_P,HDMI_D0_P
);
    reg ready_drive=0,memory_drive=0,card_drive=0,display_drive=0,underflow_drive=0;
    reg [3:0] diag_drive=0;
    integer starts=0;
    always @(posedge SYS_CLK)if(Reset_n && start)begin
        if(!load_ready || file_index!==0 || frame_base_addr!==0)$fatal(1,"incorrect core configuration");
        starts=starts+1;
    end
    reg [1:0] fake_busy=0;
    reg fake_done=0;
    always @(posedge SYS_CLK) begin
        if(!Reset_n)begin fake_busy<=0;fake_done<=0;end
        else begin
            fake_done<=0;
            if(start)fake_busy<=2;
            else if(fake_busy!=0)begin fake_busy<=fake_busy-1'b1;if(fake_busy==1)fake_done<=1;end
        end
    end
    assign audio_error=0;assign audio_error_code=0;
assign opened_file_index=0;
    assign load_ready=Reset_n && ready_drive && fake_busy==0;assign load_busy=fake_busy!=0;assign load_done=fake_done;
    assign debug_error_flags=Reset_n ? diag_drive : 4'b0000;
    assign load_error=diag_drive[3];assign load_error_code=0;assign card_initialized=Reset_n && card_drive;
    assign LED=Reset_n && memory_drive;assign display_ready=Reset_n && display_drive;
    assign display_underflow=Reset_n && underflow_drive;assign memory_frame_write_done=0;
    assign {sd_cs_n,sd_sck,sd_mosi,HDMI_CLK_P,HDMI_D2_P,HDMI_D1_P,HDMI_D0_P}=7'b1011010;
endmodule
